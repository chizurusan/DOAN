import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import 'auth_service.dart';
import 'firestore_service.dart';
import 'gemini_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MODEL
// ─────────────────────────────────────────────────────────────────────────────

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
  });

  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChatMessage(
      id: doc.id,
      text: data['text'] as String? ?? '',
      isUser: data['isUser'] as bool? ?? false,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOT ENGINE — thay thế hàm này bằng API call (Gemini / OpenAI) để có AI thật
// ─────────────────────────────────────────────────────────────────────────────

class _BotEngine {
  static String reply(String userText) {
    final text = userText.toLowerCase().trim();

    if (_match(text, ['xin chào', 'hello', 'hi', 'chào', 'hey'])) {
      return 'Xin chào! Tôi là Roomify Bot 🏠 Tôi có thể giúp bạn tìm phòng, '
          'giải đáp thắc mắc về giá thuê, khu vực, hoặc các tiện ích nhà trọ. '
          'Bạn cần hỗ trợ gì?';
    }
    if (_match(text, ['giá', 'bao nhiêu tiền', 'chi phí', 'giá thuê'])) {
      return 'Giá thuê tại Roomify dao động từ 2–15 triệu/tháng tùy khu vực '
          'và diện tích 🏷️\n\n'
          '• Phòng trọ đơn: 2–4 triệu/tháng\n'
          '• Căn hộ mini: 4–8 triệu/tháng\n'
          '• Căn hộ 1PN: 7–15 triệu/tháng\n\n'
          'Bạn có ngân sách cụ thể không? Tôi sẽ lọc phòng phù hợp cho bạn!';
    }
    if (_match(text, [
      'khu vực',
      'địa điểm',
      'quận',
      'thành phố',
      'hồ chí minh',
      'hà nội',
      'đà nẵng',
    ])) {
      return 'Roomify hiện có tin đăng tại nhiều khu vực 📍\n\n'
          '• TP. Hồ Chí Minh: Q1, Q3, Q7, Bình Thạnh, Thủ Đức…\n'
          '• Hà Nội: Đống Đa, Ba Đình, Cầu Giấy…\n'
          '• Đà Nẵng: Hải Châu, Sơn Trà…\n\n'
          'Bạn muốn tìm phòng ở khu vực nào?';
    }
    if (_match(text, ['tiện ích', 'wifi', 'điều hòa', 'nội thất', 'gồm gì'])) {
      return 'Các phòng được đăng trên Roomify thường có thông tin tiện ích '
          'đầy đủ 📋\n\n'
          '• WiFi tốc độ cao\n'
          '• Điều hòa / Máy lạnh\n'
          '• Nội thất cơ bản hoặc đầy đủ\n'
          '• Bãi đỗ xe, chỗ để đồ\n\n'
          'Bạn muốn lọc phòng theo tiện ích cụ thể nào?';
    }
    if (_match(text, ['đặt phòng', 'đặt lịch', 'xem phòng', 'liên hệ chủ'])) {
      return 'Để đặt lịch xem phòng, bạn chọn tab **Liên hệ** ở menu dưới 📅\n\n'
          'Hoặc vào chi tiết bất động sản → nhấn nút **Đặt lịch xem** — '
          'chúng tôi sẽ kết nối bạn với chủ nhà ngay!';
    }
    if (_match(text, ['đăng tin', 'đăng bài', 'cho thuê', 'post'])) {
      return 'Để đăng tin cho thuê phòng, bạn vào tab **Đăng tin** 📝\n\n'
          'Gói đăng tin:\n'
          '• Gói tháng: 300.000đ\n'
          '• Gói 3 tháng: 700.000đ\n'
          '• Gói 1 năm: 2.100.000đ\n\n'
          'Cần hỗ trợ thêm về quy trình đăng tin không?';
    }
    if (_match(text, ['vr', 'tour', '3d', 'xem thực tế', 'panorama'])) {
      return 'Roomify hỗ trợ tour VR 360° để bạn xem phòng mà không cần đến '
          'trực tiếp 🥽\n\n'
          'Nhấn nút **Xem VR** (màu vàng ở dưới) để trải nghiệm căn phòng '
          'theo dạng toàn cảnh 360 độ!';
    }
    if (_match(text, ['thành viên', 'membership', 'vip', 'gói'])) {
      return 'Gói thành viên Roomify cho phép bạn đăng tin không giới hạn 🌟\n\n'
          '• Gói tháng: 300.000đ/tháng\n'
          '• Gói 3 tháng: 700.000đ — tiết kiệm hơn\n'
          '• Gói 1 năm: 2.100.000đ — tối ưu nhất\n\n'
          'Đăng ký tại tab **Đăng tin** trong ứng dụng nhé!';
    }
    if (_match(text, ['cảm ơn', 'thanks', 'thank', 'ok', 'được rồi'])) {
      return 'Rất vui được hỗ trợ bạn! 😊 Nếu còn câu hỏi nào về phòng trọ '
          'hay dịch vụ Roomify, đừng ngần ngại hỏi tôi nhé!';
    }
    if (_match(text, ['tạm biệt', 'bye', 'goodbye'])) {
      return 'Tạm biệt! Chúc bạn tìm được căn phòng ưng ý! 🏡 '
          'Hẹn gặp lại trên Roomify!';
    }
    if (_match(text, ['hỗ trợ', 'trợ giúp', 'help', 'hướng dẫn'])) {
      return 'Tôi có thể giúp bạn về:\n\n'
          '🔍 Tìm phòng theo giá & khu vực\n'
          '📅 Đặt lịch xem phòng\n'
          '📝 Hướng dẫn đăng tin\n'
          '🥽 Tour VR 360°\n'
          '🌟 Gói thành viên\n\n'
          'Bạn cần hỗ trợ mục nào?';
    }

    // Mặc định
    final defaults = [
      'Tôi hiểu bạn đang hỏi về "$userText" 🤔 Hiện tôi chỉ hỗ trợ '
          'các câu hỏi về mua bán bất động sản và dịch vụ Roomify. '
          'Bạn có thể hỏi cụ thể hơn không?',
      'Cảm ơn bạn đã liên hệ Roomify Bot! 🏠 Tôi chuyên tư vấn về '
          'mua bán bất động sản. Bạn muốn biết gì không?\n\n'
          'Gợi ý: hỏi về giá, khu vực, pháp lý, hoặc cách đăng tin bán.',
    ];
    return defaults[Random().nextInt(defaults.length)];
  }

  static bool _match(String text, List<String> keywords) {
    return keywords.any((k) => text.contains(k));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class ChatBotScreen extends StatefulWidget {
  const ChatBotScreen({super.key});

  @override
  State<ChatBotScreen> createState() => _ChatBotScreenState();
}

class _ChatBotScreenState extends State<ChatBotScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _localMessages = [];
  bool _isBotTyping = false;
  bool _firestoreReady = false;

  String get _sessionId {
    final uid = AuthService.instance.currentUser?.uid;
    return uid ?? 'guest_${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  void initState() {
    super.initState();
    _checkFirestore();
    _addWelcomeMessage();
  }

  void _checkFirestore() {
    setState(() {
      _firestoreReady = FirestoreService.instance.isReady;
    });
  }

  void _addWelcomeMessage() {
    _localMessages.add(ChatMessage(
      id: 'welcome',
      text: 'Xin chào! Tôi là Roomify Bot 🏠\n'
          'Roomify là nền tảng trung gian mua bán bất động sản tại Việt Nam.\n\n'
          'Tôi có thể giúip bạn:\n'
          '🔍 Tìm bất động sản theo giá & khu vực\n'
          '📜 Tư vấn pháp lý mua bán\n'
          '📝 Hướng dẫn đăng tin bán\n'
          '🥽 Xem VR 360° trước khi quyết định\n\n'
          'Bạn cần hỗ trợ gì hôm nay?',
      isUser: false,
      timestamp: DateTime.now(),
    ));
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();

    final userMsg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _localMessages.add(userMsg);
      _isBotTyping = true;
    });

    _scrollToBottom();

    // Lưu tin nhắn của người dùng lên Firestore (nếu đã kết nối).
    await FirestoreService.instance.saveChatMessage(
      sessionId: _sessionId,
      text: text,
      isUser: true,
    );

    // Gọi Gemini API — fallback sang bot quy tắc nếu chưa cấu hình key.
    String botText;
    try {
      botText = await GeminiService.chat(text);
    } on GeminiException catch (e) {
      // Chưa điền API key → dùng bot quy tắc offline.
      botText = _BotEngine.reply(text);
      // Hiện thị lỗi nhỏ nếu đã điền key nhưng bị lỗi API.
      if (!e.message.contains('Chưa cấu hình')) {
        botText =
            '⚠️ Lỗi kết nối AI: ${e.message}\n\n${_BotEngine.reply(text)}';
      }
    } catch (_) {
      botText = _BotEngine.reply(text);
    }

    final botMsg = ChatMessage(
      id: '${DateTime.now().millisecondsSinceEpoch}_bot',
      text: botText,
      isUser: false,
      timestamp: DateTime.now(),
    );

    // Lưu phản hồi bot lên Firestore.
    await FirestoreService.instance.saveChatMessage(
      sessionId: _sessionId,
      text: botText,
      isUser: false,
    );

    if (!mounted) return;
    setState(() {
      _localMessages.add(botMsg);
      _isBotTyping = false;
    });

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xóa lịch sử chat'),
        content: const Text('Bạn có chắc muốn xóa toàn bộ tin nhắn không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await FirestoreService.instance.clearChatHistory(_sessionId);
    GeminiService.clearHistory();

    setState(() {
      _localMessages.clear();
      _addWelcomeMessage();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: roomifyCream,
      appBar: AppBar(
        backgroundColor: roomifyNavy,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: roomifyGold,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                CupertinoIcons.sparkles,
                color: roomifyNavy,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Roomify Bot',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: const BoxDecoration(
                        color: Color(0xFF4ADE80),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Text(
                      _firestoreReady
                          ? 'Online · Kết nối Firebase'
                          : 'Demo mode',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.trash, size: 20),
            tooltip: 'Xóa lịch sử',
            onPressed: _clearHistory,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Banner khi chưa đăng nhập
          if (AuthService.instance.currentUser == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: roomifyGold.withValues(alpha: 0.15),
              child: Row(
                children: [
                  const Icon(CupertinoIcons.info_circle,
                      size: 16, color: roomifyNavy),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Đăng nhập để lưu lịch sử chat của bạn.',
                      style: TextStyle(fontSize: 12, color: roomifyNavy),
                    ),
                  ),
                ],
              ),
            ),

          // Danh sách tin nhắn
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _localMessages.length + (_isBotTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (_isBotTyping && index == _localMessages.length) {
                  return _TypingIndicator();
                }
                return _MessageBubble(message: _localMessages[index]);
              },
            ),
          ),

          // Quick reply chips
          if (_localMessages.length <= 1)
            _QuickReplies(onTap: (text) {
              _controller.text = text;
              _sendMessage();
            }),

          // Input bar
          _InputBar(
            controller: _controller,
            onSend: _sendMessage,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) _BotAvatar(),
          if (!isUser) const SizedBox(width: 8),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? roomifyNavy : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: isUser
                      ? const Radius.circular(18)
                      : const Radius.circular(4),
                  bottomRight: isUser
                      ? const Radius.circular(4)
                      : const Radius.circular(18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.5,
                  color: isUser ? Colors.white : roomifyText,
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
          if (isUser)
            CircleAvatar(
              radius: 14,
              backgroundColor: roomifyGold.withValues(alpha: 0.2),
              child: const Icon(
                CupertinoIcons.person_fill,
                size: 16,
                color: roomifyNavy,
              ),
            ),
        ],
      ),
    );
  }
}

