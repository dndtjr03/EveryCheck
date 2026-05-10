import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/contract_provider.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final contracts = context.watch<ContractProvider>().contracts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('다봐드림'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            onPressed: () => context.read<AuthProvider>().logout(),
            tooltip: '로그아웃',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<ContractProvider>().loadContracts(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 인사말 배너
            _WelcomeBanner(name: user?.displayName ?? ''),
            const SizedBox(height: 20),
            // 퀵 메뉴
            const _QuickMenu(),
            const SizedBox(height: 24),
            // 최근 계약
            if (contracts.isNotEmpty) ...[
              const Text(
                '최근 임대차 계약',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...contracts.take(3).map((c) => _ContractSummaryCard(contract: c)),
            ],
          ],
        ),
      ),
    );
  }
}

class _WelcomeBanner extends StatelessWidget {
  final String name;
  const _WelcomeBanner({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3D7BFF), Color(0xFF6B9FFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name.isNotEmpty ? '안녕하세요, $name님!' : '안녕하세요!',
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'AI로 임대차 분쟁을 현명하게 해결하세요.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _QuickMenu extends StatelessWidget {
  const _QuickMenu();

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.add_home_work_outlined, '계약 등록', '/contract/new'),
      (Icons.photo_camera_outlined, '손상 분석', '/analysis'),
      (Icons.gavel_outlined, '판례 검색', '/precedents'),
      (Icons.calculate_outlined, '비용 계산', '/calculator'),
    ];

    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: items.map((item) {
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {},
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF3FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(item.$1, color: const Color(0xFF3D7BFF), size: 26),
              ),
              const SizedBox(height: 6),
              Text(item.$2, style: const TextStyle(fontSize: 11, color: Colors.black54)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _ContractSummaryCard extends StatelessWidget {
  final dynamic contract;
  const _ContractSummaryCard({required this.contract});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFEEF3FF),
          child: Icon(Icons.home_outlined, color: Color(0xFF3D7BFF)),
        ),
        title: Text(contract.address, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '입주: ${contract.contractStartDate.year}년 ${contract.contractStartDate.month}월',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
