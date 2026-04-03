import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'firestore_service.dart';

const Color _navy = Color(0xFF0A1931);
const Color _gold = Color(0xFFC8A951);
const Color _cream = Color(0xFFFAF7F2);

// ── Danh sách hội thoại ────────────────────────────────────────────────────

class MemberConversationsScreen extends StatelessWidget {
  const MemberConversationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.instance.currentUser?.uid;

    if (uid == null) {
      return const _NeedLoginPlaceholder();
    }

    return Container(
      color: _cream,
      child: CustomScrollView(
        slivers: [
          const SliverAppBar.medium(
            pinned: true,
            backgroundColor: Colors.transparent,
            title: Text('Tin nhắn'),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
            sliver: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirestoreService.instance.getMyConversationsStream(uid),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final docs = snap.data?.docs ?? [];
                // Sắp xếp theo lastTime giảm dần phía client.
                final sorted = [...docs]..sort((a, b) {
                    final ta =
                        (a.data()['lastTime'] as Timestamp?)?.seconds ?? 0;
                    final tb =
                        (b.data()['lastTime'] as Timestamp?)?.seconds ?? 0;
                    return tb.compareTo(ta);
                  });

                if (sorted.isEmpty) {
                  return const SliverFillRemaining(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.chat_bubble_2,
                                size: 56, color: Colors.black26),
                            SizedBox(height: 12),
                            Text(
                              'Chưa có tin nhắn nào.',
                              style: TextStyle(
                                  fontSize: 16, color: Colors.black54),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Nhấn "Nhắn tin chủ nhà" khi xem\nmột bất động sản để bắt đầu.',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.black38),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                return SliverList.separated(
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 72),
                  itemBuilder: (context, i) {
                    final data = sorted[i].data();
                    final chatId = sorted[i].id;

                    final names = Map<String, String>.from(
                      (data['participantNames'] as Map? ?? {})
                          .map((k, v) => MapEntry(k.toString(), v.toString())),
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

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 4),
                      leading: CircleAvatar(
                        radius: 26,
                        backgroundColor: _navy,
                        child: Text(
                          otherName.isNotEmpty
                              ? otherName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(otherName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, color: _navy)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (propertyTitle != null)
                            Text(
                              'BĐS: $propertyTitle',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.black45),
                            ),
                          Text(
                            lastMsg,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                      trailing: Text(time,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black38)),
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
    );
  }

  static String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return '${diff.inDays}d trước';
    if (diff.inHours > 0) return '${diff.inHours}h trước';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m trước';
    return 'Vừa xong';
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
