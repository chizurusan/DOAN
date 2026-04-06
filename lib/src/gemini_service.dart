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
      'Bạn là Roomify Bot — trợ lý AI của nền tảng bất động sản Roomify (Việt Nam).\n\n'
      '=== QUY TẮC QUAN TRỌNG ===\n'
      '1. Trả lời TRỰC TIẾP vào câu hỏi. KHÔNG bao giờ bắt đầu bằng "Xin chào", "Tôi là Roomify Bot", hay liệt kê lại danh sách dịch vụ khi người dùng đã hỏi câu hỏi cụ thể.\n'
      '2. Chỉ chào lại khi người dùng chào trước (hi, hello, chào, xin chào).\n'
      '3. Trả lời bằng tiếng Việt, ngắn gọn, rõ ràng, tối đa 200 từ.\n'
      '4. Dùng số liệu cụ thể từ dữ liệu bên dưới. Không bịa thông tin.\n'
      '5. Nếu câu hỏi hoàn toàn ngoài phạm vi BĐS/Roomify, từ chối lịch sự.\n\n'
      '=== DỮ LIỆU DỊCH VỤ ROOMIFY ===\n\n'
      'A. DỊCH VỤ THIẾT KẾ VR 360° — 3 GÓI:\n'
      '• Gói 1 "Thiết kế 360+VR" — 10.000.000đ:\n'
      '  Chụp ảnh 360° toàn không gian, tour VR cơ bản xem qua trình duyệt, tích hợp vào tin đăng Roomify.\n'
      '• Gói 2 "Thiết kế VR" — 15.000.000đ:\n'
      '  Tour VR tương tác đầy đủ, hotspot từng phòng, tương thích kính VR & điện thoại, báo cáo lượt xem hàng tháng.\n'
      '• Gói 3 "VR cao cấp" — 35.000.000đ:\n'
      '  3D nội thất photorealistic, tour nhiều tầng, nhà ảo tương tác chọn nội thất, hỗ trợ kỹ thuật 6 tháng.\n\n'
      'B. GÓI ĐĂNG TIN CHỦ NHÀ:\n'
      '• 1 tháng: 300.000đ\n'
      '• 3 tháng: 700.000đ (tiết kiệm 200.000đ)\n'
      '• 1 năm: 2.100.000đ (tiết kiệm nhất)\n'
      '• Lẻ từng bài: 50.000đ/bài\n'
      '• Cách đăng: vào tab "Đăng tin", điền tiêu đề/mô tả/loại BĐS/vị trí/giá/phòng ngủ/diện tích/tầng/SĐT/ảnh/link VR.\n\n'
      'C. ĐẶT LỊCH XEM NHÀ:\n'
      'Vào chi tiết BĐS → nhấn "Đặt lịch xem nhà" hoặc "Liên hệ tư vấn" → điền họ tên, SĐT, thời gian mong muốn → Roomify kết nối với chủ nhà.\n\n'
      'D. NHẮN TIN VỚI CHỦ NHÀ:\n'
      'Tab "Tin nhắn" → tìm theo tên hoặc SĐT. Hoặc từ chi tiết BĐS → "Nhắn tin với chủ nhà". Cần đăng nhập.\n\n'
      'E. GIÁ BĐS THAM KHẢO:\n'
      '• Bán: Căn hộ 1–10 tỷ, Nhà phố/Biệt thự 3–50+ tỷ.\n'
      '• Thuê: Studio/mini 4–8 triệu/tháng, 1–2 phòng ngủ 8–20 triệu/tháng, Nhà phố 15–50 triệu/tháng.\n\n'
      'F. KHU VỰC HOẠT ĐỘNG:\n'
      '• TP.HCM: Quận 1, 2, 3, 7, Bình Thạnh, Thủ Đức, Bình Dương.\n'
      '• Hà Nội: Đống Đa, Ba Đình, Cầu Giấy, Nam Từ Liêm, Tây Hồ.\n'
      '• Đà Nẵng: Hải Châu, Sơn Trà, Ngũ Hành Sơn.\n\n'
      'G. TOUR VR MATTERPORT: Demo 3D xem trong trình duyệt.\n'
      'H. ĐĂNG NHẬP: Bằng Email. Cần đăng nhập để lưu yêu thích, đặt lịch, nhắn tin, đăng tin.\n\n'
      '=== VÍ DỤ TRẢ LỜI ĐÚNG ===\n'
      'Hỏi: "Giá thiết kế VR bao nhiêu?" → Trả lời ngay về 3 gói và giá cụ thể.\n'
      'Hỏi: "Cách đăng tin bán nhà?" → Trả lời ngay về quy trình đăng tin và gói thành viên.\n'
      'Hỏi: "Khu vực nào có nhà cho thuê?" → Trả lời ngay về các khu vực và giá thuê tham khảo.';

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
        'temperature': 0.3,
        'maxOutputTokens': 800,
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
