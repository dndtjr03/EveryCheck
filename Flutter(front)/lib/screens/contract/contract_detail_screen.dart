import 'package:flutter/material.dart';
import '../../models/real_estate.dart';
import '../../models/repair_estimate.dart';
import '../../services/api_service.dart';
import '../../services/contract_service.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/skeleton.dart';
import '../analysis/image_upload_screen.dart';

class ContractDetailScreen extends StatefulWidget {
  final int contractId;
  const ContractDetailScreen({super.key, required this.contractId});

  @override
  State<ContractDetailScreen> createState() => _ContractDetailScreenState();
}

class _ContractDetailScreenState extends State<ContractDetailScreen> {
  final _service = ContractService(ApiService());
  RealEstate? _contract;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      _contract = await _service.getContractDetail(widget.contractId);
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = '계약 정보를 불러오지 못했습니다.';
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_contract?.address ?? '계약 상세'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_a_photo_outlined),
            onPressed: _contract == null
                ? null
                : () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ImageUploadScreen(contract: _contract!),
                      ),
                    );
                    _load();
                  },
          ),
        ],
      ),
      body: _loading
          ? const _DetailSkeleton()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _buildDetail(_contract!),
    );
  }

  Widget _buildDetail(RealEstate c) {
    final fmt = (DateTime d) =>
        '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 계약 정보 카드
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('계약 정보', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const Divider(height: 20),
                  _InfoRow(Icons.location_on_outlined, '주소', c.address),
                  _InfoRow(Icons.calendar_today_outlined, '입주일', fmt(c.contractStartDate)),
                  _InfoRow(
                    Icons.event_outlined, '퇴거일',
                    c.contractEndDate != null ? fmt(c.contractEndDate!) : '미정',
                  ),
                  _InfoRow(Icons.timelapse_outlined, '경과 연수',
                      '${c.elapsedYears.toStringAsFixed(1)}년'),
                  if (c.memo != null && c.memo!.isNotEmpty)
                    _InfoRow(Icons.note_outlined, '메모', c.memo!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 손상 이미지 갤러리
          _SectionHeader(
            title: '손상 이미지 (${c.damageImages.length})',
            action: TextButton.icon(
              icon: const Icon(Icons.add_a_photo, size: 16),
              label: const Text('추가'),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ImageUploadScreen(contract: c)),
                );
                _load();
              },
            ),
          ),
          if (c.damageImages.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('등록된 이미지가 없습니다.', style: TextStyle(color: Colors.black38))),
            )
          else
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: c.damageImages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final img = c.damageImages[i];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      img.s3Url,
                      width: 120,
                      height: 120,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 120,
                        color: Colors.grey[200],
                        child: const Icon(Icons.broken_image, color: Colors.grey),
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 16),
          // 수리비 산출 목록
          _SectionHeader(title: 'AI 분석 결과 (${c.repairEstimates.length})'),
          ...c.repairEstimates.map((e) => _EstimateCard(estimate: e)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.black45),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(color: Colors.black45, fontSize: 13)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;
  const _SectionHeader({required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const Spacer(),
        if (action != null) action!,
      ],
    );
  }
}

class _EstimateCard extends StatelessWidget {
  final RepairEstimate estimate;
  const _EstimateCard({required this.estimate});

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (estimate.analysisStatus) {
      AnalysisStatus.completed => Colors.green,
      AnalysisStatus.failed => Colors.red,
      AnalysisStatus.analyzing => Colors.orange,
      _ => Colors.grey,
    };

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (estimate.part != null)
                  Text(estimate.part!, style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    estimate.analysisStatus.label,
                    style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (estimate.damageType != null) ...[
              const SizedBox(height: 4),
              Text('손상 종류: ${estimate.damageType}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
            if (estimate.isCompleted) ...[
              const Divider(height: 16),
              Row(
                children: [
                  _CostChip('총 수리비', '${_fmt(estimate.totalRepairCost)}원'),
                  const SizedBox(width: 8),
                  _CostChip('임차인 부담', '${_fmt(estimate.tenantCost)}원', highlight: true),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '감가상각 ${estimate.tenantSharePercent.toStringAsFixed(0)}% 적용 (경과 ${estimate.elapsedYears.toStringAsFixed(1)}년)',
                style: const TextStyle(fontSize: 11, color: Colors.black38),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmt(double v) => v.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );
}

class _CostChip extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _CostChip(this.label, this.value, {this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFEEF3FF) : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: highlight ? const Color(0xFF3D7BFF) : Colors.black45)),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: highlight ? const Color(0xFF3D7BFF) : Colors.black87)),
        ],
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          ContractCardSkeleton(),
          SizedBox(height: 12),
          ContractCardSkeleton(),
        ],
      ),
    );
  }
}
