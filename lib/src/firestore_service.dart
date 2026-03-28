import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Dịch vụ thao tác với Cloud Firestore.
///
/// Cấu trúc các collection:
/// ┌─ users/{uid}
/// │    name, email, membershipTier (null | 'monthly' | 'quarterly' | 'yearly'),
/// │    savedPropertyIds: [1, 3, ...]
/// │
/// ├─ bookings/{id}
/// │    userId, propertyId, propertyTitle, name, phone, schedule,
/// │    notes, type ('book' | 'contact'), createdAt
/// │
/// └─ posted_properties/{id}
///      userId, title, price, location, type, imageUrl, vrUrl, createdAt
class FirestoreService {
  FirestoreService._();

  static final FirestoreService instance = FirestoreService._();

  final _db = FirebaseFirestore.instance;

  // ── User profile ────────────────────────────────────────────────

  /// Tạo hoặc cập nhật hồ sơ người dùng sau khi đăng ký / đăng nhập.
  Future<void> upsertUserProfile(User user) async {
    final ref = _db.collection('users').doc(user.uid);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'name': user.displayName ?? '',
        'email': user.email ?? '',
        'membershipTier': null,
        'savedPropertyIds': <int>[],
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Lấy hồ sơ người dùng. Trả về null nếu chưa có.
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    final snap = await _db.collection('users').doc(uid).get();
    return snap.data();
  }

  /// Cập nhật gói thành viên của người dùng.
  Future<void> updateMembershipTier(String uid, String? tier) {
    return _db
        .collection('users')
        .doc(uid)
        .update({'membershipTier': tier});
  }

  /// Lưu / bỏ lưu một bất động sản.
  Future<void> toggleSavedProperty(String uid, int propertyId) async {
    final ref = _db.collection('users').doc(uid);
    final snap = await ref.get();
    final ids = List<int>.from(
      (snap.data()?['savedPropertyIds'] as List? ?? []).map((e) => e as int),
    );
    if (ids.contains(propertyId)) {
      ids.remove(propertyId);
    } else {
      ids.add(propertyId);
    }
    await ref.update({'savedPropertyIds': ids});
  }

  /// Trả về danh sách id bất động sản đã lưu.
  Future<Set<int>> getSavedPropertyIds(String uid) async {
    final snap = await _db.collection('users').doc(uid).get();
    final ids =
        (snap.data()?['savedPropertyIds'] as List? ?? []).map((e) => e as int);
    return ids.toSet();
  }

  // ── Bookings ─────────────────────────────────────────────────────

  /// Lưu yêu cầu đặt lịch xem nhà hoặc tư vấn.
  Future<void> createBooking({
    required String userId,
    required int propertyId,
    required String propertyTitle,
    required String name,
    required String phone,
    required String type, // 'book' | 'contact'
    String? schedule,
    String? notes,
  }) {
    return _db.collection('bookings').add({
      'userId': userId,
      'propertyId': propertyId,
      'propertyTitle': propertyTitle,
      'name': name.trim(),
      'phone': phone.trim(),
      'type': type,
      'schedule': schedule?.trim(),
      'notes': notes?.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Posted properties ─────────────────────────────────────────────

  /// Lưu tin đăng bất động sản của chủ nhà.
  Future<DocumentReference> postProperty({
    required String userId,
    required String title,
    required String price,
    required String location,
    required String type,
    String? imageUrl,
    String? vrUrl,
  }) {
    return _db.collection('posted_properties').add({
      'userId': userId,
      'title': title.trim(),
      'price': price.trim(),
      'location': location.trim(),
      'type': type,
      'imageUrl': imageUrl?.trim(),
      'vrUrl': vrUrl?.trim(),
      'status': 'pending', // pending | published | rejected
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
