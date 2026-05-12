enum DamageType {
  wallpaper('wallpaper', '벽지'),
  floor('floor', '바닥'),
  other('other', '기타');

  const DamageType(this.value, this.label);
  final String value;
  final String label;

  static DamageType fromValue(String v) =>
      DamageType.values.firstWhere((e) => e.value == v, orElse: () => DamageType.other);
}

class DamageImage {
  final int id;
  final int realEstateId;
  final String s3Url;
  final DamageType damageType;
  final String? aiResult;
  final String fileHash;
  final DateTime uploadedAt;

  const DamageImage({
    required this.id,
    required this.realEstateId,
    required this.s3Url,
    required this.damageType,
    this.aiResult,
    required this.fileHash,
    required this.uploadedAt,
  });

  factory DamageImage.fromJson(Map<String, dynamic> json) => DamageImage(
        id: json['id'] as int,
        realEstateId: json['real_estate_id'] as int,
        s3Url: json['s3_url'] as String,
        damageType: DamageType.fromValue(json['damage_type'] as String),
        aiResult: json['ai_result'] as String?,
        fileHash: json['file_hash'] as String,
        uploadedAt: DateTime.parse(json['uploaded_at'] as String),
      );
}
