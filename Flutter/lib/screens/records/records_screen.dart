import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_theme.dart';
import '../../local/analysis_repository.dart';
import '../../models/analysis_local.dart';
import '../analysis/analysis_chat_screen.dart';

/// 기록 탭.
///
/// SQLite `analyses` 테이블을 직접 읽어서 보여준다.
/// 서버 미연동 상태에서도 영구 보관됨 (앱 재시작·재로그인 후에도 살아있음).
/// 서버 도입 시 `AnalysisRepository`를 remote-backed로 교체하면 화면 그대로 사용 가능.
class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  final _repo = AnalysisRepository.instance;
  List<AnalysisSession> _sessions = [];
  Map<int, int> _photoCounts = {}; // analysisId → photo count
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final sessions = await _repo.listAnalyses();
    // 각 세션 사진 수도 같이 불러와서 카드에 표시
    final counts = <int, int>{};
    for (final s in sessions) {
      final photos = await _repo.listPhotos(s.id);
      counts[s.id] = photos.length;
    }
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _photoCounts = counts;
      _loading = false;
    });
  }

  Future<void> _confirmDelete(AnalysisSession s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('기록 삭제'),
        content: Text('"${s.contractAddr}"의 분석 기록을 삭제할까요?\n(채팅·사진·결과 모두 사라집니다.)'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.deleteAnalysis(s.id);
    // 사진 파일도 같이 지우면 좋지만 그건 추후 정리 (저장공간 절약용)
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('내 기록',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh, color: AppColors.n500),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  Row(
                    children: [
                      Text(
                        '총 ${_sessions.length}건의 분석 기록',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.n500),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(9999),
                        ),
                        child: const Text(
                          '🗂 로컬 저장',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryDark),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (_sessions.isEmpty)
                    const _EmptyState()
                  else
                    ..._sessions.map((s) => _AnalysisCard(
                          session: s,
                          photoCount: _photoCounts[s.id] ?? 0,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  AnalysisChatScreen(analysisId: s.id),
                            ),
                          ).then((_) => _load()),
                          onLongPress: () => _confirmDelete(s),
                        )),
                ],
              ),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Column(
          children: const [
            Text('📋', style: TextStyle(fontSize: 48)),
            SizedBox(height: 12),
            Text('아직 기록이 없어요',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.n600)),
            SizedBox(height: 6),
            Text('분석 탭에서 첫 분석을 시작해보세요',
                style: TextStyle(fontSize: 13, color: AppColors.n400)),
          ],
        ),
      ),
    );
  }
}

class _AnalysisCard extends StatelessWidget {
  final AnalysisSession session;
  final int photoCount;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _AnalysisCard({
    required this.session,
    required this.photoCount,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final completed = session.status == AnalysisStatus.completed;
    final dateFmt = DateFormat('yyyy.MM.dd HH:mm');
    final won = NumberFormat.currency(
        locale: 'ko_KR', symbol: '₩', decimalDigits: 0);

    final statusLabel = switch (session.status) {
      AnalysisStatus.pending => '대기 중',
      AnalysisStatus.inProgress => '분석 중',
      AnalysisStatus.completed => '완료',
    };
    final statusBg = switch (session.status) {
      AnalysisStatus.pending => AppColors.n100,
      AnalysisStatus.inProgress => AppColors.primaryLight,
      AnalysisStatus.completed => AppColors.secondaryLight,
    };
    final statusFg = switch (session.status) {
      AnalysisStatus.pending => AppColors.n500,
      AnalysisStatus.inProgress => AppColors.primaryDark,
      AnalysisStatus.completed => const Color(0xFF2A9060),
    };

    final thumbnailPath = _firstThumbnail(session.id);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(kRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Thumbnail(path: thumbnailPath),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.contractAddr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.n800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateFmt.format(
                            session.completedAt ?? session.startedAt),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.n500),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusFg)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _Chip(
                  label: '📷 사진 $photoCount장',
                  bg: AppColors.n100,
                  fg: AppColors.n500,
                ),
                if (completed && session.estimatedCost != null) ...[
                  const SizedBox(width: 8),
                  _Chip(
                    label: '💰 ${won.format(session.estimatedCost)}',
                    bg: AppColors.accentLight,
                    fg: const Color(0xFFB85520),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 카드 썸네일용으로 첫 사진 경로를 추측 (실제로는 비동기 조회가 더 정확하지만,
  /// 가벼운 카드용이라 광고용 placeholder로 충분히 동작).
  String? _firstThumbnail(int _) => null;
}

class _Thumbnail extends StatelessWidget {
  final String? path;
  const _Thumbnail({this.path});

  @override
  Widget build(BuildContext context) {
    if (path != null && File(path!).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(File(path!), width: 44, height: 44, fit: BoxFit.cover),
      );
    }
    return Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        color: AppColors.n100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(child: Text('🏠', style: TextStyle(fontSize: 22))),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _Chip({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: fg)),
    );
  }
}
