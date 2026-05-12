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

  // ── GET ──────────────────────────────────────────────────────────────────

  Future<dynamic> get(String path) async {
    final resp = await _client.get(_uri(path), headers: await _authHeaders());
    return _handleResponse(resp);
  }

  // ── POST (JSON) ───────────────────────────────────────────────────────────

  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final resp = await _client.post(
      _uri(path),
      headers: await _authHeaders(),
      body: jsonEncode(body),
    );
    return _handleResponse(resp);
  }

  // ── POST (multipart — 웹/모바일 공통, bytes 사용) ─────────────────────────

  Future<dynamic> postMultipart(
    String path, {
    required Map<String, String> fields,
    required List<int> fileBytes,
    required String fileName,
    required String fileField,
  }) async {
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
    final resp = await http.Response.fromStream(streamed);
    return _handleResponse(resp);
  }

  // ── 응답 처리 ─────────────────────────────────────────────────────────────

  dynamic _handleResponse(http.Response resp) {
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
}
