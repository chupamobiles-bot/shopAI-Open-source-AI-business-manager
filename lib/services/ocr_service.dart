import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrService {
  static final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Extract all text from an image file using ML Kit (on-device, FREE)
  static Future<String> extractText(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final result     = await _recognizer.processImage(inputImage);
    return result.text;
  }

  /// Pull all 15-digit IMEI numbers from raw text using regex
  /// Handles OCR inserting spaces between digits
  static List<String> extractImeis(String text) {
    // First try exact 15-digit match
    final exact = RegExp(r'\b\d{15}\b');
    final results = exact.allMatches(text).map((m) => m.group(0)!).toList();
    if (results.isNotEmpty) return results;

    // Fallback: digits possibly separated by spaces (OCR splits long numbers)
    // Match sequences like "860946 079401 815" → collapse to "860946079401815"
    final spaced = RegExp(r'\b(\d[\d ]{13,19}\d)\b');
    for (final m in spaced.allMatches(text)) {
      final digits = m.group(0)!.replaceAll(' ', '');
      if (digits.length == 15) results.add(digits);
    }
    return results;
  }

  /// Remove non-digits; return null if result isn't exactly 15 digits
  static String? cleanImei(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    return digits.length == 15 ? digits : null;
  }

  static void dispose() => _recognizer.close();
}
