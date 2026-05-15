import 'dart:convert';
import 'dart:typed_data';

import 'package:google_generative_ai/google_generative_ai.dart';

/// Gemini API 직접 호출 서비스.
///
/// 백엔드 서버 미구현 상태에서 Flutter 앱에서 바로 Gemini로 분석 요청을 보냄.
/// API 키는 `--dart-define=GEMINI_API_KEY=...`로 주입.
/// 서버 도입 시 이 클래스는 폐기하고 `AnalysisService`로 통합 예정.
class GeminiService {
  GeminiService._();
  static final GeminiService instance = GeminiService._();

  static final String _apiKey = const String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  static bool get isConfigured => _apiKey.isNotEmpty;

  static const String _model = 'gemini-1.5-flash';

  /// 사진 1장에 대한 손상 분석 (JSON 응답).
  ///
  /// 반환: `{ "part": "...", "damage_type": "...", "cost": 120000, "confidence": 0.75, "reason": "..." }`
  Future<Map<String, dynamic>> analyzePhoto(Uint8List imageBytes) async {
    if (!isConfigured) {
      throw const GeminiException('GEMINI_API_KEY가 설정되지 않았습니다. '
          '`flutter run --dart-define=GEMINI_API_KEY=...`으로 주입해주세요.');
    }

    final model = GenerativeModel(model: _model, apiKey: _apiKey);
    final prompt = TextPart(_photoInstruction);
    final image = DataPart('image/jpeg', imageBytes);

    final response = await model.generateContent([
      Content.multi([prompt, image]),
    ]);

    final text = (response.text ?? '').trim();
    if (text.isEmpty) {
      throw const GeminiException('Gemini 응답이 비어 있습니다.');
    }
    return _parseJson(text);
  }

  /// 양방향 채팅: 분석 기록 + 사용자 후속 질문을 가지고 Gemini에 자연어 응답 요청.
  ///
  /// [history]: 이전 메시지들 (user/model 역할)
  /// [latestUserMessage]: 최신 사용자 입력
  Future<String> chat({
    required List<GeminiChatTurn> history,
    required String latestUserMessage,
    String? systemContext,
  }) async {
    if (!isConfigured) {
      throw const GeminiException('GEMINI_API_KEY가 설정되지 않았습니다.');
    }

    final model = GenerativeModel(
      model: _model,
      apiKey: _apiKey,
      systemInstruction: Content.system(
        systemContext ?? _chatSystemDefault,
      ),
    );

    final chat = model.startChat(
      history: history
          .map((t) => Content(t.role, [TextPart(t.text)]))
          .toList(),
    );
    final resp = await chat.sendMessage(Content.text(latestUserMessage));
    return (resp.text ?? '응답을 받지 못했어요.').trim();
  }

  static const String _photoInstruction = '''
이 이미지는 임대차 퇴거 시 원상복구 비용 산정을 위한 손상 사진이다.
다음 항목만 추정하여 반드시 JSON 한 개만 출력하라. 다른 설명·마크다운·코드펜스는 절대 쓰지 마라.

키 (영문 소문자):
- "part": 손상 부위 (예: 거실 벽면, 욕실 타일, 바닥 장판) — 문자열
- "damage_type": 손상 종류 (예: 스크래치, 오염, 곰팡이, 들뜸) — 문자열
- "cost": 국내 시공 기준 추정 수리비(원화, 정수) — 숫자
- "confidence": 추정 확신도 — 0~1 사이 소수
- "reason": 사용자에게 보여줄 한국어 설명 (1~3문장, 손상 부위·정도·임차인 부담 가능성 포함)

출력 예:
{"part":"거실 벽지","damage_type":"오염","cost":120000,"confidence":0.75,"reason":"거실 벽지 하단부에 오염이 보입니다. 통상 손모로 보기 어려운 정도로, 임차인 부담 가능성이 있습니다."}
''';

  static const String _chatSystemDefault = '''
당신은 한국 임대차 분쟁 자문 보조 AI "다봐드림"입니다.
- 사용자는 임대차 퇴거 시 원상복구 비용 분담을 알고 싶어합니다.
- 국토교통부 임대차 가이드라인과 민법 제615조(원상회복의무), 제654조(준용),
  주택임대차보호법, 그리고 통상의 손모 법리(대법원 판례 다수)를 근거로 답하세요.
- 단정적인 법률 자문은 피하고, "가능성이 높다" / "분쟁 시 다툴 여지가 있다" 같이 완곡하게 표현하세요.
- 응답은 항상 한국어. 짧고 명확하게 답하되, 필요 시 근거(가이드라인·민법 조문·판례 요지)를 인용하세요.
- 분석 결과 요약을 받았다면 그 결과를 바탕으로 후속 질문에 답합니다.
''';

  Map<String, dynamic> _parseJson(String raw) {
    // 코드펜스 제거
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```');
    final m = fence.firstMatch(raw);
    final json = m != null ? m.group(1)!.trim() : raw;
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) return decoded;
      throw const GeminiException('JSON이 object 형태가 아닙니다.');
    } catch (e) {
      throw GeminiException('Gemini 응답 파싱 실패: $e\n원문: $raw');
    }
  }
}

/// 채팅 한 턴 (Gemini가 받아들이는 role/text 쌍).
class GeminiChatTurn {
  final String role; // 'user' or 'model'
  final String text;
  const GeminiChatTurn({required this.role, required this.text});
}

class GeminiException implements Exception {
  final String message;
  const GeminiException(this.message);
  @override
  String toString() => 'GeminiException: $message';
}
