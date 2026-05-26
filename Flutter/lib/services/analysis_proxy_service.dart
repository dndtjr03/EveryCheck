import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import '../config/app_config.dart';
import 'api_service.dart';
import 'gemini_service.dart' show GeminiChatTurn;

/// 백엔드 `/proxy` 라우터를 거쳐 Gemini와 통신하는 서비스.
///
/// `GeminiService`와 인터페이스를 동일하게 맞춰뒀기 때문에 채팅 화면에서는
/// 한 줄(`GeminiService.instance` → `AnalysisProxyService.instance`)만
/// 바꾸면 백엔드 경유로 전환됨.
///
/// 차이점:
///  - API 키가 Flutter 앱에 없음 → APK 뜯어도 키 추출 불가
///  - JWT 인증 필수 (백엔드가 사용자 검증)
///  - 백엔드(`backend/analysis_proxy_router.py`)의 `GOOGLE_API_KEY` 환경변수 사용
class AnalysisProxyService {
  AnalysisProxyService._();
  static final AnalysisProxyService instance = AnalysisProxyService._();

  /// `ApiService`는 토큰을 자동 부착하므로 그대로 재사용.
  final ApiService _api = ApiService();

  /// 백엔드 URL이 설정돼 있으면 사용 가능.
  /// (지금은 항상 true — `AppConfig.baseUrl` 기본값 `http://localhost:8000`)
  static bool get isConfigured => AppConfig.baseUrl.isNotEmpty;

  /// 사진 1장 분석.
  ///
  /// `GeminiService.analyzePhoto`와 동일한 형식의 응답:
  /// `{ "part": "...", "damage_type": "...", "cost": 120000, "confidence": 0.75, "reason": "..." }`
  Future<Map<String, dynamic>> analyzePhoto(Uint8List imageBytes) async {
    final result = await _api.postMultipart(
      '/proxy/analyze-photo',
      fields: const {},
      fileBytes: imageBytes,
      fileName: 'photo.jpg',
      fileField: 'image',
      fileContentType: 'image/jpeg',
    );
    if (result is Map<String, dynamic>) return result;
    throw const ProxyException('서버 응답이 JSON object가 아닙니다.');
  }

  /// 퇴거 사진 1장 + 입주 사진 N장을 함께 보내 baseline 비교 분석.
  ///
  /// `/proxy/analyze-with-baseline` 호출. Gemini가 입주 사진들 중 가장 비슷한
  /// 1장을 자동 매칭해 비교한 뒤 "새로 생긴 손상"만 판별한다.
  ///
  /// 추가 응답 필드:
  ///  - `is_new` (bool|null): 새 손상 여부
  ///  - `matched_move_in_index` (int|null): 매칭된 입주 사진 번호 (1-based)
  ///  - `move_in_count` (int): 비교에 사용된 입주 사진 수
  ///
  /// [moveInBytesList]가 비어 있으면 [ProxyException] — 호출자에서 사전 검증할 것.
  Future<Map<String, dynamic>> analyzePhotoWithBaseline({
    required Uint8List moveOutBytes,
    required List<Uint8List> moveInBytesList,
  }) async {
    if (moveInBytesList.isEmpty) {
      throw const ProxyException('입주 사진이 1장 이상 필요합니다.');
    }
    final uri = Uri.parse('${AppConfig.baseUrl}/proxy/analyze-with-baseline');
    final req = http.MultipartRequest('POST', uri);
    final token = await _api.getAccessToken();
    // ignore: use_null_aware_elements
    if (token != null) {
      req.headers['authorization'] = 'Bearer $token';
    }

    // 입주 사진들: 같은 필드명(move_in_images)으로 여러 번 첨부.
    for (var i = 0; i < moveInBytesList.length; i++) {
      req.files.add(http.MultipartFile.fromBytes(
        'move_in_images',
        moveInBytesList[i],
        filename: 'move_in_$i.jpg',
        contentType: MediaType('image', 'jpeg'),
      ));
    }
    req.files.add(http.MultipartFile.fromBytes(
      'move_out_image',
      moveOutBytes,
      filename: 'move_out.jpg',
      contentType: MediaType('image', 'jpeg'),
    ));

    final streamed = await http.Client().send(req);
    final resp = await http.Response.fromStream(streamed);
    final body = utf8.decode(resp.bodyBytes);

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      String detail = body;
      try {
        final j = jsonDecode(body);
        detail = (j is Map && j['detail'] != null) ? j['detail'].toString() : body;
      } catch (_) {}
      throw ProxyException('baseline 비교 분석 실패 (${resp.statusCode}): $detail');
    }
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const ProxyException('baseline 응답이 JSON object가 아닙니다.');
  }

  /// 양방향 채팅. 백엔드의 `/proxy/chat` 호출.
  ///
  /// [history]: 이전 메시지들 (`user` / `model` 역할 — Gemini history 형식 그대로)
  /// [latestUserMessage]: 사용자가 방금 보낸 메시지
  /// [systemContext]: 백엔드의 기본 시스템 프롬프트를 덮어쓸 때만 지정 (보통 분석 요약 주입용)
  Future<String> chat({
    required List<GeminiChatTurn> history,
    required String latestUserMessage,
    String? systemContext,
  }) async {
    final body = <String, dynamic>{
      'history': history.map((t) => {'role': t.role, 'text': t.text}).toList(),
      'message': latestUserMessage,
      if (systemContext != null) 'system_context': systemContext,
    };
    final resp = await _api.post('/proxy/chat', body);
    if (resp is Map<String, dynamic> && resp['reply'] is String) {
      return (resp['reply'] as String).trim();
    }
    throw const ProxyException('서버에서 reply 필드를 받지 못했습니다.');
  }
}

class ProxyException implements Exception {
  final String message;
  const ProxyException(this.message);
  @override
  String toString() => 'ProxyException: $message';
}
