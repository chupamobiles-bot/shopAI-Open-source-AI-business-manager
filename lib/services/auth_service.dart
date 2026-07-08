import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class AuthService extends ChangeNotifier {
  String? _token;
  String? _shopName;
  int?    _shopId;

  bool   get isLoggedIn => _token != null;
  String get token      => _token ?? '';
  String get shopName   => _shopName ?? '';
  int    get shopId     => _shopId ?? 0;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token    = prefs.getString('token');
    _shopName = prefs.getString('shop_name');
    _shopId   = prefs.getInt('shop_id');
  }

  Future<void> login(String email, String password) async {
    final data = await ApiService.post('/auth/login', {
      'email': email,
      'password': password,
    });
    await _save(data);
  }

  Future<void> register({
    required String shopName,
    required String ownerName,
    required String email,
    required String password,
    String? phone,
  }) async {
    final data = await ApiService.post('/auth/register', {
      'shop_name':  shopName,
      'owner_name': ownerName,
      'email':      email,
      'password':   password,
      'phone':      phone,
    });
    await _save(data);
  }

  Future<void> _save(Map<String, dynamic> data) async {
    _token    = data['token'];
    _shopName = data['shop_name'];
    _shopId   = data['shop_id'] is int
        ? data['shop_id']
        : int.tryParse('${data['shop_id']}');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token',     _token ?? '');
    await prefs.setString('shop_name', _shopName ?? '');
    await prefs.setInt('shop_id',      _shopId ?? 0);
    notifyListeners();
  }

  Future<void> logout() async {
    _token = _shopName = null; _shopId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    notifyListeners();
  }
}
