import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'app/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = AuthService();
  await auth.init();
  runApp(
    ChangeNotifierProvider.value(
      value: auth,
      child: const MobileKhataApp(),
    ),
  );
}

class MobileKhataApp extends StatelessWidget {
  const MobileKhataApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MobileKhata',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Consumer<AuthService>(
        builder: (ctx, auth, _) =>
            auth.isLoggedIn ? const HomeScreen() : const LoginScreen(),
      ),
    );
  }
}
