import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../config/app_theme.dart';
import '../../local/analysis_repository.dart';
import '../../models/analysis_local.dart';
import '../../models/pdf_pricing.dart';
import '../../services/pdf_report_service.dart';

/// 리포트(PDF) 탭.
///
/// - 인자 없이 진입: 완료된 분석 목록을 보여주고 선택 → PDF 생성
/// - `analysisId` 지정 진입: 해당 분석의 PDF 생성 화면으로 바로 이동
class ReportScreen extends StatelessWidget {
  final int? analysisId;
  const ReportScreen({super.key, this.analysisId});

  @override
  Widget build(BuildContext context) {
    if (analysisId != null) {
      return _ReportDetailScreen(analysisId: analysisId!);
    }
    return const _AnalysisPickScreen();
  }
}

// ── 분석 선택 화면 ─────────────────────────────────────────────────────────

class _AnalysisPickScreen extends StatefulWidget {
  const _AnalysisPickScreen();

  @override
  State<_AnalysisPickScreen> createState() => _AnalysisPickScreenState();
}

class _AnalysisPickScreenState extends State<_AnalysisPickScreen> {
  Future<List<AnalysisSession>> _load() async =>
      AnalysisRepository.instance.listAnalyses();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF 리포트',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: borderOf(context)),
        ),
      ),
      body: FutureBuilder<List<AnalysisSession>>(
        future: _load(),
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = (snap.data ?? const <AnalysisSession>[])
              .where((a) => a.status == AnalysisStatus.completed)
              .toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              _HeroBanner(),
              const SizedBox(height: 16),
              _PricingCard(),
              const SizedBox(height: 24),
              const Text(
                '완료된 분석에서 PDF 만들기',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              if (list.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: surfaceOf(context),
                    borderRadius: BorderRadius.circular(kRadius),
                    border: Border.all(color: borderOf(context)),
                  ),
                  child: const Column(
                    children: [
                      Text('🗂', style: TextStyle(fontSize: 40)),
                      SizedBox(height: 8),
                      Text('아직 완료된 분석이 없어요',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      SizedBox(height: 4),
                      Text('분석 탭에서 사진을 업로드하고 분석을 완료한 뒤 다시 와주세요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12, color: AppColors.n500)),
                    ],
                  ),
                )
              else
                ...list.map((a) => _AnalysisRow(session: a)),
            ],
          );
        },
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE86030), AppColors.accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: const [
          Text('📄', style: TextStyle(fontSize: 40)),
          SizedBox(height: 10),
          Text('전문 리포트로 분쟁 해결',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
          SizedBox(height: 6),
          Text('판례와 법조를 함께 담은 PDF로\n임대인·임차인 협의에 활용하세요',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: Colors.white70, height: 1.7)),
        ],
      ),
    );
  }
}

class _PricingCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final won = NumberFormat.currency(
        locale: 'ko_KR', symbol: '₩', decimalDigits: 0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceOf(context),
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('요금 안내',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: AppColors.n700)),
          const SizedBox(height: 8),
          _row('기본 (10페이지 포함)', won.format(PdfPricing.basePrice)),
          _row('초과 페이지 (11p~)',
              '${won.format(PdfPricing.extraPagePrice)} / 페이지'),
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
                child: Text(k,
                    style: const TextStyle(fontSize: 13, color: AppColors.n700))),
            Text(v,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _AnalysisRow extends StatelessWidget {
  final AnalysisSession session;
  const _AnalysisRow({required this.session});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _ReportDetailScreen(analysisId: session.id),
      )),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surfaceOf(context),
          borderRadius: BorderRadius.circular(kRadius),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04), blurRadius: 4),
          ],
        ),
        child: Row(
          children: [
            const Text('📄', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(session.contractAddr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('yyyy.MM.dd HH:mm')
                        .format(session.completedAt ?? session.startedAt),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.n500),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.n300),
          ],
        ),
      ),
    );
  }
}

