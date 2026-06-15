// 다봐드림 — 분석 로딩 화면.
//
// 디자인: claude.ai/design 핸드오프 (refined v3 — 앱 UI 톤 적용)
//   - 쿨 라이트 그레이 #F5F6FA 배경 + AppColors n-스케일
//   - 클립보드 오렌지(=AppColors.accent #FF7C45) 만 포인트
//   - 6단계 도트 인디케이터, 단계 전환 시 텍스트 크로스페이드
//   - 클립보드 + 펜 네이티브 애니메이션 (외부 자원 0개)
//
// 이 화면은 두 가지를 동시에 한다:
//   1) S3 업로드 → 백엔드 분석 등록 → Gemini 분석 → 결과 저장 파이프라인 실행
//   2) 위 단계를 6개 디자인 stage에 매핑해 시각화
// 완료 시 [AnalysisChatScreen] 으로 pushReplacement.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../local/analysis_repository.dart';
import '../../models/analysis_local.dart';
import '../../models/picked_photo.dart';
import '../../models/real_estate.dart';
import '../../services/analysis_proxy_service.dart';
import '../../services/photo_upload_service.dart';
import 'analysis_chat_screen.dart';

// ── 분석 파이프라인 단계 + 사용자 카피 ─────────────────────────────────────
enum AnalysisStage {
  uploading('사진을 안전하게 올리고 있어요', '안전한 연결로 업로드 중이에요'),
  detecting('손상된 부분을 찾고 있어요', 'AI가 사진을 자세히 살펴보고 있어요'),
  comparing('입주 사진과 비교하고 있어요', '입주 당시 모습과 차이를 확인 중이에요'),
  classifying('손상 항목을 정리하고 있어요', '새 손상과 기존 손상을 구분하고 있어요'),
  estimating('예상 수리비를 계산하고 있어요', '항목별 비용을 산정 중이에요'),
  reporting('리포트를 작성하고 있어요', '거의 다 됐어요');

  final String title;
  final String hint;
  const AnalysisStage(this.title, this.hint);
}

// ── 디자인 토큰 (AppColors와 일관) ──────────────────────────────────────
class _T {
  static const bg     = Color(0xFFF5F6FA); // AppColors.bg
  static const text   = Color(0xFF1E1B18); // AppColors.n800
  static const sub    = Color(0xFF5A534C); // AppColors.n600
  static const faint  = Color(0xFFC8C2B8); // AppColors.n300
  static const ink    = Color(0xFF1E1B18);
}

class AnalysisLoadingScreen extends StatefulWidget {
  final RealEstate contract;
  final List<PickedPhoto> moveInPhotos;
  final List<PickedPhoto> moveOutPhotos;

  const AnalysisLoadingScreen({
    super.key,
    required this.contract,
    required this.moveInPhotos,
    required this.moveOutPhotos,
  });

  @override
  State<AnalysisLoadingScreen> createState() => _AnalysisLoadingScreenState();
}

class _AnalysisLoadingScreenState extends State<AnalysisLoadingScreen> {
  final _repo = AnalysisRepository.instance;
  final _uploader = PhotoUploadService.instance;
  final _ai = AnalysisProxyService.instance;

