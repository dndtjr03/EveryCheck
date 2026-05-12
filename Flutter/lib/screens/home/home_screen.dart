import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

  void _navigateToTab(int index) {
    // 기록·분석 탭 진입 시 최신 계약 목록 갱신
    if (index == 1 || index == 2) {
      context.read<ContractProvider>().loadContracts();
    }
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      HomeTab(onNavigate: _navigateToTab),  // 0: 홈
      const RecordsScreen(),                // 1: 기록
      const ImageUploadScreen(),            // 2: 분석
      const ReportScreen(),                 // 3: 리포트
      const ProfileScreen(),                // 4: 프로필
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _navigateToTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '홈',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: '기록',
          ),
          NavigationDestination(
            icon: Icon(Icons.camera_alt_outlined),
            selectedIcon: Icon(Icons.camera_alt),
            label: '분석',
          ),
          NavigationDestination(
            icon: Icon(Icons.description_outlined),
            selectedIcon: Icon(Icons.description),
            label: '리포트',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '프로필',
          ),
        ],
      ),
    );
  }
}
