import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'firestore_service.dart';

const Color _navy = Color(0xFF0A1931);
const Color _cream = Color(0xFFFAF7F2);

// ── Danh sách hội thoại ────────────────────────────────────────────────────

class MemberConversationsScreen extends StatefulWidget {
  const MemberConversationsScreen({super.key});

  @override
  State<MemberConversationsScreen> createState() =>
      _MemberConversationsScreenState();
}

class _MemberConversationsScreenState extends State<MemberConversationsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  // Phone-lookup state
  bool _searching = false;
  Map<String, dynamic>? _foundUser;
  bool _notFound = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _isPhoneQuery =>
      RegExp(r'^[0-9\s\+\-]{8,15}$').hasMatch(_query.trim());

  Future<void> _lookupPhone(String phone) async {
    setState(() {
      _searching = true;
      _foundUser = null;
      _notFound = false;
    });
    final result = await FirestoreService.instance.findUserByPhone(phone);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _foundUser = result;
      _notFound = result == null;
    });
  }

  void _startChatWithFound(BuildContext context, String currentUid) {
    if (_foundUser == null) return;
    final otherUid = _foundUser!['uid'] as String;
    final otherName =
        (_foundUser!['name'] as String?)?.trim().isNotEmpty == true
            ? _foundUser!['name'] as String
            : (_foundUser!['email'] as String? ?? 'Người dùng');
    if (otherUid == currentUid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đây là tài khoản của bạn.')),
      );
      return;
    }
    final currentName = AuthService.instance.currentUser?.displayName ??
        AuthService.instance.currentUser?.email ??
        'Thành viên';
    FirestoreService.instance
        .initMemberChat(
      uid1: currentUid,
      name1: currentName,
      uid2: otherUid,
      name2: otherName,
    )
        .then((chatId) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MemberChatScreen(
            chatId: chatId,
            otherUserId: otherUid,
            otherUserName: otherName,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges,
      builder: (context, snapshot) {
        // Đang chờ Firebase restore session
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final uid = snapshot.data?.uid;
        if (uid == null) {
          return const Scaffold(body: _NeedLoginPlaceholder());
        }
        return _buildBody(context, uid);
      },
    );
  }

  Widget _buildBody(BuildContext context, String uid) {
    return Scaffold(
      backgroundColor: _cream,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tin nhắn',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // ── Search bar ───────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (v) {
                            setState(() {
                              _query = v;
                              _foundUser = null;
                              _notFound = false;
                            });
                          },
                          onSubmitted: (v) {
                            if (_isPhoneQuery) _lookupPhone(v);
                          },
                          keyboardType: TextInputType.text,
                          decoration: InputDecoration(
                            hintText:
                                'Tìm hội thoại hoặc nhập số điện thoại chủ nhà',
                            hintStyle: const TextStyle(
                                fontSize: 13, color: Colors.black38),
                            prefixIcon: const Icon(CupertinoIcons.search,
                                size: 18, color: Colors.black38),
                            suffixIcon: _query.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(
                                        CupertinoIcons.xmark_circle_fill,
                                        size: 18,
                                        color: Colors.black38),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() {
                                        _query = '';
                                        _foundUser = null;
                                        _notFound = false;
                                      });
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: const Color(0xFFF2F4F7),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 0, horizontal: 16),
                          ),
                        ),
                      ),
                      if (_isPhoneQuery) ...[
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed:
                              _searching ? null : () => _lookupPhone(_query),
                          style: FilledButton.styleFrom(
                            backgroundColor: _navy,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                          ),
                          child: _searching
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Tìm',
                                  style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    ],
                  ),
                  // ── Phone lookup result ───────────────────────
                  if (_foundUser != null) ...[
                    const SizedBox(height: 10),
                    _PhoneResultCard(
                      user: _foundUser!,
                      onStartChat: () => _startChatWithFound(context, uid),
                    ),
                  ] else if (_notFound) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(CupertinoIcons.info_circle,
                              size: 18, color: Colors.orange),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Không tìm thấy người dùng với SĐT này. Thử liên hệ qua trang bất động sản.',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.black54),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // ── Conversation list ──────────────────────────────
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirestoreService.instance.getMyConversationsStream(uid),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snap.data?.docs ?? [];
                  final sorted = [...docs]..sort((a, b) {
                      final ta =
                          (a.data()['lastTime'] as Timestamp?)?.seconds ?? 0;
                      final tb =
                          (b.data()['lastTime'] as Timestamp?)?.seconds ?? 0;
                      return tb.compareTo(ta);
                    });

                  // Filter by search query (non-phone)
                  final filtered = _query.isNotEmpty && !_isPhoneQuery
                      ? sorted.where((doc) {
                          final data = doc.data();
                          final names =
                              (data['participantNames'] as Map? ?? {});
                          final other = names.entries
                              .where((e) => e.key.toString() != uid)
                              .map((e) => e.value.toString().toLowerCase())
                              .join(' ');
                          final propTitle =
                              (data['propertyTitle'] as String? ?? '')
                                  .toLowerCase();
                          return other.contains(_query.toLowerCase()) ||
                              propTitle.contains(_query.toLowerCase());
                        }).toList()
                      : sorted;

                  if (filtered.isEmpty) {
                    return _EmptyState(
                      hasQuery: _query.isNotEmpty,
                      isPhoneQuery: _isPhoneQuery,
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 68),
                    itemBuilder: (context, i) {
                      final data = filtered[i].data();
                      final chatId = filtered[i].id;

                      final names = Map<String, String>.from(
                        (data['participantNames'] as Map? ?? {}).map(
                          (k, v) => MapEntry(k.toString(), v.toString()),
                        ),
                      );
                      final otherEntry = names.entries.firstWhere(
                        (e) => e.key != uid,
                        orElse: () => const MapEntry('', 'Người dùng'),
                      );
                      final otherUid = otherEntry.key;
                      final otherName = otherEntry.value;
                      final lastMsg = data['lastMessage'] as String? ?? '';
                      final propertyTitle = data['propertyTitle'] as String?;
                      final ts = data['lastTime'] as Timestamp?;
                      final time = ts != null ? _formatTime(ts.toDate()) : '';

                      return _ConversationTile(
                        otherName: otherName,
                        lastMsg: lastMsg,
                        propertyTitle: propertyTitle,
                        time: time,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MemberChatScreen(
                              chatId: chatId,
                              otherUserId: otherUid,
                              otherUserName: otherName,
                              propertyTitle: propertyTitle,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m';
    return 'Vừa';
  }
}

// ── Helper widgets ─────────────────────────────────────────────────────────

class _PhoneResultCard extends StatelessWidget {
  const _PhoneResultCard({required this.user, required this.onStartChat});
  final Map<String, dynamic> user;
  final VoidCallback onStartChat;

  @override
  Widget build(BuildContext context) {
    final name = (user['name'] as String?)?.trim().isNotEmpty == true
        ? user['name'] as String
        : (user['email'] as String? ?? 'Người dùng');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _navy.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _navy.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: _navy,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, color: _navy)),
                Text(
                  user['phone'] as String? ?? '',
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: onStartChat,
            style: FilledButton.styleFrom(
              backgroundColor: _navy,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: const Text('Nhắn tin', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.otherName,
    required this.lastMsg,
    required this.time,
    required this.onTap,
    this.propertyTitle,
  });

  final String otherName;
  final String lastMsg;
  final String? propertyTitle;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: _navy,
              child: Text(
                otherName.isNotEmpty ? otherName[0].toUpperCase() : '?',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(otherName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _navy,
                          fontSize: 15)),
                  if (propertyTitle != null)
                    Text(
                      'BĐS: $propertyTitle',
                      style:
                          const TextStyle(fontSize: 11, color: Colors.black38),
                    ),
                  Text(
                    lastMsg,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(time,
                style: const TextStyle(fontSize: 11, color: Colors.black38)),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasQuery, required this.isPhoneQuery});
  final bool hasQuery;
  final bool isPhoneQuery;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _navy.withValues(alpha: 0.07),
                shape: BoxShape.circle,
              ),
              child: const Icon(CupertinoIcons.chat_bubble_2,
                  size: 34, color: Colors.black26),
            ),
            const SizedBox(height: 16),
            Text(
              hasQuery
                  ? (isPhoneQuery
                      ? 'Nhấn "Tìm" để tra cứu người dùng'
                      : 'Không tìm thấy hội thoại phù hợp')
                  : 'Chưa có tin nhắn nào',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              hasQuery
                  ? (isPhoneQuery
                      ? 'Nhập đúng số điện thoại để kết nối với chủ nhà hoặc đại lý'
                      : 'Thử tìm kiếm với từ khoá khác')
                  : 'Nhập số điện thoại chủ nhà để bắt đầu kết nối,\nhoặc nhắn tin từ trang bất động sản.',
              style: const TextStyle(fontSize: 13, color: Colors.black38),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Màn hình chat ─────────────────────────────────────────────────────────

class MemberChatScreen extends StatefulWidget {
  const MemberChatScreen({
    super.key,
    required this.chatId,
    required this.otherUserId,
    required this.otherUserName,
    this.propertyTitle,
  });

  final String chatId;
  final String otherUserId;
  final String otherUserName;
  final String? propertyTitle;

  @override
  State<MemberChatScreen> createState() => _MemberChatScreenState();
}

class _MemberChatScreenState extends State<MemberChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();

    final user = AuthService.instance.currentUser;
    if (user == null) return;

    await FirestoreService.instance.sendMemberMessage(
      chatId: widget.chatId,
      senderId: user.uid,
      senderName: user.displayName ?? user.email ?? 'Thành viên',
      text: text,
      propertyTitle: widget.propertyTitle,
    );

    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.otherUserName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if (widget.propertyTitle != null)
              Text(
                widget.propertyTitle!,
                style: const TextStyle(fontSize: 12, color: Colors.white60),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirestoreService.instance
                  .getMemberMessagesStream(widget.chatId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'Hãy bắt đầu cuộc trò chuyện!',
                      style: TextStyle(color: Colors.black45),
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scroll,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final data = docs[i].data();
                    return _Bubble(
                      text: data['text'] as String? ?? '',
                      isMe: data['senderId'] == uid,
                      senderName: data['senderName'] as String? ?? '',
                    );
                  },
                );
              },
            ),
          ),
          _ChatInputBar(controller: _controller, onSend: _send),
        ],
      ),
    );
  }
}