  AnalysisStage _stage = AnalysisStage.uploading;
  bool _allDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  // ── 파이프라인 ──────────────────────────────────────────────────────────
  Future<void> _run() async {
    final allPhotos = [
      ...widget.moveInPhotos.map((p) => _Tagged(p, PhotoGroup.moveIn)),
      ...widget.moveOutPhotos.map((p) => _Tagged(p, PhotoGroup.moveOut)),
    ];
    final useBaseline =
        widget.moveInPhotos.isNotEmpty && widget.moveOutPhotos.isNotEmpty;

    try {
      // 1) 분석 세션 생성 + 업로드
      _setStage(AnalysisStage.uploading);
      final analysisId = await _repo.createAnalysis(
        contractId: widget.contract.id,
        contractAddr: widget.contract.address,
      );

      final uploaded = <_UploadedPhoto>[];
      int order = 0;
      for (final t in allPhotos) {
        final s3Url = await _uploadOne(t.photo, order);
        final photoId = await _repo.addPhoto(
          analysisId: analysisId,
          s3Url: s3Url,
          group: t.group,
          orderIndex: order,
        );
        uploaded.add(_UploadedPhoto(id: photoId, group: t.group, bytes: t.photo.bytes));
        order++;
      }

      // 2) 분석 시작 메시지
      await _repo.updateAnalysisStatus(analysisId, AnalysisStatus.inProgress);
      await _repo.addMessage(
        analysisId: analysisId,
        role: ChatRole.ai,
        content: useBaseline
            ? '🔍 분석을 시작합니다. 입주 사진 ${widget.moveInPhotos.length}장과 '
                '퇴거 사진 ${widget.moveOutPhotos.length}장을 비교해 '
                '"새로 생긴 손상"만 식별할게요.'
            : '🔍 분석을 시작합니다. 사진 ${allPhotos.length}장을 차례로 확인할게요.\n'
                '(입주 사진이 없어 비교 없이 단독 분석합니다.)',
      );

      if (!AnalysisProxyService.isConfigured) {
        throw StateError('백엔드 URL이 설정되지 않았습니다.');
      }

      // 3) Gemini 분석 — detecting / comparing
      _setStage(useBaseline ? AnalysisStage.comparing : AnalysisStage.detecting);

      final moveInBytesList = useBaseline
          ? uploaded
              .where((u) => u.group == PhotoGroup.moveIn)
              .map((u) => u.bytes)
              .toList()
          : const <Uint8List>[];
      final targets = useBaseline
          ? uploaded.where((u) => u.group == PhotoGroup.moveOut).toList()
          : uploaded;

      final analyses = <Map<String, dynamic>>[];
      for (int i = 0; i < targets.length; i++) {
        final u = targets[i];
        try {
          final raw = useBaseline
              ? await _ai.analyzePhotoWithBaseline(
                  moveOutBytes: u.bytes, moveInBytesList: moveInBytesList)
              : await _ai.analyzePhoto(u.bytes);
          await _repo.markPhotoAnalyzed(analysisId, u.id, raw);
          analyses.add(raw);
          await _addAnalysisMessage(analysisId, u.id, raw, useBaseline);
        } catch (e) {
          await _repo.addMessage(
            analysisId: analysisId,
            role: ChatRole.ai,
            content: '⚠️ 사진 ${i + 1} 분석 중 오류: $e',
            photoId: u.id,
          );
        }
      }

      // 4) 분류 + 비용 집계
      _setStage(AnalysisStage.classifying);
      await _short();
      _setStage(AnalysisStage.estimating);
      int totalCost = 0;
      for (final raw in analyses) {
        final cost = (raw['cost'] as num?)?.toInt() ?? 0;
        if (raw['is_new'] != false) totalCost += cost;
      }
      await _short();

      // 5) 리포트 작성
      _setStage(AnalysisStage.reporting);
      await _repo.addMessage(
        analysisId: analysisId,
        role: ChatRole.ai,
        content: '✅ 분석 완료. 예상 임차인 부담액: ${_won(totalCost)}\n'
            '아래에서 자유롭게 추가 질문해주세요.',
      );
      await _repo.updateAnalysisStatus(
        analysisId,
        AnalysisStatus.completed,
        estimatedCost: totalCost,
      );

      if (!mounted) return;
      setState(() => _allDone = true);
      // 완료 인디케이터를 잠깐 보여준 뒤 채팅으로 교체.
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AnalysisChatScreen(analysisId: analysisId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('분석 실패'),
          content: Text('$e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<String> _uploadOne(PickedPhoto photo, int order) async {
    final ext = p.extension(photo.file.path).isEmpty
        ? '.jpg'
        : p.extension(photo.file.path);
    final tmpDir = await getTemporaryDirectory();
    final tmpFile = File(p.join(
      tmpDir.path,
      'upload_${DateTime.now().microsecondsSinceEpoch}_$order$ext',
    ));
    await tmpFile.writeAsBytes(photo.bytes);
    try {
      final s3Url = await _uploader.uploadSingle(tmpFile);
      if (s3Url == null) {
        throw StateError('S3 업로드 실패: ${photo.file.name}');
      }
      return s3Url;
    } finally {
      try { await tmpFile.delete(); } catch (_) {}
    }
  }

  Future<void> _addAnalysisMessage(
    int analysisId,
    int photoId,
    Map<String, dynamic> raw,
    bool useBaseline,
  ) async {
    final cost = (raw['cost'] as num?)?.toInt() ?? 0;
    final part = raw['part'] ?? '미상';
    final dtype = raw['damage_type'] ?? '미상';
    final conf = ((raw['confidence'] as num?) ?? 0).toDouble();
    final reason = raw['reason'] ?? '추가 설명 없음';
    final isNew = raw['is_new'];

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
    final msg = [
      if (verdict.isNotEmpty) verdict,
      '부위: $part',
      '손상 종류: $dtype',
      '추정 수리비: ${cost}원',
      'AI 확신도: ${(conf * 100).toStringAsFixed(0)}%',
      '사유: $reason',
    ].join('\n');

    await _repo.addMessage(
      analysisId: analysisId,
      role: ChatRole.ai,
      content: msg,
      photoId: photoId,
    );
  }

  void _setStage(AnalysisStage s) {
    if (!mounted) return;
    setState(() => _stage = s);
  }

  Future<void> _short() => Future.delayed(const Duration(milliseconds: 400));

  String _won(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '₩${buf.toString()}';
  }

  // ── 시각 ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: _T.bg,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Hero(),
              const SizedBox(height: 24),
              _FadeText(
                text: _allDone ? '분석이 완료됐어요' : _stage.title,
                style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700,
                  color: _T.text, letterSpacing: -0.4, height: 1.35,
                ),
                maxWidth: 280,
              ),
              const SizedBox(height: 12),
              _FadeText(
                text: _allDone ? '결과를 확인해보세요' : _stage.hint,
                style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w400,
                  color: _T.sub, letterSpacing: -0.1, height: 1.5,
                ),
              ),
              const Spacer(),
              _DotIndicator(
                count: AnalysisStage.values.length,
                current: _stage.index,
                allDone: _allDone,
              ),
              const SizedBox(height: 18),
              const Text(
                '잠시만 기다려주세요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w400,
                  color: _T.faint, letterSpacing: -0.1,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// 디자인 핸드오프 — 시각 컴포넌트 (외부 자원 0)
// ════════════════════════════════════════════════════════════════════════

class _Hero extends StatelessWidget {
  const _Hero();
  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        children: [
          const Positioned.fill(child: _ClipboardAnimation()),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_T.bg.withOpacity(0), _T.bg],
                    stops: const [0.55, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DotIndicator extends StatelessWidget {
  final int count;
  final int current;
  final bool allDone;
  const _DotIndicator({
    required this.count,
    required this.current,
    required this.allDone,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            width: (!allDone && i == current) ? 24 : 4,
            height: 4,
            decoration: BoxDecoration(
              color: (allDone || i <= current) ? _T.ink : _T.faint,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      ],
    );
  }
}

class _FadeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final double? maxWidth;
  const _FadeText({required this.text, required this.style, this.maxWidth});

  @override
  State<_FadeText> createState() => _FadeTextState();
}

class _FadeTextState extends State<_FadeText> {
  late String _shown = widget.text;
  bool _visible = true;

  @override
  void didUpdateWidget(covariant _FadeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      setState(() => _visible = false);
      Future.delayed(const Duration(milliseconds: 180), () {
        if (!mounted) return;
        setState(() {
          _shown = widget.text;
          _visible = true;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.06),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: widget.maxWidth ?? double.infinity),
            child: Text(
              _shown,
              textAlign: TextAlign.center,
              style: widget.style,
            ),
          ),
        ),
      ),
    );
  }
}

class _ClipboardAnimation extends StatefulWidget {
  const _ClipboardAnimation();
  @override
  State<_ClipboardAnimation> createState() => _ClipboardAnimationState();
}

class _ClipboardAnimationState extends State<_ClipboardAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat();
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => CustomPaint(
        painter: _ClipboardPainter(t: _c.value),
        size: Size.infinite,
      ),
    );
  }
}

