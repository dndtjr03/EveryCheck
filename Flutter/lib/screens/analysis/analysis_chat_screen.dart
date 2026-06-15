import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../config/app_theme.dart';
import '../../local/analysis_repository.dart';
import '../../models/analysis_local.dart';
// 백엔드 경유로 변경: Flutter 앱에 Gemini API 키가 박히지 않도록 함.
// 기존 `gemini_service.dart`는 보존(폐기 안 함) — `GeminiChatTurn` 타입은 그대로 재사용.
import '../../services/analysis_proxy_service.dart';
import '../../services/gemini_service.dart' show GeminiChatTurn;
import '../report/report_screen.dart';

/// 분석 채팅 화면.
///
/// 흐름:
///   1) 진입 직후 "분석 시작하기" 버튼이 보임 (C-2)
///   2) 버튼을 누르면 모든 사진을 순차로 Gemini에 보내며 결과를 채팅 메시지로 누적
///   3) 모든 사진 분석 끝나면 요약 메시지 + 사용자 양방향 질문 가능 (B-2)
///   4) 첫 분석 완료 시 "해당 내용과 판례, 법례를 바탕으로 PDF를 생성해드릴까요?" 다이얼로그
class AnalysisChatScreen extends StatefulWidget {
  final int analysisId;
  const AnalysisChatScreen({super.key, required this.analysisId});

  @override
  State<AnalysisChatScreen> createState() => _AnalysisChatScreenState();
}

class _AnalysisChatScreenState extends State<AnalysisChatScreen> {
  final _repo = AnalysisRepository.instance;
  final _ai = AnalysisProxyService.instance;
  final _scroll = ScrollController();
  final _input = TextEditingController();

  AnalysisSession? _session;
  List<DamagePhoto> _photos = [];
  List<ChatMessage> _messages = [];
  bool _busy = true;
  bool _analyzing = false;
  bool _waitingReply = false;
  bool _pdfPrompted = false; // PDF 유도 다이얼로그 1회만

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = await _repo.getAnalysis(widget.analysisId);
    final photos = await _repo.listPhotos(widget.analysisId);
    final messages = await _repo.listMessages(widget.analysisId);
    if (!mounted) return;
    setState(() {
      _session = session;
      _photos = photos;
      _messages = messages;
      _busy = false;
    });

