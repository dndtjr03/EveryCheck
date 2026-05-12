class AppConfig {
  // 기본값: localhost:8000 (adb reverse tcp:8000 tcp:8000 로 PC↔폰 포워딩 사용)
  // - 실기기 USB 디버깅: adb reverse 가 자동 실행되므로 그대로 동작 (VS Code preLaunchTask)
  // - 에뮬레이터: dart-define=API_BASE_URL=http://10.0.2.2:8000 으로 덮어쓰기
  // - 운영: dart-define=API_BASE_URL=https://api.example.com 으로 덮어쓰기
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

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
