import 'package:flutter/material.dart';
import '../../models/precedent.dart';
import '../../models/real_estate.dart';
import '../../models/repair_estimate.dart';
import '../../services/analysis_service.dart';
import '../../services/api_service.dart';

class AnalysisResultScreen extends StatefulWidget {
  final RealEstate contract;
  final RepairEstimate estimate;

  const AnalysisResultScreen({
    super.key,
    required this.contract,
    required this.estimate,
  });

  @override
  State<AnalysisResultScreen> createState() => _AnalysisResultScreenState();
}

class _AnalysisResultScreenState extends State<AnalysisResultScreen> {
  final _analysisService = AnalysisService(ApiService());
  List<PrecedentResult> _precedents = [];
  bool _loadingPrecedents = false;

  @override
  void initState() {
    super.initState();
    _loadPrecedents();
  }

  Future<void> _loadPrecedents() async {
    final e = widget.estimate;
    if (e.part == null && e.damageType == null) return;

    setState(() => _loadingPrecedents = true);
    final query = '${e.part ?? ''} ${e.damageType ?? ''} 임차인 과실 원상복구'.trim();
    try {
      final resp = await _analysisService.searchPrecedents(query: query, nResults: 3);
      setState(() => _precedents = resp.results);
    } catch (_) {
      // 판례 검색 실패는 무시 (선택적 기능)
    } finally {
      setState(() => _loadingPrecedents = false);
    }
  }

  String _fmtWon(double v) => '${v.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},',
      )}원';

  @override
  Widget build(BuildContext context) {
    final e = widget.estimate;
    return Scaffold(
      appBar: AppBar(title: const Text('AI 분석 결과')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 분석 결과 요약 카드
          _ResultSummaryCard(estimate: e),
          const SizedBox(height: 16),
          // 비용 상세
          _CostDetailCard(estimate: e, fmtWon: _fmtWon),
          const SizedBox(height: 16),
          // 판례 근거
          _PrecedentSection(
            precedents: _precedents,
            loading: _loadingPrecedents,
          ),
          const SizedBox(height: 24),
          // 확인 버튼
          ElevatedButton(
            onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
            child: const Text('홈으로 돌아가기'),
          ),
        ],
      ),
    );
  }
}

class _ResultSummaryCard extends StatelessWidget {
  final RepairEstimate estimate;
  const _ResultSummaryCard({required this.estimate});

  @override
  Widget build(BuildContext context) {
    final confidencePct = estimate.aiConfidence != null
        ? '${(estimate.aiConfidence! * 100).toStringAsFixed(0)}%'
        : '-';

    return Card(
      color: const Color(0xFF3D7BFF),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: Colors.white70, size: 18),
                const SizedBox(width: 6),
                const Text('AI 분석 완료', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const Spacer(),
                Text('신뢰도 $confidencePct', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              estimate.part ?? '손상 부위 미상',
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              estimate.damageType ?? '',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _CostDetailCard extends StatelessWidget {
  final RepairEstimate estimate;
  final String Function(double) fmtWon;
  const _CostDetailCard({required this.estimate, required this.fmtWon});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('수리비 산출', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const Divider(height: 20),
            _Row('총 수리비', fmtWon(estimate.totalRepairCost)),
            _Row('경과 연수', '${estimate.elapsedYears.toStringAsFixed(1)}년'),
            _Row('내용연수', '${estimate.usefulLifeYears.toStringAsFixed(0)}년'),
            _Row('감가상각 적용 비율', '${estimate.tenantSharePercent.toStringAsFixed(0)}%'),
            const Divider(height: 20),
            Row(
              children: [
                const Expanded(
                  child: Text('임차인 최종 부담액', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                Text(
                  fmtWon(estimate.tenantCost),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF3D7BFF),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '공식: 수리비 × (1 − 경과연수/내용연수)\n국토교통부 원상복구 가이드라인 기준',
              style: TextStyle(fontSize: 11, color: Colors.grey[500], height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _PrecedentSection extends StatelessWidget {
  final List<PrecedentResult> precedents;
  final bool loading;
  const _PrecedentSection({required this.precedents, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.gavel_outlined, size: 18),
            const SizedBox(width: 6),
            const Text('관련 판례', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const Spacer(),
            if (loading)
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
        const SizedBox(height: 10),
        if (!loading && precedents.isEmpty)
          const Text('관련 판례를 찾을 수 없습니다.', style: TextStyle(color: Colors.black38, fontSize: 13))
        else
          ...precedents.map((p) => _PrecedentCard(precedent: p)),
      ],
    );
  }
}

class _PrecedentCard extends StatelessWidget {
  final PrecedentResult precedent;
  const _PrecedentCard({required this.precedent});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    precedent.caseNumber,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF3FF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    precedent.similarityLabel,
                    style: const TextStyle(color: Color(0xFF3D7BFF), fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${precedent.court} · ${precedent.date}',
              style: const TextStyle(fontSize: 11, color: Colors.black38),
            ),
            const SizedBox(height: 8),
            Text(
              precedent.document.length > 120
                  ? '${precedent.document.substring(0, 120)}...'
                  : precedent.document,
              style: const TextStyle(fontSize: 12, color: Colors.black54, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
