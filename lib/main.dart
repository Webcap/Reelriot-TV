import 'package:caffeine_tv/env.dart';
import 'package:caffeine_tv/screens/home_screen.dart';
import 'package:caffeine_tv/screens/pairing_screen.dart';
import 'package:caffeine_tv/screens/splash_screen.dart';
import 'package:caffeine_tv/services/ad_service.dart';
import 'package:caffeine_tv/services/settings_service.dart';
import 'package:caffeine_tv/utils/cleanup_utils.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  await bootstrap('.env');
}

Future<void> bootstrap(String envFile) async {
  debugPrint('[Main] 🚀 Bootstrapping with $envFile');
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load env first as it's required by subsequent service initializations
  await dotenv.load(fileName: envFile);
  
  // Initialize settings
  await SettingsService().init();
  debugPrint('[Main] ✅ Minimal requirements (env, settings) loaded');

  // Initialize Supabase synchronously to ensure session recovery
  final url = supabaseUrl.trim();
  final anonKey = supabaseAnonKey.trim();
  if (url.isNotEmpty && anonKey.isNotEmpty) {
    debugPrint('[Main] 🛠️ Initializing Supabase...');
    try {
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
    } catch (e) {
      debugPrint('[Main] ❌ Supabase initialization failed: $e');
    }
  }

  // Background initialization of other third-party services (Ads)
  unawaited(_initializeBgServices());

  // Async cleanup of update files (non-blocking)
  unawaited(cleanupUpdateFiles());

  runApp(const CaffeineTvApp());
}

Future<void> _initializeBgServices() async {
  try {
    // Initialize AdService
    debugPrint('[Main] 📺 Background initializing AdService...');
    await AdService.instance.initialize();
    debugPrint('[Main] ✅ AdService initialized');
  } catch (e) {
    debugPrint('[Main] ❌ Background initialization failed: $e');
  }
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
    if (!requireLogin) {
      return const SplashScreen(destination: HomeScreen());
    }

    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          final showHomeOnWait =
              Supabase.instance.client.auth.currentSession != null;
          return SplashScreen(
            destination: showHomeOnWait ? const HomeScreen() : const PairingScreen(),
          );
        }

        final session = snapshot.data?.session ??
            Supabase.instance.client.auth.currentSession;
        final destination =
            session != null ? const HomeScreen() : const PairingScreen();

        return SplashScreen(destination: destination);
      },
    );
  }
}
