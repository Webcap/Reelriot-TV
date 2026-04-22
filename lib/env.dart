import 'package:flutter_dotenv/flutter_dotenv.dart';

String get tmdbApiKey => dotenv.env['TMDB_API_KEY'] ?? '';
String get caffeineApiUrl {
  final v = dotenv.env['CAFFEINE_API_URL']?.trim() ?? '';
  return v.isEmpty ? 'https://caffeine.synqholdings.com/' : (v.endsWith('/') ? v : '$v/');
}
String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? dotenv.env['SUPABASE_ANNON_KEY'] ?? '';
String get caffeineApiKey => dotenv.env['CAFFEINE_API_KEY'] ?? '';
String get pairingPageUrl => dotenv.env['PAIRING_PAGE_URL'] ?? '';

/// When true, app shows pairing screen until user signs in. When false (default), login is optional and home is shown.
bool get requireLogin {
  final v = dotenv.env['REQUIRE_LOGIN']?.trim().toLowerCase();
  return v == 'true' || v == '1' || v == 'yes';
}

String get environment => dotenv.env['ENVIRONMENT']?.trim().toLowerCase() ?? 'prod';
String get opensubtitlesApiKey => dotenv.env['OPENSUBTITLES_API_KEY'] ?? '';
