import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';

class CloudinaryService {
  /// Upload an invoice image and return its secure URL
  static Future<String> uploadInvoice(File imageFile) async {
    final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/${AppConfig.cloudinaryCloudName}/image/upload');

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = AppConfig.cloudinaryUploadPreset
      ..fields['folder']        = 'mobilekhata/invoices'
      ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));

    final response = await request.send();
    final body     = jsonDecode(await response.stream.bytesToString());

    if (response.statusCode != 200) {
      throw Exception('Cloudinary upload failed: ${body['error']?['message']}');
    }

    return body['secure_url'] as String;
  }
}
