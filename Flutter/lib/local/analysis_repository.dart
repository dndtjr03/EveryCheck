import 'dart:convert';

import '../models/analysis_local.dart';
import '../services/api_service.dart';

/// 분석 세션·사진·메시지에 대한 데이터 액세스.
///
/// 이전: 로컬 SQLite 기반. 현재: FastAPI(`/analyses/*`) 호출 기반.
/// 호출 시그니처는 가급적 기존과 호환되도록 유지.
class AnalysisRepository {
  AnalysisRepository._();
  static final AnalysisRepository instance = AnalysisRepository._();

  final _api = ApiService();

  // ── Analysis ────────────────────────────────────────────────────────────

  Future<int> createAnalysis({
    required int contractId,
    required String contractAddr,
  }) async {
    final json = await _api.post('/analyses/', {
      'contract_id': contractId,
      'contract_addr': contractAddr,
    }) as Map<String, dynamic>;
    return json['id'] as int;
  }

  Future<AnalysisSession?> getAnalysis(int id) async {
    try {
      final json = await _api.get('/analyses/$id') as Map<String, dynamic>;
      return AnalysisSession.fromJson(json);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<AnalysisSession>> listAnalyses() async {
    final list = await _api.get('/analyses/') as List<dynamic>;
    return list
        .map((e) => AnalysisSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateAnalysisStatus(
    int id,
    AnalysisStatus status, {
    String? summary,
    int? estimatedCost,
  }) async {
    final body = <String, dynamic>{'status': status.name};
    if (summary != null) body['summary'] = summary;
    if (estimatedCost != null) body['estimated_cost'] = estimatedCost;
    await _api.patch('/analyses/$id', body);
  }

  Future<void> deleteAnalysis(int id) async {
    await _api.delete('/analyses/$id');
  }

  // ── Damage Photos ────────────────────────────────────────────────────────

  /// S3 업로드가 끝난 사진을 분석 세션에 등록한다.
  /// (구버전의 `addPhoto(filePath: ...)` → `s3Url: ...`로 시그니처 변경)
  Future<int> addPhoto({
    required int analysisId,
    required String s3Url,
    required PhotoGroup group,
    required int orderIndex,
  }) async {
    final json = await _api.post('/analyses/$analysisId/photos', {
      's3_url': s3Url,
      'group_type': group.name,
      'order_index': orderIndex,
    }) as Map<String, dynamic>;
    return json['id'] as int;
  }

  Future<List<DamagePhoto>> listPhotos(int analysisId) async {
    final list =
        await _api.get('/analyses/$analysisId/photos') as List<dynamic>;
    return list
        .map((e) => DamagePhoto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `aiResultJson`은 Map/Object를 받아 직렬화. (예: Gemini 분석 raw 결과)
  Future<void> markPhotoAnalyzed(
    int analysisId,
    int photoId,
    Object aiResult,
  ) async {
    await _api.patch('/analyses/$analysisId/photos/$photoId', {
      'analyzed': true,
      'ai_result':
          aiResult is String ? aiResult : jsonEncode(aiResult),
    });
  }

  // ── Messages ─────────────────────────────────────────────────────────────

  Future<int> addMessage({
    required int analysisId,
    required ChatRole role,
    required String content,
    int? photoId,
  }) async {
    final json = await _api.post('/analyses/$analysisId/messages', {
      'role': role.name,
      'content': content,
      if (photoId != null) 'photo_id': photoId,
    }) as Map<String, dynamic>;
    return json['id'] as int;
  }

  Future<List<ChatMessage>> listMessages(int analysisId) async {
    final list =
        await _api.get('/analyses/$analysisId/messages') as List<dynamic>;
    return list
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
