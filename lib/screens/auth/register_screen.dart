import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../app/theme.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _shopName  = TextEditingController();
  final _ownerName = TextEditingController();
  final _phone     = TextEditingController();
  final _email     = TextEditingController();
  final _password  = TextEditingController();
  bool _loading    = false;

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await context.read<AuthService>().register(
        shopName:  _shopName.text.trim(),
        ownerName: _ownerName.text.trim(),
        email:     _email.text.trim(),
        password:  _password.text,
        phone:     _phone.text.trim(),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _field(_shopName,  'Shop Name',   Icons.store_outlined,   required: true),
              _field(_ownerName, 'Owner Name',  Icons.person_outline,   required: true),
              _field(_phone,     'Phone',       Icons.phone_outlined,   keyboardType: TextInputType.phone),
              _field(_email,     'Email',       Icons.email_outlined,   required: true,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => (v == null || !v.contains('@')) ? 'Enter valid email' : null),
              _field(_password,  'Password',   Icons.lock_outline,     required: true, obscure: true,
                  validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: _loading ? null : _register,
                child: _loading
                    ? const SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Create Account'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon, {
    bool required = false,
    bool obscure  = false,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextFormField(
          controller: ctrl,
          obscureText: obscure,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon),
          ),
          validator: validator ?? (required ? (v) => (v == null || v.isEmpty) ? 'Required' : null : null),
        ),
      );
}
