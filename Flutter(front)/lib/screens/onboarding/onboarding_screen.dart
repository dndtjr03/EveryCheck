import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../auth/login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;

  static const _steps = [
    _Step(
      icon: '🏠',
      title: '주거분쟁,\n이제 AI가 해결해드려요',
      desc: '입주·퇴거 사진 한 장으로\n공정한 분석을 받아보세요',
      color1: AppColors.primary,
      color2: AppColors.primaryDark,
    ),
    _Step(
      icon: '📷',
      title: '사진을 찍으면\nAI가 비교해드려요',
      desc: '입주 시와 퇴거 시 사진을 비교해\n손상 여부를 자동으로 파악해요',
      color1: AppColors.primaryDark,
      color2: Color(0xFF1E4A82),
    ),
    _Step(
      icon: '⚖️',
      title: '판례 기반으로\n명확하게 설명해드려요',
      desc: '실제 임대차 판례를 바탕으로\n쉽고 정확하게 안내해드려요',
      color1: Color(0xFF2A9060),
      color2: Color(0xFF1D6644),
    ),
  ];

  void _goToLogin() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _steps[_step];
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [s.color1, s.color2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              children: [
                // 로그인 버튼
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _goToLogin,
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: const Text('로그인', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  ),
                ),
                // 아이콘 + 텍스트
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(44),
                        ),
                        child: Center(
                          child: Text(s.icon, style: const TextStyle(fontSize: 72)),
                        ),
                      ),
                      const SizedBox(height: 36),
                      Text(
                        s.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.35,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        s.desc,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.75),
                          height: 1.8,
                        ),
                      ),
                    ],
                  ),
                ),
                // 점 페이지네이션
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_steps.length, (i) {
                    return GestureDetector(
                      onTap: () => setState(() => _step = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _step ? 20 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == _step
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(9999),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 28),
                // 하단 버튼
                if (_step < _steps.length - 1)
                  Row(
                    children: [
                      Expanded(
                        child: _GhostButton(
                          label: '건너뛰기',
                          onTap: _goToLogin,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _WhiteButton(
                          label: '다음 →',
                          color: AppColors.primary,
                          onTap: () => setState(() => _step++),
                        ),
                      ),
                    ],
                  )
                else
                  _WhiteButton(
                    label: '시작하기',
                    color: AppColors.primary,
                    onTap: _goToLogin,
                    full: true,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Step {
  final String icon;
  final String title;
  final String desc;
  final Color color1;
  final Color color2;
  const _Step({
    required this.icon,
    required this.title,
    required this.desc,
    required this.color1,
    required this.color2,
  });
}

class _GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GhostButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(kRadiusPill),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }
}

class _WhiteButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool full;
  const _WhiteButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.full = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: full ? double.infinity : null,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(kRadiusPill),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}
