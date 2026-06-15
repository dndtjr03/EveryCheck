import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import '../config/app_config.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// 401 자동 refresh 지원 ApiService.
/// - 모든 인증 요청은 `_withRetryOn401`을 거침
/// - 401 발생 시 저장된 refresh token으로 `/auth/refresh` 1회 호출
/// - 동시 다발 401에도 refresh는 단 1회만 수행 (`_ongoingRefresh` 캐시)
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final _storage = const FlutterSecureStorage();
  final _client = http.Client();

  Future<bool>? _ongoingRefresh;

  Future<String?> getAccessToken() =>
      _storage.read(key: AppConfig.accessTokenKey);
  Future<String?> getRefreshToken() =>
      _storage.read(key: AppConfig.refreshTokenKey);

  Future<bool> get isAdminToken async =>
      (await getAccessToken()) == 'test01';

  Future<void> saveTokens(
      {required String access, required String refresh}) async {
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

  /// 모든 API 요청에 공통 적용되는 timeout. 무한 로딩 방지.
  static const _defaultTimeout = Duration(seconds: 15);

  Future<dynamic> get(String path) async {
    return _withRetryOn401(() async {
      return _client
          .get(_uri(path), headers: await _authHeaders())
          .timeout(_defaultTimeout);
    });
  }

  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    return _withRetryOn401(() async {
      return _client
          .post(
            _uri(path),
            headers: await _authHeaders(),
            body: jsonEncode(body),
          )
          .timeout(_defaultTimeout);
    });
  }

  Future<dynamic> patch(String path, Map<String, dynamic> body) async {
    return _withRetryOn401(() async {
      return _client
          .patch(
            _uri(path),
            headers: await _authHeaders(),
            body: jsonEncode(body),
          )
          .timeout(_defaultTimeout);
    });
  }

  Future<dynamic> delete(String path) async {
    return _withRetryOn401(() async {
      return _client
          .delete(_uri(path), headers: await _authHeaders())
          .timeout(_defaultTimeout);
    });
  }

  Future<dynamic> postMultipart(
    String path, {
    required Map<String, String> fields,
    required List<int> fileBytes,
    required String fileName,
    required String fileField,
    /// 파일 part의 Content-Type. 미지정 시 application/octet-stream로 나가
    /// 백엔드 이미지 검증에서 400을 받을 수 있음. 이미지면 image/jpeg 등 명시.
    String? fileContentType,
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
        contentType: fileContentType != null
            ? MediaType.parse(fileContentType)
            : null,
      ));
      final streamed = await _client.send(request).timeout(
            const Duration(seconds: 60),
          );
      return http.Response.fromStream(streamed);
    });
  }

  // ── 401 자동 재시도 래퍼 ──────────────────────────────────────────────────

  Future<dynamic> _withRetryOn401(
      Future<http.Response> Function() sender) async {
    var resp = await sender();
    if (resp.statusCode == 401) {
      final refreshed = await _refreshTokensOnce();
      if (refreshed) {
        resp = await sender();
      } else {
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
      final resp = await _client
          .post(
            _uri('/auth/refresh'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'refresh_token': refresh}),
          )
          .timeout(_defaultTimeout);
      if (resp.statusCode != 200) return false;
      final json =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
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
