import 'dart:convert';

import 'package:http/http.dart' as http;

/// ===========================================================================
/// HƯỚNG DẪN LẤY GEMINI API KEY:
///
/// 1. Truy cập https://aistudio.google.com/app/apikey
/// 2. Đăng nhập tài khoản Google
/// 3. Nhấn "Create API key" → chọn project Firebase của bạn
/// 4. Copy API key → dán vào _apiKey bên dưới
/// ===========================================================================
class GeminiService {
  GeminiService._();

  static const String _apiKey = 'AIzaSyAkDO0LmY7hjofZ-DKHKOVqK9hl0zJ1WUc';

  static const String _model = 'gemini-2.0-flash';

  static const String _systemPrompt =
      'Bạn là Roomify Bot, trợ lý AI chuyên tư vấn bất động sản mua bán tại Việt Nam. '
      'Roomify là nền tảng trung gian kết nối người mua và người bán bất động sản. '
      'Nhiệm vụ của bạn là giúp người dùng tìm kiếm bất động sản phù hợp, '
      'tư vấn giá mua bán, khu vực, pháp lý, hướng dẫn đăng tin bán và giải đáp câu hỏi về dịch vụ Roomify. '
      'Trả lời ngắn gọn, thân thiện bằng tiếng Việt. '
      'Nếu câu hỏi nằm ngoài phạm vi bất động sản mua bán, '
      'hãy lịch sự từ chối và gợi ý câu hỏi liên quan đến mua bán nhà đất.';

  /// Lịch sử hội thoại — giữ ngữ cảnh cho nhiều lượt chat.
  static final List<Map<String, dynamic>> _history = [];

  /// Gửi tin nhắn và nhận phản hồi từ Gemini.
  ///
  /// Ném [GeminiException] nếu gặp lỗi API.
  static Future<String> chat(String userMessage) async {
    if (_apiKey == 'PASTE_YOUR_GEMINI_API_KEY_HERE') {
      throw GeminiException(
        'Chưa cấu hình API key. Mở lib/src/gemini_service.dart và điền _apiKey.',
      );
    }

    // Thêm tin nhắn người dùng vào lịch sử.
    _history.add({
      'role': 'user',
      'parts': [
        {'text': userMessage},
      ],
    });

    // Giới hạn lịch sử tối đa 20 lượt để tránh vượt token.
    if (_history.length > 20) {
      _history.removeRange(0, _history.length - 20);
    }

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$_apiKey',
    );

    final body = jsonEncode({
      'system_instruction': {
        'parts': [
          {'text': _systemPrompt},
        ],
      },
      'contents': _history,
      'generationConfig': {
        'temperature': 0.7,
        'maxOutputTokens': 512,
      },
    });

    final response = await http
        .post(url, headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      // Xóa tin nhắn vừa thêm vì request thất bại.
      _history.removeLast();
      final error = jsonDecode(response.body);
      throw GeminiException(
        error['error']?['message'] ?? 'Lỗi ${response.statusCode}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final botText =
        data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String? ??
            'Xin lỗi, tôi không thể trả lời lúc này.';

    // Thêm phản hồi bot vào lịch sử.
    _history.add({
      'role': 'model',
      'parts': [
        {'text': botText},
      ],
    });

    return botText;
  }

  /// Xóa toàn bộ lịch sử hội thoại (gọi khi user xóa chat).
  static void clearHistory() => _history.clear();
}

class GeminiException implements Exception {
  const GeminiException(this.message);
  final String message;

  @override
  String toString() => 'GeminiException: $message';
}
