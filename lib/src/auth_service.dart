import 'package:firebase_auth/firebase_auth.dart';

/// Kết quả trả về từ các thao tác đăng nhập / đăng ký.
class AuthResult {
  const AuthResult({this.user, this.errorMessage});

  final User? user;
  final String? errorMessage;

  bool get isSuccess => user != null;
}

/// Dịch vụ xác thực tài khoản qua Firebase Authentication.
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  final _auth = FirebaseAuth.instance;

  /// Người dùng hiện tại (null nếu chưa đăng nhập).
  User? get currentUser => _auth.currentUser;

  /// Stream theo dõi trạng thái xác thực.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Đăng ký tài khoản mới bằng email và mật khẩu.
  Future<AuthResult> register({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await credential.user?.updateDisplayName(name.trim());
      return AuthResult(user: credential.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult(errorMessage: _mapError(e));
    } catch (_) {
      return AuthResult(errorMessage: 'Đã xảy ra lỗi. Vui lòng thử lại.');
    }
  }

  /// Đăng nhập bằng email và mật khẩu.
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return AuthResult(user: credential.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult(errorMessage: _mapError(e));
    } catch (_) {
      return AuthResult(errorMessage: 'Đã xảy ra lỗi. Vui lòng thử lại.');
    }
  }

  /// Đăng xuất.
  Future<void> signOut() => _auth.signOut();

  String _mapError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'Email này đã được dùng bởi tài khoản khác.';
      case 'invalid-email':
        return 'Địa chỉ email không hợp lệ.';
      case 'weak-password':
        return 'Mật khẩu quá yếu. Vui lòng dùng ít nhất 6 ký tự.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email hoặc mật khẩu không đúng.';
      case 'user-disabled':
        return 'Tài khoản này đã bị vô hiệu hóa.';
      case 'too-many-requests':
        return 'Quá nhiều lần thử. Hãy thử lại sau ít phút.';
      case 'network-request-failed':
        return 'Lỗi kết nối mạng. Kiểm tra internet và thử lại.';
      default:
        return e.message ?? 'Đã xảy ra lỗi. Vui lòng thử lại.';
    }
  }
}
