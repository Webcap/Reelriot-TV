import 'package:reelriot_tv/env.dart';
import 'package:media_kit/media_kit.dart';
import 'package:reelriot_tv/screens/home_screen.dart';
import 'package:reelriot_tv/screens/pairing_screen.dart';
import 'package:reelriot_tv/screens/splash_screen.dart';
import 'package:reelriot_tv/services/ad_service.dart';
import 'package:reelriot_tv/services/outage_service.dart';
import 'package:reelriot_tv/services/settings_service.dart';
import 'package:reelriot_tv/utils/cleanup_utils.dart';
import 'package:reelriot_tv/widgets/outage_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('[FlutterError] ${details.exception}');
    };
    await bootstrap('.env');
  }, (error, stack) {
    debugPrint('[ZonedError] $error\n$stack');
  });
}

Future<void> bootstrap(String envFile) async {
  // If in release mode, override debugPrint to do nothing
  // if (kReleaseMode) {
  //   debugPrint = (String? message, {int? wrapWidth}) {};
  // }

  debugPrint('[Main] 🚀 Bootstrapping with $envFile');
  // WidgetsFlutterBinding already called in main
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
      await Supabase.initialize(
        url: url,
        anonKey: anonKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
        debug: false,
      );
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
      // We no longer aggressively signOut here. 
      // If the token is truly dead, Supabase will emit a signedOut event naturally.
    }
  }

  // Start API health monitoring — detects outages and blocks the UI
  OutageService.instance.start();

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
      // Wrap every route with the outage overlay so no screen is accessible
      // when the Caffeine API is down.
      builder: (context, child) => OutageOverlay(child: child ?? const SizedBox.shrink()),
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
        // If we already have a session in the client, prefer staying on Home
        // rather than jumping to Pairing while the stream is initializing.
        final currentSession = Supabase.instance.client.auth.currentSession;

        if (snapshot.connectionState == ConnectionState.waiting && currentSession == null) {
          return const SplashScreen(destination: PairingScreen());
        }

        final session = snapshot.data?.session ?? currentSession;
        final destination = session != null
            ? const HomeScreen()
            : const PairingScreen();

        return SplashScreen(destination: destination);
      },
    );
  }
}
