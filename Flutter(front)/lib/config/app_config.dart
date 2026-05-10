class AppConfig {
  static const String baseUrl = 'http://10.0.2.2:8000'; // 안드로이드 에뮬레이터 → localhost
  // static const String baseUrl = 'http://localhost:8000'; // 웹/iOS 시뮬레이터용

  static const String appName = '다봐드림';
  static const String appVersion = '1.0.0';

  // 토큰 저장 키
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';

  // 이미지 업로드 제한
  static const int maxImageSizeMb = 10;
  static const List<String> allowedImageExtensions = ['jpg', 'jpeg', 'png', 'webp'];

  // 분석 폴링 간격 (ms)
  static const int analysisPollIntervalMs = 3000;
  static const int analysisPollMaxRetries = 20;
}
