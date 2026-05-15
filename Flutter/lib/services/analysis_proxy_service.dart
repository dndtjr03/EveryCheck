import 'dart:typed_data';

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
    );
    if (result is Map<String, dynamic>) return result;
    throw const ProxyException('서버 응답이 JSON object가 아닙니다.');
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
