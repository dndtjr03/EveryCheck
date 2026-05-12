import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/real_estate.dart';
import '../../providers/contract_provider.dart';
import '../contract/contract_detail_screen.dart';
import '../contract/contract_form_screen.dart';

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
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
      ),
      body: provider.loading && provider.contracts.isEmpty
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () => provider.loadContracts(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  // 헤더
                  Row(
                    children: [
                      Text(
                        '총 ${provider.contracts.length}건의 분석 기록',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.n500),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ContractFormScreen()),
                        ).then((_) => provider.loadContracts()),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(9999),
                          ),
                          child: const Text(
                            '+ 새 기록',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (provider.contracts.isEmpty)
                    _EmptyState()
                  else
                    ...provider.contracts
                        .map((c) => _RecordCard(contract: c)),
                ],
              ),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Column(
          children: [
            const Text('📋', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            const Text(
              '아직 기록이 없어요',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.n600),
            ),
            const SizedBox(height: 6),
            const Text(
              '분석 탭에서 첫 분석을 시작해보세요',
              style: TextStyle(fontSize: 13, color: AppColors.n400),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  final RealEstate contract;
  const _RecordCard({required this.contract});

  String _fmt(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final hasImages = contract.damageImages.isNotEmpty;
    final statusLabel = hasImages ? '사진 등록됨' : '사진 없음';
    final statusBg    = hasImages ? AppColors.secondaryLight : AppColors.n100;
    final statusFg    = hasImages ? const Color(0xFF2A9060) : AppColors.n500;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ContractDetailScreen(contractId: contract.id),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
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
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.n100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text('🏠', style: TextStyle(fontSize: 22)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contract.address,
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
                        _fmt(contract.contractStartDate),
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
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusFg,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _Chip(
                  label: '📷 사진 ${contract.damageImages.length}장',
                  bg: AppColors.n100,
                  fg: AppColors.n500,
                ),
                const SizedBox(width: 8),
                _Chip(
                  label: '입주일 ${_fmt(contract.contractStartDate)}',
                  bg: AppColors.primaryLight,
                  fg: AppColors.primaryDark,
                ),
              ],
            ),
          ],
        ),
      ),
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
