import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/real_estate.dart';
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
    String fmt(DateTime d) =>
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
                separatorBuilder: (context, i) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final img = c.damageImages[i];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      img.s3Url,
                      width: 120,
                      height: 120,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => Container(
                        width: 120,
                        color: Colors.grey[200],
                        child: const Icon(Icons.broken_image, color: Colors.grey),
                      ),
                    ),
                  );
                },
              ),
            ),
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
          Icon(icon, size: 16, color: AppColors.n400),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(color: AppColors.n400, fontSize: 13)),
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
        ?action,
      ],
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
