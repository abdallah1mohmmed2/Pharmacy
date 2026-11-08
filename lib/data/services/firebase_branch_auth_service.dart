import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Firebase identity for one pharmacy branch. Firebase Auth owns and refreshes
/// tokens; passwords are never copied into SQLite or ERP settings.
class FirebaseBranchAuthService {
  FirebaseBranchAuthService._();
  static final FirebaseBranchAuthService instance = FirebaseBranchAuthService._();
  FirebaseApp? _app;
  FirebaseAuth? _auth;

  Future<void> configure({
    required String apiKey,
    required String appId,
    required String messagingSenderId,
    required String projectId,
  }) async {
    if ([apiKey, appId, messagingSenderId, projectId]
        .any((value) => value.trim().isEmpty)) {
      throw StateError('إعداد Firebase يحتاج api_key وapp_id وmessaging_sender_id وproject_id');
    }
    if (_app?.options.projectId == projectId && _app?.options.apiKey == apiKey) return;
    if (_app != null) {
      await _auth?.signOut();
      await _app!.delete();
      _app = null;
      _auth = null;
    }
    final name = 'pharmacy-branch-$projectId';
    final existing = Firebase.apps.where((app) => app.name == name);
    _app = existing.isNotEmpty ? existing.first : await Firebase.initializeApp(
      name: name,
      options: FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
      ),
    );
    _auth = FirebaseAuth.instanceFor(app: _app!);
  }

  bool get isSignedIn => _auth?.currentUser != null;
  String? get uid => _auth?.currentUser?.uid;
  String? get email => _auth?.currentUser?.email;

  Future<void> signIn({required String email, required String password}) async {
    final auth = _auth;
    if (auth == null) throw StateError('يجب إعداد Firebase أولاً');
    await auth.signInWithEmailAndPassword(email: email.trim(), password: password);
  }

  Future<String?> idToken() async => _auth?.currentUser?.getIdToken();

  Future<void> signOut() async {
    await _auth?.signOut();
  }
}
