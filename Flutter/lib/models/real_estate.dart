import 'damage_image.dart';
import 'repair_estimate.dart';

class RealEstate {
  final int id;
  final int ownerId;
  final String address;
  final DateTime contractStartDate;
  final DateTime? contractEndDate;
  final String? memo;
  final DateTime createdAt;
  final List<DamageImage> damageImages;
  final List<RepairEstimate> repairEstimates;

  const RealEstate({
    required this.id,
    required this.ownerId,
    required this.address,
    required this.contractStartDate,
    this.contractEndDate,
    this.memo,
    required this.createdAt,
    this.damageImages = const [],
    this.repairEstimates = const [],
  });

  factory RealEstate.fromJson(Map<String, dynamic> json) => RealEstate(
        id: json['id'] as int,
        ownerId: json['owner_id'] as int,
        address: json['address'] as String,
        contractStartDate: DateTime.parse(json['contract_start_date'] as String),
        contractEndDate: json['contract_end_date'] != null
            ? DateTime.parse(json['contract_end_date'] as String)
            : null,
        memo: json['memo'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        damageImages: (json['damage_images'] as List<dynamic>? ?? [])
            .map((e) => DamageImage.fromJson(e as Map<String, dynamic>))
            .toList(),
        repairEstimates: (json['repair_estimates'] as List<dynamic>? ?? [])
            .map((e) => RepairEstimate.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  // 계약 기간 (일)
  int? get contractDurationDays {
    if (contractEndDate == null) return null;
    return contractEndDate!.difference(contractStartDate).inDays;
  }

  // 경과 연수 (감가상각 계산용)
  double get elapsedYears {
    final end = contractEndDate ?? DateTime.now();
    return end.difference(contractStartDate).inDays / 365.0;
  }
}