class _ClipboardPainter extends CustomPainter {
  final double t;
  _ClipboardPainter({required this.t});

  static const _orange    = Color(0xFFFF7C45); // AppColors.accent
  static const _paper     = Color(0xFFFFFFFF);
  static const _paperFold = Color(0xFFE2DDD6);
  static const _ink       = Color(0xFF1E1B18);
  static const _clip      = Color(0xFF3C3730);
  static const _clipHole  = Color(0xFF5A534C);
  static const _penBody   = Color(0xFF1E1B18);
  static const _penTip    = Color(0xFFA09890);
  static const _penAccent = Color(0xFFC8C2B8);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // 클립보드 보드
    final boardW = w * 0.42;
    final boardH = h * 0.78;
    final boardLeft = (w - boardW) / 2;
    final boardTop  = h * 0.18;
    final boardRect = Rect.fromLTWH(boardLeft, boardTop, boardW, boardH);
    canvas.drawRRect(
      RRect.fromRectAndRadius(boardRect, const Radius.circular(10)),
      Paint()..color = _orange,
    );

    // 흰 종이
    final paperInset = boardW * 0.07;
    final paperRect = Rect.fromLTWH(
      boardLeft + paperInset,
      boardTop  + paperInset * 0.9,
      boardW - paperInset * 2,
      boardH - paperInset * 1.4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(paperRect, const Radius.circular(4)),
      Paint()..color = _paper,
    );

    // 모서리 접힘
    final foldSize = boardW * 0.14;
    final foldPath = Path()
      ..moveTo(paperRect.right, paperRect.bottom - foldSize)
      ..lineTo(paperRect.right, paperRect.bottom)
      ..lineTo(paperRect.right - foldSize, paperRect.bottom)
      ..close();
    canvas.drawPath(foldPath, Paint()..color = _paperFold);
    canvas.drawLine(
      Offset(paperRect.right, paperRect.bottom - foldSize),
      Offset(paperRect.right - foldSize, paperRect.bottom),
      Paint()..color = const Color(0xFFC8C2B8)..strokeWidth = 1.2,
    );

