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

    // ── Chào hỏi ──────────────────────────────────────────────────────────
    if (_match(
            text, ['xin chào', 'hello', 'hi ', 'chào', 'hey', 'alo', 'ơi']) &&
        !_match(text, [
          'giá',
          'bao nhiêu',
          'như thế nào',
          'cách',
          'thiết kế',
          'đăng',
          'vr',
          'nhà'
        ])) {
      return 'Xin chào! Tôi là Roomify Bot 🏠\n\n'
          'Tôi có thể giúp bạn:\n'
          '🔍 Tìm BĐS theo giá & khu vực\n'
          '📅 Đặt lịch xem nhà\n'
          '📝 Đăng tin bán/cho thuê\n'
          '🥽 Thiết kế tour VR cho chủ nhà\n'
          '💬 Nhắn tin trực tiếp chủ nhà\n\n'
          'Bạn cần hỗ trợ gì?';
    }

    // ── Giá thiết kế VR ──────────────────────────────────────────────────
    if (_match(text, [
      'giá vr',
      'thiết kế vr',
      'giá thiết kế',
      'dịch vụ vr',
      'matterport',
      'tour 360',
      'thiết kế 360',
      'làm vr',
      'vr giá',
      'bao nhiêu vr',
      'phí vr',
      'gói vr',
      'dịch vụ thiết kế',
      'chi phí vr',
      'vr bao nhiêu',
      'vr 360',
      'tạo vr',
      'làm tour',
      'giá tour',
    ])) {
      return '🥽 Roomify cung cấp 3 gói thiết kế VR:\n\n'
          '📸 Gói 1 — 10.000.000đ\n'
          '   Chụp 360°, tour VR cơ bản, tích hợp tin đăng\n\n'
          '🎯 Gói 2 — 15.000.000đ\n'
          '   Tour tương tác, hotspot từng phòng, kính VR, báo cáo lượt xem\n\n'
          '⭐ Gói 3 — 35.000.000đ\n'
          '   3D photorealistic, nhà ảo tương tác, hỗ trợ kỹ thuật 6 tháng\n\n'
          'Bạn muốn tư vấn chi tiết gói nào?';
    }

    // ── VR tính năng chung ────────────────────────────────────────────────
    if (_match(text,
        ['vr', 'tour ảo', 'thực tế ảo', 'panorama', '360 độ', 'xem 3d'])) {
      return 'Roomify tích hợp 2 loại trải nghiệm ảo 🥽\n\n'
          '• Tour VR 360°: Xem trực tiếp trong ứng dụng\n'
          '• Tour Matterport 3D: Xem chi tiết trong trình duyệt\n\n'
          'Chủ nhà muốn có tour VR riêng? Roomify thiết kế từ 10 triệu đồng.\n'
          'Hỏi "giá thiết kế VR" để xem 3 gói dịch vụ chi tiết!';
    }

    // ── Đăng tin / Gói thành viên ─────────────────────────────────────────
    if (_match(text, [
      'đăng tin',
      'đăng bài',
      'đăng bán',
      'đăng cho thuê',
      'tạo tin',
      'thành viên',
      'membership',
      'vip',
      'gói thành viên',
      'gói đăng',
      'đăng nhà',
      'bán nhà như thế nào',
      'cho thuê nhà như thế nào',
      'đăng ký bán',
    ])) {
      return '📝 Đăng tin bán/cho thuê tại tab "Đăng tin"\n\n'
          'Thông tin cần điền:\n'
          '• Tiêu đề, mô tả, loại BĐS\n'
          '• Vị trí, giá, diện tích, số tầng, số phòng ngủ\n'
          '• SĐT liên hệ, ảnh, link VR 360 (nếu có)\n\n'
          'Gói thành viên:\n'
          '• 1 tháng: 300.000đ\n'
          '• 3 tháng: 700.000đ (tiết kiệm 200.000đ)\n'
          '• 1 năm: 2.100.000đ (tối ưu nhất)\n'
          '• Lẻ từng bài: 50.000đ/bài';
    }

    // ── Đặt lịch ──────────────────────────────────────────────────────────
    if (_match(text, [
      'đặt lịch',
      'hẹn xem',
      'xem nhà',
      'xem phòng',
      'đặt hẹn',
      'cách xem nhà',
      'muốn xem',
      'đến xem',
    ])) {
      return '📅 Quy trình đặt lịch xem nhà:\n\n'
          '1. Vào chi tiết BĐS muốn xem\n'
          '2. Nhấn "Đặt lịch xem nhà" hoặc "Liên hệ tư vấn"\n'
          '3. Điền họ tên, SĐT, thời gian mong muốn\n'
          '4. Roomify kết nối với chủ nhà & xác nhận lịch\n\n'
          '💡 Ngoài ra có thể nhắn tin trực tiếp với chủ nhà qua tab "Tin nhắn"!';
    }

    // ── Nhắn tin chủ nhà ──────────────────────────────────────────────────
    if (_match(text, [
      'nhắn tin',
      'chat với',
      'liên lạc',
      'tin nhắn',
      'kết nối chủ',
      'liên hệ chủ',
      'tìm chủ nhà',
      'nhắn với chủ',
    ])) {
      return '💬 Nhắn tin với chủ nhà qua 2 cách:\n\n'
          '① Tab "Tin nhắn" → tìm theo tên hoặc SĐT\n'
          '② Vào chi tiết BĐS → nhấn "Nhắn tin với chủ nhà"\n\n'
          'Cần đăng nhập để sử dụng tính năng này!';
    }

    // ── Giá mua/thuê BĐS ─────────────────────────────────────────────────
    if (_match(text, [
      'giá nhà',
      'giá mua',
      'giá bán',
      'giá thuê',
      'giá căn hộ',
      'giá chung cư',
      'bao nhiêu tiền',
      'chi phí mua',
      'mua nhà bao nhiêu',
      'thuê nhà bao nhiêu',
      'giá bất động sản',
      'tầm giá',
    ])) {
      return '🏷️ Giá BĐS tham khảo trên Roomify:\n\n'
          'Mua bán:\n'
          '• Căn hộ chung cư: 1–10 tỷ đồng\n'
          '• Nhà phố / Biệt thự: 3–50+ tỷ đồng\n\n'
          'Cho thuê:\n'
          '• Studio/mini: 4–8 triệu/tháng\n'
          '• Căn hộ 1–2 phòng ngủ: 8–20 triệu/tháng\n'
          '• Nhà phố: 15–50 triệu/tháng\n\n'
          'Bạn có ngân sách cụ thể không? Tôi tư vấn thêm!';
    }

    // ── Khu vực ──────────────────────────────────────────────────────────
    if (_match(text, [
      'khu vực',
      'địa điểm',
      'quận',
      'hồ chí minh',
      'hà nội',
      'đà nẵng',
      'tp.hcm',
      'tp hcm',
      'hcm',
      'bình dương',
      'thủ đức',
      'bình thạnh',
      'sài gòn',
      'hoạt động ở đâu',
      'có ở đâu',
    ])) {
      return '📍 Khu vực Roomify đang hoạt động:\n\n'
          'TP. Hồ Chí Minh:\n'
          '  Quận 1, 2, 3, 7, Bình Thạnh, Thủ Đức, Bình Dương\n\n'
          'Hà Nội:\n'
          '  Đống Đa, Ba Đình, Cầu Giấy, Nam Từ Liêm, Tây Hồ\n\n'
          'Đà Nẵng:\n'
          '  Hải Châu, Sơn Trà, Ngũ Hành Sơn\n\n'
          'Bạn muốn tìm BĐS khu vực nào?';
    }

    // ── Loại BĐS ─────────────────────────────────────────────────────────
    if (_match(text, [
      'loại nhà',
      'loại bđs',
      'căn hộ',
      'biệt thự',
      'nhà phố',
      'penthouse',
      'chung cư',
      'đất nền',
      'studio',
      'có loại nào',
      'các loại',
    ])) {
      return '🏢 Các loại BĐS trên Roomify:\n\n'
          '• Căn hộ chung cư (studio, 1PN, 2PN, 3PN)\n'
          '• Căn hộ penthouse\n'
          '• Nhà phố / Nhà liên kế\n'
          '• Biệt thự\n'
          '• Đất nền / Đất dự án\n\n'
          'Bạn đang tìm loại nào?';
    }

    // ── Đăng nhập / Tài khoản ────────────────────────────────────────────
    if (_match(text, [
      'đăng ký',
      'đăng nhập',
      'tài khoản',
      'login',
      'register',
      'tạo tài khoản',
      'quên mật khẩu',
      'tạo account',
    ])) {
      return '👤 Roomify hỗ trợ đăng ký & đăng nhập bằng Email.\n\n'
          'Sau khi đăng nhập:\n'
          '❤️ Lưu BĐS yêu thích\n'
          '📅 Đặt lịch xem nhà\n'
          '💬 Nhắn tin với chủ nhà\n'
          '📝 Đăng tin bán/cho thuê\n\n'
          'Nhấn biểu tượng avatar góc phải màn hình chính để đăng nhập!';
    }

    // ── Lưu yêu thích ────────────────────────────────────────────────────
    if (_match(text, ['lưu', 'yêu thích', 'bookmark', '❤️', 'tim', 'save'])) {
      return '❤️ Nhấn biểu tượng tim trên thẻ BĐS để lưu vào danh sách yêu thích.\n\n'
          'Danh sách yêu thích đồng bộ theo tài khoản, xem lại bất cứ lúc nào trong hồ sơ cá nhân!';
    }

    // ── Cảm ơn / Phản hồi ────────────────────────────────────────────────
    if (_match(text, [
      'cảm ơn',
      'thanks',
      'thank',
      'tuyệt',
      'hay quá',
      'ok',
      'được rồi',
      'hiểu rồi',
      'rõ rồi'
    ])) {
      return 'Vui lòng được hỗ trợ bạn! 😊\nCòn câu hỏi nào về Roomify, cứ hỏi nhé!';
    }
    if (_match(text, ['tạm biệt', 'bye', 'goodbye', 'thôi nhé', 'hẹn gặp'])) {
      return 'Tạm biệt! Chúc bạn tìm được BĐS ưng ý trên Roomify! 🏡';
    }

    // ── Hỗ trợ tổng quát ────────────────────────────────────────────────
    if (_match(text, [
      'hỗ trợ',
      'trợ giúp',
      'help',
      'hướng dẫn',
      'làm sao',
      'như thế nào',
      'có thể giúp'
    ])) {
      return 'Tôi có thể hỗ trợ bạn về 🤖\n\n'
          '🔍 Tìm BĐS theo giá & khu vực\n'
          '📅 Đặt lịch xem nhà\n'
          '💬 Nhắn tin với chủ nhà\n'
          '📝 Đăng tin bán/cho thuê\n'
          '🥽 Dịch vụ thiết kế VR (10–35 triệu)\n'
          '🌟 Gói thành viên chủ nhà\n\n'
          'Bạn cần hỗ trợ mục nào?';
    }

    // ── Mặc định ─────────────────────────────────────────────────────────
    return 'Xin lỗi, tôi chưa hiểu câu hỏi của bạn 😅\n\n'
        'Bạn có thể hỏi về:\n'
        '• "Giá thiết kế VR bao nhiêu?"\n'
        '• "Cách đăng tin bán nhà"\n'
        '• "Giá thuê căn hộ ở Q1"\n'
        '• "Làm sao đặt lịch xem nhà?"\n'
        '• "Khu vực nào có nhà cho thuê?"';
  }

  static bool _match(String text, List<String> keywords) {
    return keywords.any((k) => text.contains(k));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class ChatBotScreen extends StatefulWidget {
  const ChatBotScreen({super.key, this.embedded = false});

  /// Nếu true: ẩn AppBar (dùng trong dialog có title bar riêng).
  final bool embedded;

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
          'Roomify là nền tảng mua bán & cho thuê BĐS tích hợp VR 360°.\n\n'
          'Tôi có thể giúp bạn:\n'
          '🔍 Tìm BĐS theo giá & khu vực\n'
          '📅 Đặt lịch xem nhà với chủ nhà\n'
          '💬 Hướng dẫn nhắn tin với chủ nhà\n'
          '📝 Đăng tin bán/cho thuê (từ 50.000đ)\n'
          '🥽 Thiết kế VR cho chủ nhà (10–35 triệu)\n\n'
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

    // Gọi Gemini API — fallback sang bot quy tắc nếu lỗi bất kỳ.
    String botText;
    try {
      botText = await GeminiService.chat(text);
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
      appBar: widget.embedded
          ? null
          : AppBar(
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
    '🥽 Giá thiết kế VR?',
    '📅 Cách đặt lịch xem nhà?',
    '📝 Cách đăng tin bán?',
    '💬 Nhắn tin với chủ nhà?',
    '📍 Khu vực hoạt động?',
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
