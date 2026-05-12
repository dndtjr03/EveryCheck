import 'package:flutter/material.dart';
import '../../config/app_theme.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  String _selected = 'basic';

  static const _plans = [
    _Plan(
      id: 'basic',
      label: '기본 리포트',
      price: '₩9,900',
      sub: 'AI 분석 결과 PDF',
      recommended: false,
    ),
    _Plan(
      id: 'pro',
      label: '전문가 리포트',
      price: '₩29,900',
      sub: '변호사 검토 포함',
      recommended: true,
    ),
  ];

  static const _features = [
    ('📸', '입주·퇴거 사진 비교 (고해상도)'),
    ('⚖️', '항목별 AI 분석 결과 및 판례 인용'),
    ('📝', '손상 부위 상세 설명 및 책임 소재'),
    ('💰', '예상 수리비용 범위 안내'),
    ('👨‍⚖️', '전문 변호사 검토 의견 (전문가 플랜)'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('PDF 리포트',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
        children: [
          // 히어로
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE86030), AppColors.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: const [
                Text('📄', style: TextStyle(fontSize: 40)),
                SizedBox(height: 10),
                Text(
                  '전문 리포트로 분쟁 해결',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  '법적 효력을 위한 공식 문서로\n분쟁 해결에 활용하세요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                    height: 1.7,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 포함 내용
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(kRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '리포트 포함 내용',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.n700,
                  ),
                ),
                const SizedBox(height: 12),
                ...List.generate(_features.length, (i) {
                  final f = _features[i];
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      border: i < _features.length - 1
                          ? const Border(
                              bottom: BorderSide(color: AppColors.n100))
                          : null,
                    ),
                    child: Row(
                      children: [
                        Text(f.$1, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Text(f.$2,
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.n700)),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 플랜 선택
          Row(
            children: _plans.map((p) {
              final active = _selected == p.id;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selected = p.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: active ? AppColors.accentLight : AppColors.surface,
                      border: Border.all(
                        color: active ? AppColors.accent : AppColors.n200,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(kRadius),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (p.recommended)
                          Positioned(
                            top: -24,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  borderRadius: BorderRadius.circular(9999),
                                ),
                                child: const Text('추천',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white)),
                              ),
                            ),
                          ),
                        Column(
                          children: [
                            Text(p.label,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.n700)),
                            const SizedBox(height: 6),
                            Text(
                              p.price,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: active
                                    ? const Color(0xFFB85520)
                                    : AppColors.n800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(p.sub,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.n500)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // 준비 중 배너
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.accentLight,
              borderRadius: BorderRadius.circular(kRadius),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
            ),
            child: const Row(
              children: [
                Text('🚧', style: TextStyle(fontSize: 20)),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('캡스톤 데모 준비 중',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.n800)),
                      SizedBox(height: 2),
                      Text('결제 및 PDF 기능은 현재 지원되지 않습니다',
                          style: TextStyle(fontSize: 12, color: AppColors.n500)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 결제 버튼 (비활성화)
          ElevatedButton(
            onPressed: null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              disabledBackgroundColor: AppColors.n200,
              minimumSize: const Size(double.infinity, 52),
              shape: const StadiumBorder(),
            ),
            child: Text(
              '${_plans.firstWhere((p) => p.id == _selected).price} 결제하고 받기',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              '캡스톤 발표 이후 순차적으로 오픈 예정입니다',
              style: TextStyle(fontSize: 12, color: AppColors.n400),
            ),
          ),
        ],
      ),
    );
  }
}

class _Plan {
  final String id;
  final String label;
  final String price;
  final String sub;
  final bool recommended;
  const _Plan({
    required this.id,
    required this.label,
    required this.price,
    required this.sub,
    required this.recommended,
  });
}