    // 상단 클립
    final clipW = boardW * 0.30;
    final clipH = boardH * 0.10;
    final clipLeft = boardLeft + (boardW - clipW) / 2;
    final clipTop  = boardTop - clipH * 0.55;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(clipLeft, clipTop, clipW, clipH),
        const Radius.circular(5),
      ),
      Paint()..color = _clip,
    );
    canvas.drawCircle(
      Offset(clipLeft + clipW / 2, clipTop + clipH * 0.42),
      clipW * 0.07,
      Paint()..color = _clipHole,
    );

    // 3개의 물결 선
    final lineYs = [
      paperRect.top + paperRect.height * 0.34,
      paperRect.top + paperRect.height * 0.52,
      paperRect.top + paperRect.height * 0.70,
    ];
    final lineLeft  = paperRect.left  + paperRect.width * 0.12;
    final lineRight = paperRect.right - paperRect.width * 0.18;
    final lineWidth = lineRight - lineLeft;
    final amp = boardH * 0.018;
    const phases = [[0.00, 0.28], [0.33, 0.61], [0.66, 0.94]];

    Offset? penTipPos;
    int? drawingIdx;

    for (int i = 0; i < 3; i++) {
      final start = phases[i][0], end = phases[i][1];
      double progress;
      if (t < start) {
        progress = 0;
      } else if (t > end) {
        progress = 1;
      } else {
        progress = (t - start) / (end - start);
      }
      if (progress <= 0) continue;

      final wave = _wavyPath(lineLeft, lineYs[i], lineWidth, amp, progress);
      canvas.drawPath(
        wave,
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = boardW * 0.022
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );

      if (progress < 1 && t >= start && t <= end) {
        drawingIdx = i;
        final endX = lineLeft + lineWidth * progress;
        final wavePhase = (endX - lineLeft) / lineWidth;
        final endY = lineYs[i] + math.sin(wavePhase * math.pi * 4) * amp;
        penTipPos = Offset(endX, endY);
      }
    }

    if (penTipPos == null) {
      final nextIdx = t < 0.33 ? 0 : (t < 0.66 ? 1 : (t < 0.96 ? 2 : 0));
      penTipPos = Offset(lineLeft, lineYs[nextIdx]);
    }

    _drawPen(canvas, penTipPos, boardW, isDrawing: drawingIdx != null);
  }

  Path _wavyPath(
      double x0, double y0, double width, double amp, double progress) {
    final path = Path();
    const steps = 80;
    final endIdx = (steps * progress).round().clamp(1, steps);
    for (int i = 0; i <= endIdx; i++) {
      final f = i / steps;
      final x = x0 + width * f;
      final y = y0 + math.sin(f * math.pi * 4) * amp;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  void _drawPen(Canvas canvas, Offset tip, double scale,
      {required bool isDrawing}) {
    canvas.save();
    canvas.translate(tip.dx, tip.dy);
    canvas.rotate(-math.pi / 5.1);

    final penLen = scale * 0.58;
    final penW   = scale * 0.075;

    if (isDrawing) {
      final shadow = Path()
        ..moveTo(0, 0)
        ..lineTo(penLen * 0.45, penW * 0.4)
        ..lineTo(penLen * 0.50, penW * 0.7)
        ..lineTo(0, penW * 0.3)
        ..close();
      canvas.drawPath(shadow, Paint()..color = const Color(0x33000000));
    }

    final tipPath = Path()
      ..moveTo(0, 0)
      ..lineTo(penW * 0.55, -penW * 0.7)
      ..lineTo(-penW * 0.55, -penW * 0.7)
      ..close();
    canvas.drawPath(tipPath, Paint()..color = _penTip);

    final bodyTop = -penW * 0.7 - penLen;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-penW / 2, bodyTop, penW, penLen),
        Radius.circular(penW * 0.35),
      ),
      Paint()..color = _penBody,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        -penW / 2 + penW * 0.15,
        bodyTop + penLen * 0.32,
        penW * 0.7,
        penLen * 0.05,
      ),
      Paint()..color = _penAccent,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-penW * 0.6, bodyTop - penW * 0.05,
            penW * 1.2, penW * 0.45),
        Radius.circular(penW * 0.2),
      ),
      Paint()..color = _penBody,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_ClipboardPainter old) => old.t != t;
}

// ── 파이프라인 내부 모델 ────────────────────────────────────────────────
class _Tagged {
  final PickedPhoto photo;
  final PhotoGroup group;
  _Tagged(this.photo, this.group);
}

class _UploadedPhoto {
  final int id;
  final PhotoGroup group;
  final Uint8List bytes;
  _UploadedPhoto({required this.id, required this.group, required this.bytes});
}
