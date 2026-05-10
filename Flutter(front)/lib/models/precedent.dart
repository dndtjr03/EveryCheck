class PrecedentResult {
  final String id;
  final String title;
  final String caseNumber;
  final String court;
  final String date;
  final String document;
  final double distance;

  const PrecedentResult({
    required this.id,
    required this.title,
    required this.caseNumber,
    required this.court,
    required this.date,
    required this.document,
    required this.distance,
  });

  factory PrecedentResult.fromJson(Map<String, dynamic> json) => PrecedentResult(
        id: json['id'] as String,
        title: json['title'] as String,
        caseNumber: json['case_number'] as String,
        court: json['court'] as String,
        date: json['date'] as String,
        document: json['document'] as String,
        distance: (json['distance'] as num).toDouble(),
      );

  // 유사도 점수 (0~1, 1이 가장 유사)
  double get similarity => 1.0 - distance.clamp(0.0, 1.0);
  String get similarityLabel => '${(similarity * 100).toStringAsFixed(0)}% 유사';
}

class PrecedentSearchResponse {
  final String query;
  final List<PrecedentResult> results;
  final int total;

  const PrecedentSearchResponse({
    required this.query,
    required this.results,
    required this.total,
  });

  factory PrecedentSearchResponse.fromJson(Map<String, dynamic> json) =>
      PrecedentSearchResponse(
        query: json['query'] as String,
        results: (json['results'] as List<dynamic>)
            .map((e) => PrecedentResult.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: json['total'] as int,
      );
}
