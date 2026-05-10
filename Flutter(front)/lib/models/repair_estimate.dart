enum AnalysisStatus {
  pending('pending', '대기 중'),
  analyzing('analyzing', '분석 중'),
  completed('completed', '완료'),
  failed('failed', '실패');

  const AnalysisStatus(this.value, this.label);
  final String value;
  final String label;

  static AnalysisStatus fromValue(String? v) =>
      AnalysisStatus.values.firstWhere((e) => e.value == v, orElse: () => AnalysisStatus.pending);
}

class RepairEstimate {
  final int id;
  final int realEstateId;
  final int? damageImageId;
  final double totalRepairCost;
  final double usefulLifeYears;
  final double elapsedYears;
  final double tenantCost;
  final double depreciationRate;
  final String? part;
  final String? damageType;
  final double? estimatedCost;
  final double? aiConfidence;
  final String? imageHash;
  final AnalysisStatus analysisStatus;
  final String? celeryTaskId;
  final DateTime createdAt;

  const RepairEstimate({
    required this.id,
    required this.realEstateId,
    this.damageImageId,
    required this.totalRepairCost,
    required this.usefulLifeYears,
    required this.elapsedYears,
    required this.tenantCost,
    required this.depreciationRate,
    this.part,
    this.damageType,
    this.estimatedCost,
    this.aiConfidence,
    this.imageHash,
    required this.analysisStatus,
    this.celeryTaskId,
    required this.createdAt,
  });

  factory RepairEstimate.fromJson(Map<String, dynamic> json) => RepairEstimate(
        id: json['id'] as int,
        realEstateId: json['real_estate_id'] as int,
        damageImageId: json['damage_image_id'] as int?,
        totalRepairCost: (json['total_repair_cost'] as num).toDouble(),
        usefulLifeYears: (json['useful_life_years'] as num).toDouble(),
        elapsedYears: (json['elapsed_years'] as num).toDouble(),
        tenantCost: (json['tenant_cost'] as num).toDouble(),
        depreciationRate: (json['depreciation_rate'] as num).toDouble(),
        part: json['part'] as String?,
        damageType: json['damage_type'] as String?,
        estimatedCost: json['estimated_cost'] != null
            ? (json['estimated_cost'] as num).toDouble()
            : null,
        aiConfidence: json['ai_confidence'] != null
            ? (json['ai_confidence'] as num).toDouble()
            : null,
        imageHash: json['image_hash'] as String?,
        analysisStatus: AnalysisStatus.fromValue(json['analysis_status'] as String?),
        celeryTaskId: json['celery_task_id'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  // 임차인 부담 비율 (%)
  double get tenantSharePercent => depreciationRate * 100;

  bool get isAnalyzing => analysisStatus == AnalysisStatus.analyzing;
  bool get isCompleted => analysisStatus == AnalysisStatus.completed;
}
