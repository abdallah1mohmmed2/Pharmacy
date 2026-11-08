import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Cross-platform Firebase Authentication REST client.
///
/// Only the refresh token is persisted, in OS-backed secure storage. Passwords
/// are sent directly to Firebase Auth and are never persisted by this class.
class FirebaseBranchAuthService {
  FirebaseBranchAuthService(
      {http.Client? client, FlutterSecureStorage? storage})
      : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  static final FirebaseBranchAuthService instance = FirebaseBranchAuthService();

  final http.Client _client;
  final FlutterSecureStorage _storage;
  String? _apiKey;
  String? _projectId;
  String? _idToken;
  String? _refreshToken;
  String? _uid;
  String? _email;
  DateTime? _expiresAt;
  Future<String?>? _tokenRefresh;
  int _sessionGeneration = 0;

  String get _authEmulatorHost =>
      const String.fromEnvironment('FIREBASE_AUTH_EMULATOR_HOST');

  Uri _identityUri(String path) {
    if (_authEmulatorHost.isNotEmpty) {
      final host = _authEmulatorHost.contains('://')
          ? _authEmulatorHost
          : 'http://' + _authEmulatorHost;
      return Uri.parse(host + '/identitytoolkit.googleapis.com/v1/' + path);
    }
    return Uri.https('identitytoolkit.googleapis.com', '/v1/' + path);
  }

  Uri _tokenUri() {
    if (_authEmulatorHost.isNotEmpty) {
      final host = _authEmulatorHost.contains('://')
          ? _authEmulatorHost
          : 'http://' + _authEmulatorHost;
      return Uri.parse(host + '/securetoken.googleapis.com/v1/token');
    }
    return Uri.https('securetoken.googleapis.com', '/v1/token');
  }

  Future<void> configure({
    required String apiKey,
    required String projectId,
  }) async {
    if (apiKey.trim().isEmpty || projectId.trim().isEmpty) {
      throw StateError('أدخل Firebase project_id وapi_key في إعداد 35');
    }
    final persistedProject =
        await _storage.read(key: 'firebase_branch_project_id');
    if (persistedProject != null && persistedProject != projectId.trim()) {
      await signOut();
    }
    _apiKey = apiKey.trim();
    _projectId = projectId.trim();
    await _storage.write(key: 'firebase_branch_project_id', value: _projectId);
    _refreshToken ??= await _storage.read(key: 'firebase_branch_refresh_token');
    _uid ??= await _storage.read(key: 'firebase_branch_uid');
    _email ??= await _storage.read(key: 'firebase_branch_email');
  }

  bool get isSignedIn => _refreshToken != null || _idToken != null;
  String? get uid => _uid;
  String? get email => _email;

  Future<void> signIn({required String email, required String password}) async {
    final generation = ++_sessionGeneration;
    final key = _apiKey;
    if (key == null) throw StateError('يجب إعداد Firebase أولاً');
    final response = await _client
        .post(
          _identityUri('accounts:signInWithPassword')
              .replace(queryParameters: {'key': key}),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email.trim(),
            'password': password,
            'returnSecureToken': true,
          }),
        )
        .timeout(const Duration(seconds: 20));
    final data = _decodeResponse(response, 'Firebase Auth sign-in');
    if (generation != _sessionGeneration) {
      throw StateError('تم إلغاء محاولة تسجيل الدخول بسبب تغيير الجلسة');
    }
    _idToken = data['idToken']?.toString();
    _refreshToken = data['refreshToken']?.toString();
    _uid = data['localId']?.toString();
    _email = data['email']?.toString();
    _expiresAt = DateTime.now().add(
      Duration(
          seconds: int.tryParse(data['expiresIn']?.toString() ?? '') ?? 3600),
    );
    if (_idToken == null || _refreshToken == null || _uid == null) {
      throw StateError('استجابة Firebase Auth لا تحتوي بيانات الجلسة المطلوبة');
    }
    await _storage.write(
        key: 'firebase_branch_refresh_token', value: _refreshToken);
    await _storage.write(key: 'firebase_branch_uid', value: _uid);
    await _storage.write(key: 'firebase_branch_email', value: _email);
  }

  Future<String?> idToken() async {
    final activeRefresh = _tokenRefresh;
    if (activeRefresh != null) return activeRefresh;
    final pending = _loadOrRefreshIdToken();
    _tokenRefresh = pending;
    try {
      return await pending;
    } finally {
      if (identical(_tokenRefresh, pending)) _tokenRefresh = null;
    }
  }

  /// Forces a refresh-token exchange so newly issued Custom Claims become
  /// visible immediately instead of waiting for the current ID token to expire.
  Future<String?> forceRefreshIdToken() async {
    final activeRefresh = _tokenRefresh;
    if (activeRefresh != null) await activeRefresh;
    _idToken = null;
    _expiresAt = null;
    return idToken();
  }

  Future<String?> _loadOrRefreshIdToken() async {
    final generation = _sessionGeneration;
    if (_refreshToken == null) {
      _refreshToken = await _storage.read(key: 'firebase_branch_refresh_token');
    }
    if (generation != _sessionGeneration) return null;
    if (_refreshToken == null) return _idToken;
    if (_idToken != null &&
        _expiresAt != null &&
        _expiresAt!.isAfter(DateTime.now().add(const Duration(minutes: 2)))) {
      return _idToken;
    }
    final key = _apiKey;
    if (key == null) throw StateError('Firebase api_key غير مضبوط');
    final response = await _client.post(
      _tokenUri().replace(queryParameters: {'key': key}),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': _refreshToken!,
      },
    ).timeout(const Duration(seconds: 20));
    if (generation != _sessionGeneration) return null;
    if (response.statusCode == 400 || response.statusCode == 401) {
      // A rejected refresh token is no longer a usable session. Clear only
      // authentication material; keep the configured project identifier.
      await _clearSession();
    }
    final data = _decodeResponse(response, 'Firebase token refresh');
    if (generation != _sessionGeneration) return null;
    _idToken = data['id_token']?.toString();
    _refreshToken = data['refresh_token']?.toString() ?? _refreshToken;
    _uid = data['user_id']?.toString() ?? _uid;
    _expiresAt = DateTime.now().add(
      Duration(
          seconds: int.tryParse(data['expires_in']?.toString() ?? '') ?? 3600),
    );
    if (_idToken == null) throw StateError('لم يصدر Firebase ID token');
    await _storage.write(
        key: 'firebase_branch_refresh_token', value: _refreshToken);
    if (_uid != null) {
      await _storage.write(key: 'firebase_branch_uid', value: _uid);
    }
    return _idToken;
  }

  Future<void> _clearSession({bool clearProject = false}) async {
    _sessionGeneration++;
    _idToken = null;
    _refreshToken = null;
    _uid = null;
    _email = null;
    _expiresAt = null;
    await _storage.delete(key: 'firebase_branch_refresh_token');
    await _storage.delete(key: 'firebase_branch_uid');
    await _storage.delete(key: 'firebase_branch_email');
    if (clearProject) {
      await _storage.delete(key: 'firebase_branch_project_id');
    }
  }

  Future<void> signOut() => _clearSession(clearProject: true);

  Map<String, dynamic> _decodeResponse(
      http.Response response, String operation) {
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded['error'] is Map
          ? (decoded['error']['message'] ?? 'unknown').toString()
          : response.body;
      throw StateError(
          '$operation failed (HTTP ${response.statusCode}): $message');
    }
    return decoded;
  }
}
