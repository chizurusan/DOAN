import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

const _imgbbApiKey = 'e0af3b8af7be0756811793d85a8557e5';

class ImageUploadService {
  ImageUploadService._();

  static final _picker = ImagePicker();

  /// Mở picker để chọn ảnh từ thư viện.
  static Future<XFile?> pickImage() async {
    return _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
  }

  /// Upload [file] lên ImgBB và trả về URL ảnh.
  static Future<String> uploadPropertyImage(
    XFile file,
    String userId, {
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.1);

    final bytes =
        kIsWeb ? await file.readAsBytes() : await File(file.path).readAsBytes();
    final base64Image = base64Encode(bytes);

    onProgress?.call(0.4);

    final uri = Uri.parse(
      'https://api.imgbb.com/1/upload?key=$_imgbbApiKey',
    );

    final response = await http.post(
      uri,
      body: {'image': base64Image},
    ).timeout(const Duration(seconds: 30));

    onProgress?.call(0.9);

    if (response.statusCode != 200) {
      throw Exception(
          'Tải ảnh thất bại (${response.statusCode}): ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final url = json['data']?['url'] as String?;
    if (url == null) throw Exception('Không lấy được URL ảnh.');

    onProgress?.call(1.0);
    return url;
  }
}
