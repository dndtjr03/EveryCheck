import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  final AuthService _authService;

  AuthStatus _status = AuthStatus.unknown;
  User? _user;
  String? _error;

  AuthProvider(this._authService);

  AuthStatus get status => _status;
  User? get user => _user;
  String? get error => _error;
  bool get isLoggedIn => _status == AuthStatus.authenticated;

  static const _adminKey = 'test01';
  static final _adminUser = User(
    id: 0,
    email: 'admin@dabwadrim.kr',
    fullName: '관리자',
    isActive: true,
    createdAt: DateTime(2024),
  );

  Future<void> checkAuth() async {
    try {
      final token = await _authService.getSavedToken();
      if (token == _adminKey) {
        _user = _adminUser;
        _status = AuthStatus.authenticated;
        notifyListeners();
        return;
      }
      final loggedIn = await _authService.isLoggedIn();
      if (!loggedIn) {
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        return;
      }
      try {
        _user = await _authService.getMe();
        _status = AuthStatus.authenticated;
      } catch (_) {
        _status = AuthStatus.unauthenticated;
      }
    } catch (_) {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> login({required String email, required String password}) async {
    _error = null;
    // 관리자 로그인: 스토리지 저장 실패와 무관하게 즉시 로그인 처리
    if (email.trim() == _adminKey) {
      _user = _adminUser;
      _status = AuthStatus.authenticated;
      notifyListeners();
      _authService.saveAdminToken(_adminKey).catchError((_) {});
      return true;
    }
    try {
      _user = await _authService.login(email: email, password: password);
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _error = '로그인 중 오류가 발생했습니다.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    String? fullName,
  }) async {
    _error = null;
    try {
      await _authService.register(email: email, password: password, fullName: fullName);
      return await login(email: email, password: password);
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _error = '회원가입 중 오류가 발생했습니다.';
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    _user = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}