// ── Bong bóng tin nhắn ────────────────────────────────────────────────────

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.text,
    required this.isMe,
    required this.senderName,
  });

  final String text;
  final bool isMe;
  final String senderName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe)
            CircleAvatar(
              radius: 15,
              backgroundColor: _navy,
              child: Text(
                senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          if (!isMe) const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? _navy : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: isMe ? Colors.white : _navy,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Thanh nhập liệu ───────────────────────────────────────────────────────

class _ChatInputBar extends StatelessWidget {
  const _ChatInputBar({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, 8 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.black.withOpacity(0.08))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: 'Nhập tin nhắn...',
                filled: true,
                fillColor: const Color(0xFFF4F4F4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onSend,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: _navy,
                shape: BoxShape.circle,
              ),
              child: const Icon(CupertinoIcons.arrow_up,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Placeholder chưa đăng nhập ────────────────────────────────────────────

class _NeedLoginPlaceholder extends StatelessWidget {
  const _NeedLoginPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.lock_circle, size: 64, color: Colors.black26),
            SizedBox(height: 16),
            Text(
              'Đăng nhập để xem tin nhắn',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0A1931),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Bạn cần đăng nhập để nhắn tin\nvới chủ nhà.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Widget khởi tạo chat (dùng từ PropertyDetailPage) ────────────────────

/// Nút nhắn tin chủ nhà — tự khởi tạo chatId rồi mở MemberChatScreen.
class StartChatButton extends StatefulWidget {
  const StartChatButton({
    super.key,
    required this.ownerId,
    required this.ownerName,
    required this.propertyTitle,
    required this.currentUserId,
    required this.currentUserName,
  });

  final String ownerId;
  final String ownerName;
  final String propertyTitle;
  final String currentUserId;
  final String currentUserName;

  @override
  State<StartChatButton> createState() => _StartChatButtonState();
}

class _StartChatButtonState extends State<StartChatButton> {
  bool _loading = false;

  Future<void> _openChat() async {
    setState(() => _loading = true);
    try {
      final chatId = await FirestoreService.instance.initMemberChat(
        uid1: widget.currentUserId,
        name1: widget.currentUserName,
        uid2: widget.ownerId,
        name2: widget.ownerName,
        propertyTitle: widget.propertyTitle,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MemberChatScreen(
            chatId: chatId,
            otherUserId: widget.ownerId,
            otherUserName: widget.ownerName,
            propertyTitle: widget.propertyTitle,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton.icon(
        onPressed: _loading ? null : _openChat,
        icon: _loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(CupertinoIcons.chat_bubble_text_fill),
        label: const Text('Nhắn tin chủ nhà'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF0A1931),
          side: const BorderSide(color: Color(0xFF0A1931)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}
