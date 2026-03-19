import 'package:caffeine_tv/env.dart';
import 'package:caffeine_tv/screens/home_screen.dart';
import 'package:caffeine_tv/screens/pairing_screen.dart';
import 'package:caffeine_tv/screens/splash_screen.dart';
import 'package:caffeine_tv/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  final url = supabaseUrl.trim();
  final anonKey = supabaseAnonKey.trim();
  if (url.isNotEmpty && anonKey.isNotEmpty) {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      debug: false,
    );

    // Verify session recovery
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      debugPrint('[Main] 👤 Session recovered on startup for: ${session.user.email}');
    } else {
      debugPrint('[Main] 👤 No session found on startup');
    }
  }

  // Initialize SettingsService
  await SettingsService().init();

  runApp(const CaffeineTvApp());
}

class CaffeineTvApp extends StatelessWidget {
  const CaffeineTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Caffeine TV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFDC2626), brightness: Brightness.dark),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const _AuthGate(),
        '/pairing': (context) => const PairingScreen(),
        '/home': (context) => const HomeScreen(),
      },
    );
  }
}

/// Login is optional by default. Set REQUIRE_LOGIN=true in .env to require pairing before home.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final Widget destination;
    if (requireLogin) {
      final session = Supabase.instance.client.auth.currentSession;
      destination = session != null ? const HomeScreen() : const PairingScreen();
    } else {
      destination = const HomeScreen();
    }
    return SplashScreen(destination: destination);
  }
}