// ── PDF 상세/결제/생성 화면 ──────────────────────────────────────────────

class _ReportDetailScreen extends StatefulWidget {
  final int analysisId;
  const _ReportDetailScreen({required this.analysisId});

  @override
  State<_ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<_ReportDetailScreen> {
  AnalysisSession? _session;
  int _damageCount = 0;
  bool _busy = true;
  bool _paying = false;
  bool _paid = false;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = AnalysisRepository.instance;
    final s = await repo.getAnalysis(widget.analysisId);
    final photos = await repo.listPhotos(widget.analysisId);
    if (!mounted) return;
    setState(() {
      _session = s;
      _damageCount = photos.where((p) => p.analyzed).length;
      _busy = false;
    });
  }

  Future<void> _mockPay() async {
    setState(() => _paying = true);
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    setState(() {
      _paying = false;
      _paid = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('결제가 완료됐어요 (모킹). PDF를 생성합니다.'),
        backgroundColor: AppColors.secondary,
      ),
    );
    await _generateAndPreview();
  }

  Future<void> _generateAndPreview() async {
    setState(() => _generating = true);
    try {
      final pdfBytes =
          await PdfReportService.instance.buildReport(widget.analysisId);
      if (!mounted) return;
      await Printing.layoutPdf(
        onLayout: (_) async => pdfBytes,
        name: 'EveryCheck_${widget.analysisId}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('PDF 생성 실패: $e'),
            backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_session == null) {
      return const Scaffold(body: Center(child: Text('분석을 찾을 수 없어요.')));
    }
    final pages = PdfPricing.estimatePagesFor(damageCount: _damageCount);
    final price = PdfPricing.totalFor(pages);
    final won = NumberFormat.currency(
        locale: 'ko_KR', symbol: '₩', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF 생성',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          _HeroBanner(),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surfaceOf(context),
              borderRadius: BorderRadius.circular(kRadius),
              border: Border.all(color: borderOf(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_session!.contractAddr,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  '분석 완료: ${DateFormat('yyyy.MM.dd HH:mm').format(_session!.completedAt ?? _session!.startedAt)}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.n500),
                ),
                const Divider(height: 24),
                _kv('손상 분석 건수', '${_damageCount}건'),
                _kv('예상 페이지 수',
                    '${pages}p (표지+요약+손상×$_damageCount+법조)'),
                _kv('기본 가격', won.format(PdfPricing.basePrice)),
                if (pages > PdfPricing.basePageQuota)
                  _kv('초과 페이지 추가요금',
                      '${pages - PdfPricing.basePageQuota}p × ${won.format(PdfPricing.extraPagePrice)} = ${won.format((pages - PdfPricing.basePageQuota) * PdfPricing.extraPagePrice)}'),
                const Divider(height: 24),
                Row(
                  children: [
                    const Expanded(
                      child: Text('합계',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                    Text(
                      won.format(price),
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.accent),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.accentLight,
              borderRadius: BorderRadius.circular(kRadius),
              border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.4)),
            ),
            child: const Row(
              children: [
                Text('🧪', style: TextStyle(fontSize: 20)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '결제 모킹: 결제하기 누르면 즉시 결제 완료 처리되고 PDF 미리보기가 열립니다.',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.n700, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed:
                _paying || _generating ? null : (_paid ? _generateAndPreview : _mockPay),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              disabledBackgroundColor: AppColors.n200,
              minimumSize: const Size(double.infinity, 52),
              shape: const StadiumBorder(),
            ),
            child: _paying
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : _generating
                    ? const Text('PDF 생성 중...',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white))
                    : Text(
                        _paid
                            ? '📄 PDF 다시 열기'
                            : '${won.format(price)} 결제하고 PDF 받기',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white),
                      ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              '※ 결제는 캡스톤 시연용 모킹입니다. 실제 결제 게이트웨이는 미연동.',
              style: TextStyle(fontSize: 11, color: AppColors.n400),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
                child: Text(k,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.n500))),
            Text(v,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