    // 메시지 0개 + 사진 있으면 환영 메시지 추가
    if (messages.isEmpty && photos.isNotEmpty) {
      await _addSystem(
        '${photos.length}장의 사진이 준비되었어요.\n'
        '아래 [분석 시작하기] 버튼을 눌러 AI 분석을 시작해주세요.',
      );
    }
  }

  Future<void> _addSystem(String text) async {
    final id = await _repo.addMessage(
      analysisId: widget.analysisId,
      role: ChatRole.system,
      content: text,
    );
    if (!mounted) return;
    setState(() {
      _messages.add(ChatMessage(
        id: id,
        analysisId: widget.analysisId,
        role: ChatRole.system,
        content: text,
        createdAt: DateTime.now(),
      ));
    });
    _scrollToBottom();
  }

  Future<void> _addMessage(ChatRole role, String content, {int? photoId}) async {
    final id = await _repo.addMessage(
      analysisId: widget.analysisId,
      role: role,
      content: content,
      photoId: photoId,
    );
    if (!mounted) return;
    setState(() {
      _messages.add(ChatMessage(
        id: id,
        analysisId: widget.analysisId,
        role: role,
        content: content,
        photoId: photoId,
        createdAt: DateTime.now(),
      ));
    });
    _scrollToBottom();
  }

  /// S3 public URL에서 사진 바이트를 직접 다운로드.
  /// 같은 사진을 여러 번 사용하는 호출자는 결과를 캐시해 사용해야 함.
  /// 15초 내 응답 없으면 TimeoutException 던짐 (네트워크 hang 차단용).
  Future<Uint8List> _fetchPhotoBytes(DamagePhoto photo) async {
    final uri = Uri.parse(photo.s3Url);
    final http.Response resp;
    try {
      resp = await http
          .get(uri)
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw StateError('사진 다운로드 실패 ($e): ${photo.s3Url}');
    }
    if (resp.statusCode != 200) {
      throw StateError(
          '사진 다운로드 실패 (${resp.statusCode}): ${photo.s3Url}');
    }
    return resp.bodyBytes;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── 1) 분석 시작: 모든 사진 순차 분석 ────────────────────────────────────

  Future<void> _startAnalysis() async {
    if (_analyzing) return;
    if (!AnalysisProxyService.isConfigured) {
      _toast('백엔드 URL이 설정되지 않았습니다.\n'
          'AppConfig.baseUrl 또는 --dart-define=API_BASE_URL 을 확인해주세요.');
      return;
    }

    setState(() => _analyzing = true);
    await _repo.updateAnalysisStatus(
        widget.analysisId, AnalysisStatus.inProgress);

    // 입주/퇴거 분리. 비교 모드 vs 단독 모드 결정.
    final moveIns = _photos.where((p) => p.group == PhotoGroup.moveIn).toList();
    final moveOuts =
        _photos.where((p) => p.group == PhotoGroup.moveOut).toList();
    final useBaseline = moveIns.isNotEmpty && moveOuts.isNotEmpty;

    // baseline 비교에서는 퇴거 사진만 분석 대상, 입주 사진은 비교용으로만 사용.
    final targets = useBaseline ? moveOuts : _photos;

    await _addMessage(
      ChatRole.ai,
      useBaseline
          ? '🔍 분석을 시작합니다. 입주 사진 ${moveIns.length}장과 퇴거 사진 '
              '${moveOuts.length}장을 비교해 "새로 생긴 손상"만 식별할게요.'
          : '🔍 분석을 시작합니다. 사진 ${_photos.length}장을 차례로 확인할게요.\n'
              '(입주 사진이 없어 비교 없이 단독 분석합니다.)',
    );

    // 입주 사진들 bytes를 한 번만 미리 다운로드해 메모리에 보관 (퇴거 사진마다 재전송).
    // 다운로드 실패 시 채팅창에 명확한 에러 메시지를 띄우고 분석을 중단한다 (무한 로딩 방지).
    List<Uint8List> moveInBytes = const [];
    if (useBaseline) {
      try {
        moveInBytes = await Future.wait(moveIns.map(_fetchPhotoBytes));
      } catch (e) {
        await _addMessage(
          ChatRole.ai,
          '⚠️ 입주 사진을 불러오지 못해 분석을 중단합니다.\n원인: $e',
        );
        await _repo.updateAnalysisStatus(
            widget.analysisId, AnalysisStatus.pending);
        if (mounted) setState(() => _analyzing = false);
        return;
      }
    }

    final results = <Map<String, dynamic>>[];
    int totalCost = 0;

    for (int i = 0; i < targets.length; i++) {
      final photo = targets[i];
      try {
        final bytes = await _fetchPhotoBytes(photo);
        final Map<String, dynamic> raw;
        if (useBaseline) {
          raw = await _ai.analyzePhotoWithBaseline(
            moveOutBytes: bytes,
            moveInBytesList: moveInBytes,
          );
        } else {
          raw = await _ai.analyzePhoto(bytes);
        }
        await _repo.markPhotoAnalyzed(widget.analysisId, photo.id, raw);
        results.add(raw);

        final cost = (raw['cost'] as num?)?.toInt() ?? 0;
        // 기존 손상(임차인 부담 가능성 낮음)은 총액에서 제외.
        final isNew = raw['is_new'];
        if (isNew != false) {
          totalCost += cost;
        }

        final part = raw['part'] ?? '미상';
        final dtype = raw['damage_type'] ?? '미상';
        final conf = ((raw['confidence'] as num?) ?? 0).toDouble();
        final reason = raw['reason'] ?? '추가 설명 없음';
        final matchedIdx = raw['matched_move_in_index'];

        // 비교 결과 라벨
        final String verdict;
        if (isNew == true) {
          verdict = '🆕 새로 생긴 손상 — 임차인 부담 가능성 ↑';
        } else if (isNew == false) {
          verdict = '🟢 입주 시 이미 있던 손상 — 임차인 부담 없음';
        } else if (useBaseline) {
          verdict = '🟡 판단 보류 (입주 사진과 매칭 어려움)';
        } else {
          verdict = '';
        }

        final matchedLine = (useBaseline && matchedIdx is int)
            ? '- 비교한 입주 사진: $matchedIdx번\n'
            : '';

        final groupLabel = useBaseline ? '퇴거' : photo.group.label;
        final msg = '''
📸 $groupLabel 사진 ${i + 1}/${targets.length}
${verdict.isNotEmpty ? '$verdict\n' : ''}- 부위: $part
- 손상: $dtype
- 추정 수리비: ${_won(cost)}
- 확신도: ${(conf * 100).toStringAsFixed(0)}%
$matchedLine
$reason
''';
        await _addMessage(ChatRole.ai, msg.trim(), photoId: photo.id);
      } catch (e) {
        await _addMessage(
          ChatRole.ai,
          '⚠️ ${photo.group.label} 사진 ${i + 1} 분석 실패: $e',
          photoId: photo.id,
        );
      }
    }

    // 요약. 비교 모드면 "새 손상 / 기존 손상 / 보류" 분포를 따로 보여준다.
    int newDamage = 0;
    int oldDamage = 0;
    int unclear = 0;
    for (final r in results) {
      switch (r['is_new']) {
        case true:
          newDamage++;
          break;
        case false:
          oldDamage++;
          break;
        default:
          unclear++;
      }
    }

    final summary = useBaseline
        ? '''
✅ 비교 분석 완료
- 입주 사진: ${moveIns.length}장 (baseline)
- 퇴거 사진: ${targets.length}장 (분석)
- 🆕 새 손상: $newDamage건
- 🟢 입주 시부터 있던 손상: $oldDamage건
- 🟡 판단 보류: $unclear건
- 추정 임차인 부담액: ${_won(totalCost)} (새 손상만 합산)
'''
        : '''
✅ 사진 분석 완료
- 총 사진: ${_photos.length}장 (성공 ${results.length}건)
- 추정 총 수리비: ${_won(totalCost)}
''';
    await _addMessage(ChatRole.ai, summary.trim());

    await _repo.updateAnalysisStatus(
      widget.analysisId,
      AnalysisStatus.completed,
      summary: summary,
      estimatedCost: totalCost,
    );

    // 위젯 메모리상의 _session 도 같이 갱신해야 build()에서 채팅 입력창이 즉시 활성화됨.
    // (이전엔 DB만 바뀌고 _session 은 그대로라 앱 재시작 전엔 입력창이 안 보였음)
    final refreshed = await _repo.getAnalysis(widget.analysisId);
    if (!mounted) return;
    setState(() {
      _session = refreshed;
    });

    // AI가 사용자에게 질문 (사용자 입력 유도)
    //
    // 흐름:
    //   사진 분석 결과 출력 → AI 질문 → 사용자 답변 → _sendUserMessage()에서 종합 응답 → PDF 유도
    final aiQuestion = _buildFollowupQuestion(results);
    await _addMessage(ChatRole.ai, aiQuestion);

    if (!mounted) return;
    setState(() => _analyzing = false);

    // 여기서는 PDF 유도하지 않음. 사용자 답변 → 종합 응답 후에 1회만 띄움.
  }

  /// 분석 결과를 토대로 사용자에게 "어떤 부분이 가장 걱정되는지" 자연어 질문 생성.
  /// 가장 신뢰도 높은 손상 1~2개를 짚어주면서 사용자 의견을 묻는다.
  String _buildFollowupQuestion(List<Map<String, dynamic>> results) {
    if (results.isEmpty) {
      return '분석 결과가 충분치 않은데, 어느 부위가 가장 신경 쓰이시는지 한 줄로 알려주실 수 있을까요?';
    }
    // 확신도 내림차순 정렬해서 상위 2개 짚기
    final sorted = [...results]
      ..sort((a, b) => ((b['confidence'] as num?) ?? 0)
          .toDouble()
          .compareTo(((a['confidence'] as num?) ?? 0).toDouble()));
    final top = sorted.take(2).toList();
    final highlights = top
        .map((r) => '"${r['part'] ?? '미상'}의 ${r['damage_type'] ?? '손상'}"')
        .join(', ');

    return '''
🤔 분석 결과 중 $highlights 부분이 임차인 부담 여지가 있어 보여서 고민 중이에요.

혹시 사용자님께서 가장 걱정되시는 부위나, 임대인이 부당하게 청구한다고 느끼시는 부분이 있으면 알려주세요. 거주 기간이나 사용 습관(예: "5년 살았어요", "흡연자가 있었어요")도 같이 적어주시면 그 맥락까지 반영해서 최종 의견을 드릴게요.
''';
  }

  // ── 2) 사용자 후속 질문 → Gemini 채팅 ────────────────────────────────────

  Future<void> _sendUserMessage() async {
    final text = _input.text.trim();
    if (text.isEmpty || _waitingReply) return;
    _input.clear();

    if (!AnalysisProxyService.isConfigured) {
      _toast('백엔드 URL이 설정되지 않아 답변할 수 없어요.');
      return;
    }

    await _addMessage(ChatRole.user, text);

    setState(() => _waitingReply = true);
    try {
      final history = _messages
          .where((m) => m.role != ChatRole.system)
          .where((m) => !m.content.startsWith('📸')) // 사진 결과는 컨텍스트로만 별도 전달
          .map((m) => GeminiChatTurn(
                role: m.role == ChatRole.user ? 'user' : 'model',
                text: m.content,
              ))
          .toList();

      // 사진 분석 결과를 system context로 압축
      final summaryCtx =
          _session?.summary ?? '아직 분석 결과 요약이 없습니다.';

      final reply = await _ai.chat(
        history: history.take(history.length - 1).toList(),
        latestUserMessage: text,
        systemContext: '''
당신은 한국 임대차 분쟁 자문 보조 AI "다봐드림"입니다.
국토교통부 가이드라인, 민법 제615조·제654조, 주택임대차보호법, 통상의 손모 법리(대법원 판례)를 근거로 한국어로 답합니다.
단정적 자문은 피하고 "가능성이 있다"같이 완곡하게 표현합니다.

[이번 분석 요약]
$summaryCtx
''',
      );

      await _addMessage(ChatRole.ai, reply);

      // 분석이 끝난 상태에서 사용자가 첫 답변을 보내고 AI가 응답한 직후 PDF 유도 (1회만)
      if (!_pdfPrompted &&
          _session?.status == AnalysisStatus.completed) {
        _pdfPrompted = true;
        // 다이얼로그가 너무 즉시 떠서 답변이 묻히지 않게 살짝 대기
        await Future.delayed(const Duration(milliseconds: 400));
        if (mounted) await _askPdf();
      }
    } catch (e) {
      await _addMessage(ChatRole.ai, '⚠️ 답변 생성 중 오류: $e');
    } finally {
      if (mounted) setState(() => _waitingReply = false);
    }
  }

  // ── 3) PDF 생성 유도 다이얼로그 ──────────────────────────────────────────

  Future<void> _askPdf() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('📄 리포트 생성',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: const Text(
          '해당 내용과 판례, 법례를 바탕으로 PDF를 생성해드릴까요?',
          style: TextStyle(fontSize: 14, color: AppColors.n700, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('나중에', style: TextStyle(color: AppColors.n500)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('생성하기'),
          ),
        ],
      ),
    );
    if (go == true && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReportScreen(analysisId: widget.analysisId),
        ),
      );
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _won(int v) =>
      NumberFormat.currency(locale: 'ko_KR', symbol: '₩', decimalDigits: 0)
          .format(v);

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final canStart = !_analyzing &&
        _session?.status != AnalysisStatus.completed &&
        _photos.isNotEmpty;
    final canChat = _session?.status == AnalysisStatus.completed;

    return Scaffold(
      appBar: AppBar(
        title: Text(_session?.contractAddr ?? '분석',
            style:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis),
        actions: [
          if (_session?.status == AnalysisStatus.completed)
            IconButton(
              tooltip: 'PDF 만들기',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ReportScreen(analysisId: widget.analysisId),
              )),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
              itemCount: _messages.length,
              itemBuilder: (_, i) => _MessageBubble(message: _messages[i]),
            ),
          ),
          if (canStart) _StartAnalysisBar(onStart: _startAnalysis),
          if (_analyzing) const _AnalyzingBar(),
          if (canChat) _ChatInputBar(
            controller: _input,
            onSend: _sendUserMessage,
            waiting: _waitingReply,
          ),
        ],
      ),
    );
  }
}

