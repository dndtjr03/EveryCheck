import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final _storage = const FlutterSecureStorage();
  final _client = http.Client();

  /// 동시에 여러 요청이 401을 받았을 때, refresh를 한 번만 수행하도록 보장.
  /// 첫 요청이 refresh를 시작하면 이후 401들은 이 Future를 await.
  Future<bool>? _ongoingRefresh;

  Future<String?> getAccessToken() => _storage.read(key: AppConfig.accessTokenKey);
  Future<String?> getRefreshToken() => _storage.read(key: AppConfig.refreshTokenKey);

  Future<bool> get isAdminToken async =>
      (await getAccessToken()) == 'test01';

  Future<void> saveTokens({required String access, required String refresh}) async {
    await _storage.write(key: AppConfig.accessTokenKey, value: access);
    await _storage.write(key: AppConfig.refreshTokenKey, value: refresh);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: AppConfig.accessTokenKey);
    await _storage.delete(key: AppConfig.refreshTokenKey);
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await getAccessToken();
    return {
      'content-type': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
    };
  }

  Uri _uri(String path) => Uri.parse('${AppConfig.baseUrl}$path');

  // ── 공개 HTTP 메서드 ─────────────────────────────────────────────────────

  Future<dynamic> get(String path) async {
    return _withRetryOn401(() async {
      final resp =
          await _client.get(_uri(path), headers: await _authHeaders());
      return resp;
    });
  }

  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    return _withRetryOn401(() async {
      final resp = await _client.post(
        _uri(path),
        headers: await _authHeaders(),
        body: jsonEncode(body),
      );
      return resp;
    });
  }

  Future<dynamic> postMultipart(
    String path, {
    required Map<String, String> fields,
    required List<int> fileBytes,
    required String fileName,
    required String fileField,
  }) async {
    return _withRetryOn401(() async {
      final token = await getAccessToken();
      final request = http.MultipartRequest('POST', _uri(path));
      if (token != null) {
        request.headers['authorization'] = 'Bearer $token';
      }
      request.fields.addAll(fields);
      request.files.add(http.MultipartFile.fromBytes(
        fileField,
        fileBytes,
        filename: fileName,
      ));
      final streamed = await _client.send(request);
      return http.Response.fromStream(streamed);
    });
  }

  // ── 401 자동 재시도 래퍼 ──────────────────────────────────────────────────

  /// [sender] 를 실행해서 응답을 받음.
  /// 200~299 → JSON 디코드해 반환 (또는 null)
  /// 401     → refresh token으로 새 액세스 토큰 발급 후 [sender] 1회 재시도
  /// 그 외 비-2xx → ApiException
  Future<dynamic> _withRetryOn401(
      Future<http.Response> Function() sender) async {
    var resp = await sender();
    if (resp.statusCode == 401) {
      final refreshed = await _refreshTokensOnce();
      if (refreshed) {
        // 새 토큰으로 한 번만 재시도
        resp = await sender();
      } else {
        // refresh 실패 → 토큰 폐기. AuthProvider가 다음 checkAuth() 시 로그인 화면으로.
        await clearTokens();
      }
    }
    return _decodeOrThrow(resp);
  }

  dynamic _decodeOrThrow(http.Response resp) {
    final body = utf8.decode(resp.bodyBytes);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      if (body.isEmpty) return null;
      return jsonDecode(body);
    }
    String detail = 'Unknown error';
    try {
      final json = jsonDecode(body);
      detail = json['detail'] ?? json['message'] ?? body;
    } catch (_) {
      detail = body;
    }
    throw ApiException(resp.statusCode, detail.toString());
  }

  /// 동시에 여러 401이 발생해도 단 1회만 /auth/refresh 호출하도록 보장.
  /// 반환값: refresh 성공 시 true, 실패(또는 refresh token 자체가 없음) 시 false.
  Future<bool> _refreshTokensOnce() {
    final inFlight = _ongoingRefresh;
    if (inFlight != null) return inFlight;
    final future = _doRefresh();
    _ongoingRefresh = future;
    future.whenComplete(() => _ongoingRefresh = null);
    return future;
  }

  Future<bool> _doRefresh() async {
    final refresh = await getRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final resp = await _client.post(
        _uri('/auth/refresh'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({'refresh_token': refresh}),
      );
      if (resp.statusCode != 200) return false;
      final json = jsonDecode(utf8.decode(resp.bodyBytes))
          as Map<String, dynamic>;
      final newAccess = json['access_token'] as String?;
      final newRefresh = json['refresh_token'] as String?;
      if (newAccess == null || newRefresh == null) return false;
      await saveTokens(access: newAccess, refresh: newRefresh);
      return true;
    } catch (_) {
      return false;
    }
  }
}
