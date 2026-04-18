import 'package:supabase_flutter/supabase_flutter.dart';

/// Wrapper user đơn giản – thay thế Firebase User.
class AppUser {
  const AppUser({required this.uid, this.email, this.displayName});

  final String uid;
  final String? email;
  final String? displayName;
}

/// Kết quả trả về từ các thao tác đăng nhập / đăng ký.
class AuthResult {
  const AuthResult({this.user, this.errorMessage});

  final AppUser? user;
  final String? errorMessage;

  bool get isSuccess => user != null;
}

/// Dịch vụ xác thực tài khoản qua Supabase Auth.
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  SupabaseClient get _client => Supabase.instance.client;

  AppUser? _fromSupabaseUser(User? user) {
    if (user == null) return null;
    return AppUser(
      uid: user.id,
      email: user.email,
      displayName: user.userMetadata?['full_name'] as String? ??
          user.email?.split('@').first,
    );
  }

  /// Người dùng hiện tại (null nếu chưa đăng nhập).
  AppUser? get currentUser => _fromSupabaseUser(_client.auth.currentUser);

  /// Stream theo dõi trạng thái xác thực.
  Stream<AppUser?> get authStateChanges {
    return _client.auth.onAuthStateChange.map(
      (event) => _fromSupabaseUser(event.session?.user),
    );
  }

  /// Đăng ký tài khoản mới bằng email và mật khẩu.
  Future<AuthResult> register({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'full_name': name.trim()},
      );
      final user = response.user;
      if (user == null) {
        return const AuthResult(
          errorMessage: 'Đăng ký thất bại. Vui lòng thử lại.',
        );
      }
      return AuthResult(user: _fromSupabaseUser(user));
    } on AuthException catch (e) {
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
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final user = response.user;
      if (user == null) {
        return const AuthResult(
          errorMessage: 'Đăng nhập thất bại. Vui lòng thử lại.',
        );
      }
      return AuthResult(user: _fromSupabaseUser(user));
    } on AuthException catch (e) {
      return AuthResult(errorMessage: _mapError(e));
    } catch (_) {
      return AuthResult(errorMessage: 'Đã xảy ra lỗi. Vui lòng thử lại.');
    }
  }

  /// Đăng xuất.
  Future<void> signOut() => _client.auth.signOut();

  /// Đổi tên hiển thị.
  Future<void> updateDisplayName(String name) async {
    await _client.auth.updateUser(UserAttributes(data: {'full_name': name}));
    final uid = _client.auth.currentUser?.id;
    if (uid != null) {
      await _client
          .from('users')
          .update({'full_name': name})
          .eq('id', uid);
    }
  }

  /// Đổi mật khẩu (xác thực lại bằng email + mật khẩu cũ trước).
  Future<String?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final email = _client.auth.currentUser?.email ?? '';
      // Xác thực lại
      await _client.auth.signInWithPassword(
        email: email,
        password: currentPassword,
      );
      // Đổi mật khẩu
      await _client.auth.updateUser(UserAttributes(password: newPassword));
      return null; // null = thành công
    } on AuthException catch (e) {
      return _mapError(e);
    } catch (_) {
      return 'Đã xảy ra lỗi. Vui lòng thử lại.';
    }
  }

  String _mapError(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('already registered') ||
        msg.contains('already been registered') ||
        msg.contains('user already exists')) {
      return 'Email này đã được dùng bởi tài khoản khác.';
    }
    if (msg.contains('invalid email')) return 'Địa chỉ email không hợp lệ.';
    if (msg.contains('weak password') || msg.contains('password should be')) {
      return 'Mật khẩu quá yếu. Vui lòng dùng ít nhất 6 ký tự.';
    }
    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid credentials') ||
        msg.contains('wrong password')) {
      return 'Email hoặc mật khẩu không đúng.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Vui lòng xác nhận email trước khi đăng nhập.';
    }
    if (msg.contains('too many requests')) {
      return 'Quá nhiều lần thử. Hãy thử lại sau ít phút.';
    }
    return e.message.isNotEmpty ? e.message : 'Đã xảy ra lỗi. Vui lòng thử lại.';
  }
}