// ── 메시지 버블 ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    final isSystem = message.role == ChatRole.system;

    if (isSystem) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(message.content,
            style: const TextStyle(
                fontSize: 13, color: AppColors.primaryDark, height: 1.5)),
      );
    }

    final bg = isUser ? AppColors.primary : surfaceOf(context);
    final fg = isUser ? Colors.white : AppColors.n800;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          boxShadow: isUser
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                  ),
                ],
        ),
        child: Text(
          message.content,
          style: TextStyle(fontSize: 14, color: fg, height: 1.5),
        ),
      ),
    );
  }
}

// ── 분석 시작 바 ────────────────────────────────────────────────────────────

class _StartAnalysisBar extends StatelessWidget {
  final VoidCallback onStart;
  const _StartAnalysisBar({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: surfaceOf(context),
          border: Border(top: BorderSide(color: borderOf(context))),
        ),
        child: ElevatedButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('분석 시작하기'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 50),
            shape: const StadiumBorder(),
            textStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _AnalyzingBar extends StatelessWidget {
  const _AnalyzingBar();
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surfaceOf(context),
          border: Border(top: BorderSide(color: borderOf(context))),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('AI가 사진을 분석 중이에요...',
                style: TextStyle(fontSize: 13, color: AppColors.n700)),
          ],
        ),
      ),
    );
  }
}

// ── 채팅 입력 바 ───────────────────────────────────────────────────────────

class _ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool waiting;
  const _ChatInputBar({
    required this.controller,
    required this.onSend,
    required this.waiting,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: surfaceOf(context),
          border: Border(top: BorderSide(color: borderOf(context))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !waiting,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: waiting ? '답변 생성 중...' : '궁금한 점을 물어보세요',
                  filled: true,
                  fillColor: AppColors.n100,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              onPressed: waiting ? null : onSend,
              icon: waiting
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
