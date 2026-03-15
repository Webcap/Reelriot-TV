import 'package:flutter_dotenv/flutter_dotenv.dart';

String get tmdbApiKey => dotenv.env['TMDB_API_KEY'] ?? '';
String get caffeineApiUrl {
  final v = dotenv.env['CAFFEINE_API_URL']?.trim() ?? '';
  return v.isEmpty ? 'https://caffeine.synqholdings.com/' : (v.endsWith('/') ? v : '$v/');
}
String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? dotenv.env['SUPABASE_ANNON_KEY'] ?? '';
String get pairingPageUrl => dotenv.env['PAIRING_PAGE_URL'] ?? '';
