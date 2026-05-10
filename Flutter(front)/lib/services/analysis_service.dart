import 'dart:io';
import '../models/damage_image.dart';
import '../models/precedent.dart';
import '../models/repair_estimate.dart';
import 'api_service.dart';

class AnalysisService {
  final ApiService _api;
  AnalysisService(this._api);

  /// 손상 이미지를 업로드하고 AI 분석을 비동기로 시작한다.
  /// 반환: {task_id, repair_estimate_id}
  Future<Map<String, dynamic>> startAnalysis({
    required int realEstateId,
    required File imageFile,
  }) async {
    final data = await _api.postMultipart(
      '/analyze',
      fields: {'real_estate_id': realEstateId.toString()},
      file: imageFile,
      fileField: 'file',
    ) as Map<String, dynamic>;
    return data;
  }

  /// repair_estimate_id로 분석 결과를 폴링한다.
  Future<RepairEstimate> getEstimate(int realEstateId, int estimateId) async {
    final data =
        await _api.get('/real-estates/$realEstateId') as Map<String, dynamic>;
    final estimates = (data['repair_estimates'] as List<dynamic>? ?? []);
    final raw = estimates.firstWhere(
      (e) => (e as Map<String, dynamic>)['id'] == estimateId,
      orElse: () => throw ApiException(404, 'estimate not found'),
    );
    return RepairEstimate.fromJson(raw as Map<String, dynamic>);
  }

  /// 이미지를 직접 업로드만 한다 (분석 없이).
  Future<DamageImage> uploadImage({
    required int realEstateId,
    required File imageFile,
    required DamageType damageType,
  }) async {
    final data = await _api.postMultipart(
      '/real-estates/$realEstateId/images',
      fields: {'damage_type': damageType.value},
      file: imageFile,
      fileField: 'file',
    ) as Map<String, dynamic>;
    return DamageImage.fromJson(data);
  }

  /// 관련 판례를 의미 검색한다.
  Future<PrecedentSearchResponse> searchPrecedents({
    required String query,
    int nResults = 3,
  }) async {
    final data = await _api.post('/precedents/search', {
      'query': query,
      'n_results': nResults,
    }) as Map<String, dynamic>;
    return PrecedentSearchResponse.fromJson(data);
  }
}
