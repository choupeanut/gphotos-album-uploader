import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

final authServiceProvider = Provider<GoogleAuthService>((ref) {
  final service = GoogleAuthService();
  return service;
});

class GoogleAuthService {
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  GoogleSignInAccount? _currentUser;
  bool _initialized = false;
  
  final List<String> _scopes = [
    'email',
    'https://www.googleapis.com/auth/photoslibrary.appendonly',
  ];

  GoogleSignInAccount? get currentUser => _currentUser;

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      try {
        await _googleSignIn.initialize(
          serverClientId: '944913482390-663t9ebdou7cv60utb56vb6qaf95ju0c.apps.googleusercontent.com',
        ).timeout(const Duration(seconds: 10));
      } catch (e) {
        print('GoogleSignIn 初始化失敗: $e');
        // ignore errors if already initialized
      }
      _initialized = true;
      _googleSignIn.authenticationEvents.listen((event) {
        if (event is GoogleSignInAuthenticationEventSignIn) {
          _currentUser = event.user;
        } else if (event is GoogleSignInAuthenticationEventSignOut) {
          _currentUser = null;
        }
      });
    }
  }

  /// 觸發登入
  Future<GoogleSignInAccount?> signIn() async {
    await _ensureInitialized();
    try {
      final account = await _googleSignIn.authenticate(scopeHint: _scopes).timeout(const Duration(seconds: 30));
      _currentUser = account;
      return account;
    } catch (e, stackTrace) {
      print('Google SignIn 發生錯誤: $e');
      print('StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// 靜默登入 (開啟 App 時自動嘗試恢復上次登入狀態)
  Future<GoogleSignInAccount?> signInSilently() async {
    await _ensureInitialized();
    try {
      final future = _googleSignIn.attemptLightweightAuthentication();
      final account = future != null ? await future.timeout(const Duration(seconds: 10)) : null;
      _currentUser = account;
      return account;
    } catch (e) {
      print('靜默登入失敗: $e');
      return null;
    }
  }

  /// 登出
  Future<void> signOut() async {
    await _ensureInitialized();
    await _googleSignIn.signOut().timeout(const Duration(seconds: 5), onTimeout: () => null);
    _currentUser = null;
  }

  /// 取得 API 驗證的 Header
  Future<Map<String, String>?> getAuthHeaders() async {
    await _ensureInitialized();
    if (_currentUser == null) return null;
    
    try {
      // 根據 Google Sign In 7.0.0，需要透過 authorizationClient 取得授權 Headers
      final authHeaders = await _currentUser!.authorizationClient.authorizationHeaders(_scopes, promptIfNecessary: true).timeout(const Duration(seconds: 15));
      return authHeaders;
    } catch(e) {
       print('取得 Authorization headers 發生錯誤: $e');
       return null;
    }
  }
  
  /// 取得原始的 Access Token
  Future<String?> getAccessToken() async {
    await _ensureInitialized();
    if (_currentUser == null) {
      await signInSilently();
    }
    if (_currentUser == null) return null;

    try {
       // Timeout 避免因等待使用者授權 UI 彈窗而在背景卡死
       final authz = await _currentUser!.authorizationClient.authorizeScopes(_scopes).timeout(const Duration(seconds: 15));
       return authz.accessToken;
    } catch(e) {
       print('取得 Access Token 發生錯誤: $e');
       return null;
    }
  }
}
