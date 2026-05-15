/// PDF 리포트 가격 정책.
///
/// - 기본: 1회 생성 = ₩3,000 (10페이지 포함)
/// - 11페이지부터 페이지당 ₩500 추가
class PdfPricing {
  static const int basePrice = 3000;
  static const int basePageQuota = 10;
  static const int extraPagePrice = 500;

  /// 페이지 수에 따른 총 금액(원).
  static int totalFor(int pages) {
    if (pages <= 0) return 0;
    final extra = pages > basePageQuota ? pages - basePageQuota : 0;
    return basePrice + extra * extraPagePrice;
  }

  /// 분석 데이터(요약 1p + 손상 N개) → 예상 페이지 수.
  /// 표지 1 + 요약 1 + 손상별 1 + 마무리(판례 목록) 1
  static int estimatePagesFor({required int damageCount}) {
    return 1 + 1 + damageCount + 1;
  }
}
