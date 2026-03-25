import 'package:caffeine_tv/env.dart';
import 'package:caffeine_tv/screens/home_screen.dart';
import 'package:caffeine_tv/screens/pairing_screen.dart';
import 'package:caffeine_tv/screens/splash_screen.dart';
import 'package:caffeine_tv/services/ad_service.dart';
import 'package:caffeine_tv/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  await bootstrap('.env');
}

Future<void> bootstrap(String envFile) async {
  debugPrint('[Main] 🚀 Bootstrapping with $envFile');
  WidgetsFlutterBinding.ensureInitialized();
  
  debugPrint('[Main] 📝 Loading env file...');
  await dotenv.load(fileName: envFile);
  debugPrint('[Main] ✅ Env loaded');

  // Initialize AdService
  debugPrint('[Main] 📺 Initializing AdService...');
  await AdService.instance.initialize();
  debugPrint('[Main] ✅ AdService initialized');

  final url = supabaseUrl.trim();
  final anonKey = supabaseAnonKey.trim();
  debugPrint('[Main] 🔗 Supabase URL: ${url.isNotEmpty ? 'SET' : 'MISSING'}');
  
  if (url.isNotEmpty && anonKey.isNotEmpty) {
    debugPrint('[Main] 🛠️ Initializing Supabase...');
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
