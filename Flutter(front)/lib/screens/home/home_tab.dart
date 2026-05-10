import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/contract_provider.dart';
import '../../models/real_estate.dart';

class HomeTab extends StatelessWidget {
  final void Function(int index) onNavigate;
  const HomeTab({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final user      = context.watch<AuthProvider>().user;
    final contracts = context.watch<ContractProvider>().contracts;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(userName: user?.displayName),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => context.read<ContractProvider>().loadContracts(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    _HeroCard(onAnalyze: () => onNavigate(1)),
                    const SizedBox(height: 20),
                    _QuickActions(onNavigate: onNavigate),
                    const SizedBox(height: 20),
                    _RecentSection(contracts: contracts, onNavigate: onNavigate),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Top Bar ──────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String? userName;
  const _TopBar({this.userName});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(
            '다봐드림',
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w900,
              color: AppColors.primary,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.n100,
              borderRadius: BorderRadius.circular(9999),
            ),
            child: const Icon(Icons.notifications_none_rounded,
                color: AppColors.n600, size: 20),
          ),
        ],
      ),
    );
  }
}

// ── Hero Card ────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final VoidCallback onAnalyze;
  const _HeroCard({required this.onAnalyze});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AI 주거분쟁 해결사',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                '입주·퇴거 사진으로\n분쟁을 해결해드려요',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.4,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: onAnalyze,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: const Text(
                    '📷 분석 시작하기',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            right: -10,
            top: -10,
            child: Text(
              '🏠',
              style: TextStyle(
                fontSize: 90,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quick Actions ─────────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  final void Function(int) onNavigate;
  const _QuickActions({required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final items = [
      _QuickItem(emoji: '📷', label: '새 분석', sub: '사진 올리기',
          bg: AppColors.primaryLight, fg: AppColors.primaryDark, tabIndex: 1),
      _QuickItem(emoji: '📋', label: '내 기록', sub: '이전 분석',
          bg: AppColors.secondaryLight, fg: const Color(0xFF2A9060), tabIndex: 2),
      _QuickItem(emoji: '📄', label: 'PDF', sub: '유료 리포트',
          bg: AppColors.accentLight, fg: const Color(0xFFB85520), tabIndex: 3),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'QUICK MENU',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.n500,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: items.map((item) {
            return Expanded(
              child: GestureDetector(
                onTap: () => onNavigate(item.tabIndex),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  decoration: BoxDecoration(
                    color: item.bg,
                    borderRadius: BorderRadius.circular(kRadius),
                  ),
                  child: Column(
                    children: [
                      Text(item.emoji, style: const TextStyle(fontSize: 26)),
                      const SizedBox(height: 5),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: item.fg,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.sub,
                        style: const TextStyle(fontSize: 10, color: AppColors.n500),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _QuickItem {
  final String emoji;
  final String label;
  final String sub;
  final Color bg;
  final Color fg;
  final int tabIndex;
  const _QuickItem({
    required this.emoji,
    required this.label,
    required this.sub,
    required this.bg,
    required this.fg,
    required this.tabIndex,
  });
}

// ── Recent Section ────────────────────────────────────────────────────────────

class _RecentSection extends StatelessWidget {
  final List<RealEstate> contracts;
  final void Function(int) onNavigate;

  const _RecentSection({required this.contracts, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'RECENT',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.n500,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 10),
        if (contracts.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(kRadius),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Column(
              children: [
                const Text('🏠', style: TextStyle(fontSize: 36)),
                const SizedBox(height: 8),
                const Text(
                  '아직 분석 기록이 없어요',
                  style: TextStyle(fontSize: 14, color: AppColors.n500),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => onNavigate(1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    child: const Text(
                      '첫 분석 시작하기',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          ...contracts.take(3).map((c) => _RecentCard(contract: c)),
      ],
    );
  }
}

class _RecentCard extends StatelessWidget {
  final RealEstate contract;
  const _RecentCard({required this.contract});

  @override
  Widget build(BuildContext context) {
    final hasIssues = contract.repairEstimates.isNotEmpty;
    final statusLabel = hasIssues ? '검토 필요' : '이상 없음';
    final statusBg    = hasIssues ? AppColors.accentLight : AppColors.secondaryLight;
    final statusFg    = hasIssues ? const Color(0xFFB85520) : const Color(0xFF2A9060);
    final dateStr = _fmt(contract.contractStartDate);

    return GestureDetector(
      onTap: () {},
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
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
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
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
                      fontWeight: FontWeight.w600,
                      color: AppColors.n800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    dateStr,
                    style: const TextStyle(fontSize: 12, color: AppColors.n500),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
}
