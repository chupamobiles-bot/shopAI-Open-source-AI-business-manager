import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

class ApiService {
  static Future<String> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token') ?? '';
  }

  static Map<String, String> get _jsonHeaders => {
    'Content-Type': 'application/json',
  };

  static Future<Map<String, String>> _authHeaders() async => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${await _token()}',
  };

  // ── GET ──────────────────────────────────────────────────────
  static Future<dynamic> get(String path,
      {Map<String, String>? params, bool auth = true}) async {
    var uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    if (params != null) uri = uri.replace(queryParameters: params);
    final res = await http.get(uri, headers: await _authHeaders());
    return _parse(res);
  }

  // ── POST ─────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> post(
      String path, Map<String, dynamic> body,
      {bool auth = false}) async {
    final headers = auth ? await _authHeaders() : _jsonHeaders;
    final res = await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}$path'),
      headers: headers,
      body: jsonEncode(body),
    );
    return _parse(res) as Map<String, dynamic>;
  }

  // ── PATCH ────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> patch(
      String path, Map<String, dynamic> body, {bool auth = true}) async {
    final res = await http.patch(
      Uri.parse('${AppConfig.apiBaseUrl}$path'),
      headers: await _authHeaders(),
      body: jsonEncode(body),
    );
    return _parse(res) as Map<String, dynamic>;
  }

  // ── DELETE ───────────────────────────────────────────────────
  static Future<Map<String, dynamic>> delete(
      String path, {bool auth = true}) async {
    final res = await http.delete(
      Uri.parse('${AppConfig.apiBaseUrl}$path'),
      headers: await _authHeaders(),
    );
    return _parse(res) as Map<String, dynamic>;
  }

  // ── Helper ───────────────────────────────────────────────────
  static dynamic _parse(http.Response res) {
    final raw = utf8.decode(res.bodyBytes).trim();

    if (raw.isEmpty) {
      throw ApiException(
          'Server returned empty response (HTTP ${res.statusCode}). '
          'Check config.php DB credentials on Hostinger.',
          res.statusCode);
    }

    try {
      final body = jsonDecode(raw);
      if (res.statusCode >= 400) {
        throw ApiException(body['error'] ?? 'Unknown error', res.statusCode);
      }
      return body;
    } catch (e) {
      if (e is ApiException) rethrow;
      final preview = raw.length > 300 ? raw.substring(0, 300) : raw;
      throw ApiException('Server error: $preview', res.statusCode);
    }
  }
}

class ApiException implements Exception {
  final String message;
  final int    statusCode;
  ApiException(this.message, this.statusCode);
  @override String toString() => message;
}
