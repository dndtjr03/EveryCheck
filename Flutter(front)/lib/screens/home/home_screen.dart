import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../providers/contract_provider.dart';
import '../analysis/image_upload_screen.dart';
import '../profile/profile_screen.dart';
import '../records/records_screen.dart';
import '../report/report_screen.dart';
import 'home_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  static const _tabs = [
    _TabItem(id: 'home',    emoji: '🏠', label: '홈'),
    _TabItem(id: 'analyze', emoji: '📷', label: '분석'),
    _TabItem(id: 'records', emoji: '📋', label: '기록'),
    _TabItem(id: 'report',  emoji: '📄', label: '리포트'),
    _TabItem(id: 'profile', emoji: '👤', label: '내 정보'),
  ];

  late final List<Widget> _screens = [
    HomeTab(onNavigate: _navigateTo),
    const ImageUploadScreen(),
    const RecordsScreen(),
    const ReportScreen(),
    const ProfileScreen(),
  ];

  void _navigateTo(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ContractProvider>().loadContracts();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: _BottomNav(
        activeIndex: _currentIndex,
        tabs: _tabs,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

class _TabItem {
  final String id;
  final String emoji;
  final String label;
  const _TabItem({required this.id, required this.emoji, required this.label});
}

class _BottomNav extends StatelessWidget {
  final int activeIndex;
  final List<_TabItem> tabs;
  final ValueChanged<int> onTap;

  const _BottomNav({
    required this.activeIndex,
    required this.tabs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      padding: EdgeInsets.only(
        top: 6,
        bottom: MediaQuery.of(context).padding.bottom + 6,
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final t = tabs[i];
          final active = i == activeIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onTap(i),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                decoration: BoxDecoration(
                  color: active ? AppColors.primaryLight : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t.emoji, style: const TextStyle(fontSize: 22)),
                    const SizedBox(height: 2),
                    Text(
                      t.label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                        color: active ? AppColors.primary : AppColors.n400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
