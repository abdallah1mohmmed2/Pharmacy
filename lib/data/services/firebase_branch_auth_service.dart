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

  Future<void> configure({required String apiKey}) async {
    if (apiKey.trim().isEmpty)
      throw StateError('أدخل Firebase api_key في إعداد 35');
    _apiKey = apiKey.trim();
    _refreshToken ??= await _storage.read(key: 'firebase_branch_refresh_token');
    _uid ??= await _storage.read(key: 'firebase_branch_uid');
    _email ??= await _storage.read(key: 'firebase_branch_email');
  }

  bool get isSignedIn => _refreshToken != null || _idToken != null;
  String? get uid => _uid;
  String? get email => _email;

  Future<void> signIn({required String email, required String password}) async {
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
    if (_refreshToken == null) {
      _refreshToken = await _storage.read(key: 'firebase_branch_refresh_token');
    }
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
    final data = _decodeResponse(response, 'Firebase token refresh');
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
    if (_uid != null)
      await _storage.write(key: 'firebase_branch_uid', value: _uid);
    return _idToken;
  }

  Future<void> signOut() async {
    _idToken = null;
    _refreshToken = null;
    _uid = null;
    _email = null;
    _expiresAt = null;
    await _storage.delete(key: 'firebase_branch_refresh_token');
    await _storage.delete(key: 'firebase_branch_uid');
    await _storage.delete(key: 'firebase_branch_email');
    await _storage.delete(key: 'firebase_branch_project_id');
  }

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
