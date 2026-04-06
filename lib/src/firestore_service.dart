import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

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
/// ├─ posted_properties/{id}
/// │    userId, title, price, location, type, imageUrl, vrUrl, createdAt
/// │
/// └─ chats/{sessionId}/messages/{messageId}
///      text, isUser, timestamp
class FirestoreService {
  FirestoreService._();

  static final FirestoreService instance = FirestoreService._();

  bool get _ready => Firebase.apps.isNotEmpty;

  /// Kiểm tra Firebase đã sẵn sàng chưa (dùng cho UI).
  bool get isReady => _ready;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  // ── User profile ────────────────────────────────────────────────

  /// Tạo hoặc cập nhật hồ sơ người dùng sau khi đăng ký / đăng nhập.
  Future<void> upsertUserProfile(User user) async {
    if (!_ready) return;
    final ref = _db.collection('users').doc(user.uid);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'name': user.displayName ?? '',
        'email': user.email ?? '',
        'phone': '',
        'membershipTier': null,
        'savedPropertyIds': <int>[],
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      // Cập nhật name/email mỗi lần đăng nhập (giữ nguyên các trường khác)
      await ref.update({
        'name': user.displayName?.isNotEmpty == true
            ? user.displayName!
            : (snap.data()?['name'] ?? ''),
        'email': user.email ?? '',
      });
    }
  }

  /// Lấy hồ sơ người dùng. Trả về null nếu chưa có.
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    if (!_ready) return null;
    final snap = await _db.collection('users').doc(uid).get();
    return snap.data();
  }

  /// Cập nhật số điện thoại người dùng.
  Future<void> updateUserPhone(String uid, String phone) async {
    if (!_ready) return;
    await _db.collection('users').doc(uid).update({'phone': phone.trim()});
  }

  /// Đếm số tin đăng của người dùng.
  Future<int> getUserPostingsCount(String uid) async {
    if (!_ready) return 0;
    final snap = await _db
        .collection('posted_properties')
        .where('userId', isEqualTo: uid)
        .count()
        .get();
    return snap.count ?? 0;
  }

  /// Đếm số cuộc trò chuyện thành viên của người dùng.
  Future<int> getUserConversationsCount(String uid) async {
    if (!_ready) return 0;
    final snap = await _db
        .collection('member_chats')
        .where('participants', arrayContains: uid)
        .count()
        .get();
    return snap.count ?? 0;
  }

  /// Tìm người dùng theo số điện thoại.
  /// Trả về map gồm `uid` + các trường hồ sơ, hoặc null nếu không tìm thấy.
  Future<Map<String, dynamic>?> findUserByPhone(String phone) async {
    if (!_ready) return null;
    final normalized = phone.trim().replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty) return null;
    final snap = await _db
        .collection('users')
        .where('phone', isEqualTo: normalized)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return {'uid': snap.docs.first.id, ...snap.docs.first.data()};
  }

  /// Cập nhật gói thành viên của người dùng.
  Future<void> updateMembershipTier(String uid, String? tier) {
    if (!_ready) return Future.value();
    return _db.collection('users').doc(uid).update({'membershipTier': tier});
  }

  /// Lưu / bỏ lưu một bất động sản.
  Future<void> toggleSavedProperty(String uid, int propertyId) async {
    if (!_ready) return;
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
    if (!_ready) return {};
    final snap = await _db.collection('users').doc(uid).get();
    final ids = (snap.data()?['savedPropertyIds'] as List? ?? []).map(
      (e) => e as int,
    );
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
  }) async {
    if (!_ready) return;
    await _db.collection('bookings').add({
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
  Future<void> postProperty({
    required String userId,
    required String ownerName,
    required String title,
    required String price,
    required String location,
    required String type,
    String? imageUrl,
    String? vrUrl,
    String? ownerPhone,
    int? bedrooms,
    String? area,
    String? floors,
    String? description,
  }) async {
    if (!_ready) return;
    await _db.collection('posted_properties').add({
      'userId': userId,
      'ownerName': ownerName,
      'ownerPhone': ownerPhone?.trim() ?? '',
      'title': title.trim(),
      'price': price.trim(),
      'location': location.trim(),
      'type': type,
      'imageUrl': imageUrl?.trim(),
      'vrUrl': vrUrl?.trim(),
      if (bedrooms != null) 'bedrooms': bedrooms,
      if (area != null) 'area': area.trim(),
      if (floors != null) 'floors': floors.trim(),
      if (description != null) 'description': description.trim(),
      'status': 'pending', // pending | published | rejected
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Xóa tin đăng bất động sản (chỉ xóa khi đúng chủ nhà gọi).
  Future<void> deleteProperty(String docId) async {
    if (!_ready) return;
    await _db.collection('posted_properties').doc(docId).delete();
  }

  /// Stream tin đăng của một người dùng cụ thể.
  Stream<List<Map<String, dynamic>>> getUserPostingsStream(String uid) {
    if (!_ready) return const Stream.empty();
    return _db
        .collection('posted_properties')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => {'_id': doc.id, ...doc.data()}).toList()
              ..sort((a, b) {
                final at = a['createdAt'];
                final bt = b['createdAt'];
                if (at == null && bt == null) return 0;
                if (at == null) return 1;
                if (bt == null) return -1;
                return (bt as dynamic).compareTo(at);
              }))
        .handleError((_) => <Map<String, dynamic>>[]);
  }

  /// Stream danh sách tin đã đăng (dùng cho Khám phá).
  Stream<List<Map<String, dynamic>>> getPostedPropertiesStream() {
    if (!_ready) return const Stream.empty();
    return _db
        .collection('posted_properties')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .where((doc) => doc.data()['status'] != 'rejected')
            .map((doc) => {'_id': doc.id, ...doc.data()})
            .toList());
  }

  // ── Member Chat ───────────────────────────────────────────────────────────

  String _chatId(String uid1, String uid2) {
    final sorted = [uid1, uid2]..sort();
    return sorted.join('_');
  }

  /// Tạo hoặc lấy phòng chat giữa 2 người dùng, trả về chatId.
  Future<String> initMemberChat({
    required String uid1,
    required String name1,
    required String uid2,
    required String name2,
    String? propertyTitle,
  }) async {
    final chatId = _chatId(uid1, uid2);
    if (!_ready) return chatId;
    final sorted = [uid1, uid2]..sort();
    await _db.collection('member_chats').doc(chatId).set({
      'participants': sorted,
      'participantNames': {uid1: name1, uid2: name2},
      'createdAt': FieldValue.serverTimestamp(),
      if (propertyTitle != null) 'propertyTitle': propertyTitle,
    }, SetOptions(merge: true));
    return chatId;
  }

  /// Gửi tin nhắn giữa thành viên.
  Future<void> sendMemberMessage({
    required String chatId,
    required String senderId,
    required String senderName,
    required String text,
    String? propertyTitle,
  }) async {
    if (!_ready) return;
    final chatRef = _db.collection('member_chats').doc(chatId);
    await chatRef.set({
      'lastMessage': text,
      'lastTime': FieldValue.serverTimestamp(),
      if (propertyTitle != null) 'propertyTitle': propertyTitle,
    }, SetOptions(merge: true));
    await chatRef.collection('messages').add({
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Stream tin nhắn realtime của một phòng chat.
  Stream<QuerySnapshot<Map<String, dynamic>>> getMemberMessagesStream(
      String chatId) {
    if (!_ready) return const Stream.empty();
    return _db
        .collection('member_chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp')
        .snapshots();
  }

  /// Stream danh sách hội thoại của người dùng.
  Stream<QuerySnapshot<Map<String, dynamic>>> getMyConversationsStream(
      String userId) {
    if (!_ready) return const Stream.empty();
    return _db
        .collection('member_chats')
        .where('participants', arrayContains: userId)
        .snapshots();
  }

  // ── Chat Bot ─────────────────────────────────────────────────────

  /// Lưu một tin nhắn chat vào Firestore.
  /// Cấu trúc: chats/{sessionId}/messages/{auto-id}
  Future<void> saveChatMessage({
    required String sessionId,
    required String text,
    required bool isUser,
  }) async {
    if (!_ready) return;
    await _db.collection('chats').doc(sessionId).collection('messages').add({
      'text': text,
      'isUser': isUser,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Lấy lịch sử chat của một session (sắp xếp theo thời gian tăng dần).
  Future<List<Map<String, dynamic>>> getChatHistory(String sessionId) async {
    if (!_ready) return [];
    final snap = await _db
        .collection('chats')
        .doc(sessionId)
        .collection('messages')
        .orderBy('timestamp')
        .get();
    return snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
  }

  /// Stream lịch sử chat theo thời gian thực (dùng cho real-time chat).
  Stream<QuerySnapshot<Map<String, dynamic>>> chatStream(String sessionId) {
    if (!_ready) {
      return const Stream.empty();
    }
    return _db
        .collection('chats')
        .doc(sessionId)
        .collection('messages')
        .orderBy('timestamp')
        .snapshots();
  }

  /// Xóa toàn bộ lịch sử chat của một session.
  Future<void> clearChatHistory(String sessionId) async {
    if (!_ready) return;
    final snap = await _db
        .collection('chats')
        .doc(sessionId)
        .collection('messages')
        .get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
