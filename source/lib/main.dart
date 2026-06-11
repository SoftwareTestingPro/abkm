import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/web_utils.dart';

import 'config/config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Cleanly check for and activate web updates for existing logged-in sessions
  await performWebUpdateCheck();
  
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
    authOptions: FlutterAuthClientOptions(
      localStorage: SharedPreferencesLocalStorage(
        persistSessionKey: 'abkm_auth_token',
      ),
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '${AppConfig.appName} - Community Builder',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/auth': (context) => const AuthScreen(),
        '/home': (context) => const HomeScreen(),
        '/profile': (context) => const ProfileScreen(),
      },
    );
  }
}
