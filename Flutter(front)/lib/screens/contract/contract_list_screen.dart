import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/contract_provider.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/skeleton.dart';
import 'contract_detail_screen.dart';
import 'contract_form_screen.dart';

class ContractListScreen extends StatefulWidget {
  const ContractListScreen({super.key});

  @override
  State<ContractListScreen> createState() => _ContractListScreenState();
}

class _ContractListScreenState extends State<ContractListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ContractProvider>().loadContracts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ContractProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('임대차 계약'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ContractFormScreen()),
            ),
          ),
        ],
      ),
      body: _buildBody(provider),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ContractFormScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('계약 등록'),
      ),
    );
  }

  Widget _buildBody(ContractProvider provider) {
    if (provider.loading && provider.contracts.isEmpty) {
      return ListView.builder(
        itemCount: 4,
        itemBuilder: (context, _) => const ContractCardSkeleton(),
      );
    }
    if (provider.error != null && provider.contracts.isEmpty) {
      return ErrorView(
        message: provider.error!,
        onRetry: () => context.read<ContractProvider>().loadContracts(),
      );
    }
    if (provider.contracts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.home_outlined, size: 64, color: Colors.black26),
            SizedBox(height: 16),
            Text('등록된 계약이 없습니다.\n+ 버튼으로 계약을 추가하세요.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black45)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<ContractProvider>().loadContracts(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: provider.contracts.length,
        itemBuilder: (ctx, i) {
          final contract = provider.contracts[i];
          return _ContractCard(
            address: contract.address,
            startDate: contract.contractStartDate,
            endDate: contract.contractEndDate,
            imageCount: contract.damageImages.length,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ContractDetailScreen(contractId: contract.id),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ContractCard extends StatelessWidget {
  final String address;
  final DateTime startDate;
  final DateTime? endDate;
  final int imageCount;
  final VoidCallback onTap;

  const _ContractCard({
    required this.address,
    required this.startDate,
    this.endDate,
    required this.imageCount,
    required this.onTap,
  });

  String _fmt(DateTime d) => '${d.year}.${d.month.toString().padLeft(2,'0')}.${d.day.toString().padLeft(2,'0')}';

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF3FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.home_work_outlined, color: Color(0xFF3D7BFF)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(address, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(
                      '${_fmt(startDate)} ~ ${endDate != null ? _fmt(endDate!) : '현재'}',
                      style: const TextStyle(fontSize: 12, color: Colors.black45),
                    ),
                    if (imageCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.photo_outlined, size: 12, color: Colors.black38),
                            const SizedBox(width: 2),
                            Text('$imageCount장', style: const TextStyle(fontSize: 11, color: Colors.black38)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black26),
            ],
          ),
        ),
      ),
    );
  }
}
