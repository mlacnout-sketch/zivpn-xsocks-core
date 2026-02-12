import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_colors.dart';
import 'screens/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _setupDefaults();
  runApp(const MiniZivpnApp());
}

Future<void> _setupDefaults() async {
  final prefs = await SharedPreferences.getInstance();
  
  // Set defaults if not present
  if (!prefs.containsKey('mtu')) await prefs.setInt('mtu', 1500);
  if (!prefs.containsKey('tcp_snd_buf')) await prefs.setString('tcp_snd_buf', '65535');
  if (!prefs.containsKey('tcp_wnd')) await prefs.setString('tcp_wnd', '65535');
  if (!prefs.containsKey('socks_buf')) await prefs.setString('socks_buf', '65536');
  if (!prefs.containsKey('udpgw_max_connections')) await prefs.setString('udpgw_max_connections', '512');
  if (!prefs.containsKey('udpgw_buffer_size')) await prefs.setString('udpgw_buffer_size', '32');
  if (!prefs.containsKey('ping_interval')) await prefs.setString('ping_interval', '3');
  if (!prefs.containsKey('ping_target')) await prefs.setString('ping_target', 'http://www.gstatic.com/generate_204');
  if (!prefs.containsKey('log_level')) await prefs.setString('log_level', 'info');
  if (!prefs.containsKey('core_count')) await prefs.setInt('core_count', 4);
}

class MiniZivpnApp extends StatelessWidget {
  const MiniZivpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MiniZivpn',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
          surface: AppColors.surface,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: AppColors.card,
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: const HomePage(),
    );
  }
}
