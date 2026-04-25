import 'package:reelriot_tv/env.dart';
import 'package:media_kit/media_kit.dart';
import 'package:reelriot_tv/screens/home_screen.dart';
import 'package:reelriot_tv/screens/pairing_screen.dart';
import 'package:reelriot_tv/screens/splash_screen.dart';
import 'package:reelriot_tv/services/ad_service.dart';
import 'package:reelriot_tv/services/settings_service.dart';
import 'package:reelriot_tv/utils/cleanup_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  await bootstrap('.env');
}

Future<void> bootstrap(String envFile) async {
  // If in release mode, override debugPrint to do nothing
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  debugPrint('[Main] 🚀 Bootstrapping with $envFile');
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

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
      await Supabase.initialize(url: url, anonKey: anonKey, debug: false);
      // Verify session recovery
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        debugPrint(
          '[Main] 👤 Session recovered on startup for: ${session.user.email ?? 'Anonymous'}',
        );
      } else {
        debugPrint('[Main] 👤 No session found on startup');
      }
    } catch (e) {
      debugPrint('[Main] ❌ Supabase initialization failed: $e');
      if (e.toString().contains('refresh_token_already_used')) {
        debugPrint('[Main] ⚠️ Refresh token already used. Clearing session...');
        try {
          // Attempt to sign out to clear the corrupted session from local storage
          await Supabase.instance.client.auth.signOut();
        } catch (_) {}
      }
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
    // Initialize AdService with the current settings flag
    await AdService.instance.initialize(enabled: SettingsService().adsEnabled);
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
      title: 'Reelriot TV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFDC2626),
          brightness: Brightness.dark,
        ),
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
            destination: showHomeOnWait
                ? const HomeScreen()
                : const PairingScreen(),
          );
        }

        final session =
            snapshot.data?.session ??
            Supabase.instance.client.auth.currentSession;
        final destination = session != null
            ? const HomeScreen()
            : const PairingScreen();

        return SplashScreen(destination: destination);
      },
    );
  }
}
