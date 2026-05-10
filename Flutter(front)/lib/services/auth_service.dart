import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/user.dart';
import 'api_service.dart';

class AuthService {
  final ApiService _api;
  AuthService(this._api);

  /// OAuth2 Password Grant — /auth/token 은 form-urlencoded
  Future<User> login({required String email, required String password}) async {
    final resp = await http.post(
      Uri.parse('${AppConfig.baseUrl}/auth/token'),
      headers: {HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded'},
      body: {'username': email, 'password': password},
    );
    if (resp.statusCode != 200) {
      String detail = 'Login failed';
      try {
        detail = (jsonDecode(resp.body) as Map)['detail'] ?? detail;
      } catch (_) {}
      throw ApiException(resp.statusCode, detail);
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    await _api.saveTokens(
      access: json['access_token'] as String,
      refresh: json['refresh_token'] as String,
    );
    return getMe();
  }

  Future<User> register({
    required String email,
    required String password,
    String? fullName,
  }) async {
    final data = await _api.post('/auth/register', {
      'email': email,
      'password': password,
      if (fullName != null && fullName.isNotEmpty) 'full_name': fullName,
    }) as Map<String, dynamic>;
    return User.fromJson(data);
  }

  Future<User> getMe() async {
    final data = await _api.get('/users/me') as Map<String, dynamic>;
    return User.fromJson(data);
  }

  Future<void> logout() => _api.clearTokens();

  Future<bool> isLoggedIn() async {
    final token = await _api.getAccessToken();
    return token != null && token.isNotEmpty;
  }
}
