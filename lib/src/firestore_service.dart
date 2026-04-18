import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';

/// Dịch vụ thao tác với Supabase (thay thế Cloud Firestore).
class FirestoreService {
  FirestoreService._();

  static final FirestoreService instance = FirestoreService._();

  SupabaseClient get _db => Supabase.instance.client;

  /// Luôn sẵn sàng khi Supabase đã được khởi tạo.
  bool get isReady => true;

  // ── User profile ────────────────────────────────────────────────

  /// Tạo hoặc cập nhật hồ sơ người dùng sau khi đăng ký / đăng nhập.
  Future<void> upsertUserProfile(AppUser user) async {
    await _db.from('users').upsert({
      'id': user.uid,
      'email': user.email ?? '',
      'full_name': user.displayName ?? '',
    }, onConflict: 'id');
  }

  /// Lấy hồ sơ người dùng. Trả về null nếu chưa có.
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    final data = await _db
        .from('users')
        .select()
        .eq('id', uid)
        .maybeSingle();
    return data;
  }

  /// Cập nhật số điện thoại người dùng (normalize: bỏ khoảng trắng).
  Future<void> updateUserPhone(String uid, String phone) async {
    final normalized = phone.trim().replaceAll(RegExp(r'\s+'), '');
    await _db
        .from('users')
        .update({'phone': normalized})
        .eq('id', uid);
  }

  /// Đếm số tin đăng của người dùng.
  Future<int> getUserPostingsCount(String uid) async {
    final response = await _db
        .from('user_listings')
        .select('id')
        .eq('user_id', uid);
    return (response as List).length;
  }

  /// Đếm số cuộc trò chuyện thành viên của người dùng.
  Future<int> getUserConversationsCount(String uid) async {
    final response = await _db
        .from('member_chat_rooms')
        .select('id')
        .or('participant1_id.eq.$uid,participant2_id.eq.$uid');
    return (response as List).length;
  }

  /// Tìm người dùng theo số điện thoại.
  Future<Map<String, dynamic>?> findUserByPhone(String phone) async {
    final normalized = phone.trim().replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty) return null;
    final data = await _db
        .from('users')
        .select()
        .eq('phone', normalized)
        .maybeSingle();
    if (data == null) return null;
    // Giữ 'uid' key để tương thích với UI hiện tại
    return {'uid': data['id'], ...data};
  }

  /// Cập nhật avatar URL của người dùng.
  Future<void> updateAvatarUrl(String uid, String? url) async {
    await _db.from('users').update({'avatar_url': url}).eq('id', uid);
  }

  /// Cập nhật gói thành viên của người dùng, tự tính ngày bắt đầu + hết hạn.
  Future<void> updateMembershipTier(String uid, String? tier) async {
    final now = DateTime.now().toUtc();
    final expiry = tier == null
        ? null
        : switch (tier) {
            'monthly' => now.add(const Duration(days: 30)),
            'quarterly' => now.add(const Duration(days: 90)),
            'yearly' => now.add(const Duration(days: 365)),
            _ => now.add(const Duration(days: 30)),
          };
    await _db.from('users').update({
      'membership_tier': tier,
      'membership_start_date':
          tier != null ? now.toIso8601String() : null,
      'membership_expiry_date': expiry?.toIso8601String(),
    }).eq('id', uid);
  }

  /// Lưu / bỏ lưu một bất động sản (demo property với ID nguyên).
  Future<void> toggleSavedProperty(String uid, int propertyId) async {
    final data = await _db
        .from('users')
        .select('saved_property_ids')
        .eq('id', uid)
        .maybeSingle();
    if (data == null) return;
    final ids = List<int>.from(
      (data['saved_property_ids'] as List? ?? []).map((e) => e as int),
    );
    if (ids.contains(propertyId)) {
      ids.remove(propertyId);
    } else {
      ids.add(propertyId);
    }
    await _db
        .from('users')
        .update({'saved_property_ids': ids})
        .eq('id', uid);
  }

  /// Trả về danh sách id bất động sản đã lưu.
  Future<Set<int>> getSavedPropertyIds(String uid) async {
    final data = await _db
        .from('users')
        .select('saved_property_ids')
        .eq('id', uid)
        .maybeSingle();
    if (data == null) return {};
    return List<int>.from(
      (data['saved_property_ids'] as List? ?? []).map((e) => e as int),
    ).toSet();
  }

  // ── Bookings ─────────────────────────────────────────────────────

  /// Gửi yêu cầu tư vấn dịch vụ VR cho admin.
  Future<void> createServiceInquiry({
    required String packageType, // 'vr_basic' | 'vr_pro' | 'vr_premium'
    required String packageName,
    required String name,
    required String phone,
    String? address,
    String? notes,
  }) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    await _db.from('user_bookings').insert({
      if (uid != null) 'user_id': uid,
      'property_id_raw': 0,
      'property_title': packageName,
      'contact_name': name.trim(),
      'contact_phone': phone.trim(),
      'booking_type': packageType,
      if (address != null && address.trim().isNotEmpty)
        'schedule': address.trim(),
      if (notes != null && notes.trim().isNotEmpty)
        'notes': notes.trim(),
    });
  }

  /// Lưu yêu cầu đặt lịch xem nhà hoặc tư vấn.
  Future<void> createBooking({
    required String userId,
    required int propertyId,
    required String propertyTitle,
    required String name,
    required String phone,
    required String type,
    String? schedule,
    String? notes,
    String? ownerId,
  }) async {
    await _db.from('user_bookings').insert({
      'user_id': userId,
      'property_id_raw': propertyId,
      'property_title': propertyTitle,
      'contact_name': name.trim(),
      'contact_phone': phone.trim(),
      'booking_type': type,
      'schedule': schedule?.trim(),
      'notes': notes?.trim(),
    });
    // Thông báo cho chủ nhà (nếu có ownerId)
    if (ownerId != null) {
      await _createNotification(
        userId: ownerId,
        type: 'booking_update',
        title: '📅 Có lịch hẹn mới',
        body: '$name muốn đặt lịch xem "$propertyTitle"',
      );
    }
  }

  // ── User listings (posted properties) ────────────────────────────

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
    await _db.from('user_listings').insert({
      'user_id': userId,
      'owner_name': ownerName,
      'owner_phone': ownerPhone?.trim() ?? '',
      'title': title.trim(),
      'price': price.trim(),
      'location': location.trim(),
      'type': type,
      'image_url': imageUrl?.trim(),
      'vr_url': vrUrl?.trim(),
      if (bedrooms != null) 'bedrooms': bedrooms,
      if (area != null) 'area': area.trim(),
      if (floors != null) 'floors': floors.trim(),
      if (description != null) 'description': description.trim(),
      'status': 'pending',
    });
  }

  /// Xóa tin đăng bất động sản.
  Future<void> deleteProperty(String docId) async {
    await _db.from('user_listings').delete().eq('id', docId);
  }

  /// Stream tin đăng của một người dùng cụ thể.
  Stream<List<Map<String, dynamic>>> getUserPostingsStream(String uid) {
    return _db
        .from('user_listings')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .map((rows) => rows
            .map((r) => {'_id': r['id'] as String, ...r})
            .toList());
  }

  /// Stream danh sách tất cả tin đã đăng (dùng cho Khám phá).
  Stream<List<Map<String, dynamic>>> getPostedPropertiesStream() {
    final controller =
        StreamController<List<Map<String, dynamic>>>.broadcast();

    Future<void> fetch() async {
      try {
        final data = await _db
            .from('user_listings')
            .select()
            .neq('status', 'rejected')
            .order('created_at', ascending: false);
        if (!controller.isClosed) {
          controller.add((data as List)
              .map((r) => Map<String, dynamic>.from(r as Map)
                ..['_id'] = r['id'])
              .toList());
        }
      } catch (_) {
        if (!controller.isClosed) controller.add([]);
      }
    }

    fetch();

    final channel = _db
        .channel('user_listings_explore')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_listings',
          callback: (_) => fetch(),
        )
        .subscribe();

    controller.onCancel = () {
      _db.removeChannel(channel);
    };

    return controller.stream;
  }

  // ── Member Chat ───────────────────────────────────────────────────────────

  /// Tạo hoặc lấy phòng chat giữa 2 người dùng, trả về chatId.
  Future<String> initMemberChat({
    required String uid1,
    required String name1,
    required String uid2,
    required String name2,
    String? propertyTitle,
  }) async {
    final sorted = [uid1, uid2]..sort();
    final chatId = sorted.join('_');
    final p1 = sorted[0];
    final p2 = sorted[1];
    final n1 = p1 == uid1 ? name1 : name2;
    final n2 = p2 == uid2 ? name2 : name1;

    await _db.from('member_chat_rooms').upsert({
      'id': chatId,
      'participant1_id': p1,
      'participant2_id': p2,
      'participant1_name': n1,
      'participant2_name': n2,
      if (propertyTitle != null) 'property_title': propertyTitle,
    }, onConflict: 'id');

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
    await _db.from('member_chat_messages').insert({
      'room_id': chatId,
      'sender_id': senderId,
      'sender_name': senderName,
      'text': text,
    });
    await _db.from('member_chat_rooms').update({
      'last_message': text,
      'last_message_at': DateTime.now().toIso8601String(),
      if (propertyTitle != null) 'property_title': propertyTitle,
    }).eq('id', chatId);
  }

  /// Stream tin nhắn realtime của một phòng chat.
  Stream<List<Map<String, dynamic>>> getMemberMessagesStream(String chatId) {
    return _db
        .from('member_chat_messages')
        .stream(primaryKey: ['id'])
        .eq('room_id', chatId)
        .order('created_at', ascending: true);
  }

  /// Stream danh sách hội thoại của người dùng.
  Stream<List<Map<String, dynamic>>> getMyConversationsStream(String userId) {
    final controller =
        StreamController<List<Map<String, dynamic>>>.broadcast();

    Future<void> fetch() async {
      try {
        final data = await _db
            .from('member_chat_rooms')
            .select()
            .or('participant1_id.eq.$userId,participant2_id.eq.$userId')
            .order('last_message_at', ascending: false, nullsFirst: false);

        final transformed = (data as List).map((room) {
          final r = Map<String, dynamic>.from(room as Map);
          final tsStr = r['last_message_at'] as String?;
          return {
            'id': r['id'],
            'participantNames': {
              r['participant1_id']: r['participant1_name'],
              r['participant2_id']: r['participant2_name'],
            },
            'lastMessage': r['last_message'] ?? '',
            'lastTime': tsStr != null
                ? DateTime.parse(tsStr).millisecondsSinceEpoch
                : null,
            'propertyTitle': r['property_title'],
          };
        }).toList();

        if (!controller.isClosed) controller.add(transformed);
      } catch (_) {
        if (!controller.isClosed) controller.add([]);
      }
    }

    fetch();

    final channel = _db
        .channel('member_chat_rooms_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'member_chat_rooms',
          callback: (_) => fetch(),
        )
        .subscribe();

    controller.onCancel = () {
      _db.removeChannel(channel);
    };

    return controller.stream;
  }

  // ── Admin ────────────────────────────────────────────────────────

  /// Thống kê tổng quan cho admin.
  Future<Map<String, int>> getAdminStats() async {
    final results = await Future.wait([
      _db.from('users').select('id'),
      _db.from('user_listings').select('id'),
      _db.from('user_listings').select('id').eq('status', 'pending'),
      _db.from('user_bookings').select('id'),
    ]);
    return {
      'users': (results[0] as List).length,
      'listings': (results[1] as List).length,
      'pending': (results[2] as List).length,
      'bookings': (results[3] as List).length,
    };
  }

  /// Flatten profiles join vào map phẳng (owner_name, owner_email, owner_phone).
  List<Map<String, dynamic>> _flattenListings(List raw) {
    return raw.map((r) {
      final m = Map<String, dynamic>.from(r as Map);
      final profile = m['profiles'] as Map?;
      if (profile != null) {
        m['owner_name'] = profile['full_name'] as String? ?? '';
        m['owner_email'] = profile['email'] as String? ?? '';
        m['owner_phone'] = profile['phone'] as String? ?? '';
        m.remove('profiles');
      }
      return m;
    }).toList();
  }

  /// Toàn bộ tin đăng (admin view).
  Future<List<Map<String, dynamic>>> getAdminListings() async {
    final data = await _db
        .from('user_listings')
        .select('*, profiles!user_id(full_name, email, phone)')
        .order('created_at', ascending: false);
    return _flattenListings(data as List);
  }

  /// Stream tin đăng cho admin (realtime).
  Stream<List<Map<String, dynamic>>> getAdminListingsStream() {
    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();

    Future<void> fetch() async {
      try {
        final data = await _db
            .from('user_listings')
            .select('*, profiles!user_id(full_name, email, phone)')
            .order('created_at', ascending: false);
        if (!controller.isClosed) {
          controller.add(_flattenListings(data as List));
        }
      } catch (_) {
        if (!controller.isClosed) controller.add([]);
      }
    }

    fetch();
    final channel = _db
        .channel('admin_listings')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_listings',
          callback: (_) => fetch(),
        )
        .subscribe();
    controller.onCancel = () => _db.removeChannel(channel);
    return controller.stream;
  }

  // ── Notifications ────────────────────────────────────────────────

  /// Tạo một thông báo mới cho người dùng.
  Future<void> _createNotification({
    required String userId,
    required String type,
    required String title,
    String? body,
  }) async {
    try {
      await _db.from('notifications').insert({
        'user_id': userId,
        'type': type,
        'title': title,
        if (body != null) 'body': body,
      });
    } catch (_) {}
  }

  /// Stream số thông báo chưa đọc (dùng cho badge trên chuông).
  Stream<int> getUnreadNotificationCount(String uid) {
    final controller = StreamController<int>.broadcast();

    Future<void> fetch() async {
      try {
        final data = await _db
            .from('notifications')
            .select('id')
            .eq('user_id', uid)
            .eq('is_read', false);
        if (!controller.isClosed) controller.add((data as List).length);
      } catch (_) {
        if (!controller.isClosed) controller.add(0);
      }
    }

    fetch();
    final channel = _db
        .channel('notif_count_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          callback: (_) => fetch(),
        )
        .subscribe();
    controller.onCancel = () => _db.removeChannel(channel);
    return controller.stream;
  }

  /// Stream danh sách thông báo (50 cái mới nhất).
  Stream<List<Map<String, dynamic>>> getNotificationsStream(String uid) {
    final controller =
        StreamController<List<Map<String, dynamic>>>.broadcast();

    Future<void> fetch() async {
      try {
        final data = await _db
            .from('notifications')
            .select()
            .eq('user_id', uid)
            .order('created_at', ascending: false)
            .limit(50);
        if (!controller.isClosed) {
          controller.add(
              (data as List).map((r) => Map<String, dynamic>.from(r as Map)).toList());
        }
      } catch (_) {
        if (!controller.isClosed) controller.add([]);
      }
    }

    fetch();
    final channel = _db
        .channel('notif_list_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          callback: (_) => fetch(),
        )
        .subscribe();
    controller.onCancel = () => _db.removeChannel(channel);
    return controller.stream;
  }

  /// Đánh dấu một thông báo đã đọc.
  Future<void> markNotificationRead(String id) async {
    await _db.from('notifications').update({
      'is_read': true,
      'read_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// Đánh dấu tất cả thông báo của người dùng đã đọc.
  Future<void> markAllNotificationsRead(String uid) async {
    await _db
        .from('notifications')
        .update({
          'is_read': true,
          'read_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('user_id', uid)
        .eq('is_read', false);
  }

  // ── View counting ─────────────────────────────────────────────────

  /// Tăng lượt xem cho một tin đăng user_listings.
  Future<void> incrementViewCount(String listingId) async {
    try {
      await _db.rpc('increment_view_count', params: {'lid': listingId});
    } catch (_) {
      // Fallback: read current + update
      try {
        final data = await _db
            .from('user_listings')
            .select('view_count')
            .eq('id', listingId)
            .maybeSingle();
        if (data != null) {
          final current = (data['view_count'] as int?) ?? 0;
          await _db
              .from('user_listings')
              .update({'view_count': current + 1})
              .eq('id', listingId);
        }
      } catch (_) {}
    }
  }

  // ── User bookings (member view) ───────────────────────────────────

  /// Lịch sử đặt lịch của người dùng.
  Future<List<Map<String, dynamic>>> getUserBookings(String uid) async {
    try {
      final data = await _db
          .from('user_bookings')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false);
      return (data as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Cập nhật trạng thái tin đăng (approve / reject / pending).
  Future<void> updateListingStatus(String id, String status) async {
    // Notify the listing owner
    try {
      final listing = await _db
          .from('user_listings')
          .select('user_id, title')
          .eq('id', id)
          .maybeSingle();
      if (listing != null) {
        final ownerId = listing['user_id'] as String?;
        final title = listing['title'] as String? ?? 'Tin đăng của bạn';
        if (ownerId != null) {
          final (notifType, notifTitle) = switch (status) {
            'active' => (
                'property_approved',
                '✅ Tin đăng được duyệt',
              ),
            'rejected' => (
                'property_rejected',
                '❌ Tin đăng bị từ chối',
              ),
            _ => ('system_alert', 'Cập nhật tin đăng'),
          };
          await _createNotification(
            userId: ownerId,
            type: notifType,
            title: notifTitle,
            body: title,
          );
        }
      }
    } catch (_) {}
    await _db.from('user_listings').update({'status': status}).eq('id', id);
  }

  /// Xóa tin đăng (admin).
  Future<void> adminDeleteListing(String id) async {
    await _db.from('user_listings').delete().eq('id', id);
  }

  /// Danh sách toàn bộ người dùng (admin view).
  Future<List<Map<String, dynamic>>> getAdminUsers() async {
    final data = await _db
        .from('users')
        .select()
        .order('created_at', ascending: false);
    return (data as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  /// Danh sách toàn bộ booking (admin view).
  Future<List<Map<String, dynamic>>> getAdminBookings() async {
    final data = await _db
        .from('user_bookings')
        .select()
        .order('created_at', ascending: false);
    return (data as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  /// Thống kê doanh thu từ gói thành viên.
  Future<Map<String, dynamic>> getPaymentStats() async {
    final data = await _db
        .from('users')
        .select('membership_tier, membership_expiry_date')
        .not('membership_tier', 'is', null);

    final users = (data as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
    final now = DateTime.now();

    int monthly = 0, quarterly = 0, yearly = 0;
    int activeMonthly = 0, activeQuarterly = 0, activeYearly = 0;
    int expiringSoon = 0; // hết hạn trong 7 ngày

    for (final u in users) {
      final tier = u['membership_tier'] as String?;
      final expiryStr = u['membership_expiry_date'] as String?;
      final expiry = expiryStr != null ? DateTime.tryParse(expiryStr) : null;
      final isActive = expiry != null && expiry.isAfter(now);
      final daysLeft = expiry != null ? expiry.difference(now).inDays : -1;

      if (daysLeft >= 0 && daysLeft <= 7) expiringSoon++;

      switch (tier) {
        case 'monthly':
          monthly++;
          if (isActive) activeMonthly++;
        case 'quarterly':
          quarterly++;
          if (isActive) activeQuarterly++;
        case 'yearly':
          yearly++;
          if (isActive) activeYearly++;
      }
    }

    final totalRevenue =
        monthly * 300000 + quarterly * 700000 + yearly * 2100000;
    final activeRevenue =
        activeMonthly * 300000 + activeQuarterly * 700000 + activeYearly * 2100000;

    return {
      'monthly': monthly,
      'quarterly': quarterly,
      'yearly': yearly,
      'activeMonthly': activeMonthly,
      'activeQuarterly': activeQuarterly,
      'activeYearly': activeYearly,
      'totalMembers': monthly + quarterly + yearly,
      'activeMembers': activeMonthly + activeQuarterly + activeYearly,
      'expiringSoon': expiringSoon,
      'totalRevenue': totalRevenue,
      'activeRevenue': activeRevenue,
    };
  }

  // ── Chat Bot ─────────────────────────────────────────────────────

  /// Lưu một tin nhắn chatbot vào Supabase.
  Future<void> saveChatMessage({
    required String sessionId,
    required String text,
    required bool isUser,
  }) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    await _db.from('chat_bot_messages').insert({
      'session_key': sessionId,
      if (uid != null) 'user_id': uid,
      'text': text,
      'is_user': isUser,
    });
  }

  /// Lấy lịch sử chat của một session.
  Future<List<Map<String, dynamic>>> getChatHistory(
      String sessionId) async {
    final data = await _db
        .from('chat_bot_messages')
        .select()
        .eq('session_key', sessionId)
        .order('created_at', ascending: true);
    return (data as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  /// Stream lịch sử chat theo thời gian thực.
  Stream<List<Map<String, dynamic>>> chatStream(String sessionId) {
    return _db
        .from('chat_bot_messages')
        .stream(primaryKey: ['id'])
        .eq('session_key', sessionId)
        .order('created_at', ascending: true);
  }

  /// Xóa toàn bộ lịch sử chat của một session.
  Future<void> clearChatHistory(String sessionId) async {
    await _db
        .from('chat_bot_messages')
        .delete()
        .eq('session_key', sessionId);
  }
}