class _BotAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: roomifyGold,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(CupertinoIcons.sparkles, size: 16, color: roomifyNavy),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          _BotAvatar(),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _DotsAnimation(),
          ),
        ],
      ),
    );
  }
}

class _DotsAnimation extends StatefulWidget {
  @override
  State<_DotsAnimation> createState() => _DotsAnimationState();
}

class _DotsAnimationState extends State<_DotsAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: 0, end: 1).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.33;
            final phase = (_animation.value - delay).clamp(0.0, 1.0);
            final opacity = (sin(phase * pi) * 0.7 + 0.3).clamp(0.3, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: roomifyMuted,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _QuickReplies extends StatelessWidget {
  const _QuickReplies({required this.onTap});

  final void Function(String) onTap;

  static const _chips = [
    '💰 Giá mua nhà bao nhiêu?',
    '📍 Khu vực nào?',
    '🏢 Loại bất động sản',
    '📜 Tư vấn pháp lý',
    '📝 Cách đăng tin bán',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: roomifyCream,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _chips
              .map(
                (chip) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(
                      chip,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: roomifyNavy,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: roomifyNavy, width: 1),
                    onPressed: () => onTap(chip),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(
        left: 16,
        right: 8,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Nhập tin nhắn…',
                hintStyle: const TextStyle(color: roomifyMuted, fontSize: 14),
                filled: true,
                fillColor: roomifyCream,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onSend,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: roomifyNavy,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.arrow_up,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
