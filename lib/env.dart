import 'package:flutter_dotenv/flutter_dotenv.dart';

String _env(String key) {
  if (!dotenv.isInitialized) return '';
  return dotenv.env[key] ?? '';
}

String get tmdbApiKey => _env('TMDB_API_KEY');
String get caffeineApiUrl {
  final v = _env('CAFFEINE_API_URL').trim();
  final url = v.isEmpty ? 'https://caffeine.synqholdings.com' : v;
  return url.replaceFirst(RegExp(r'/$'), '');
}
String get supabaseUrl => _env('SUPABASE_URL');
String get supabaseAnonKey {
  final k = _env('SUPABASE_ANON_KEY');
  return k.isNotEmpty ? k : _env('SUPABASE_ANNON_KEY');
}
String get caffeineApiKey => _env('CAFFEINE_API_KEY');
String get pairingPageUrl => _env('PAIRING_PAGE_URL');

/// When true, app shows pairing screen until user signs in. When false (default), login is optional and home is shown.
bool get requireLogin {
  final v = _env('REQUIRE_LOGIN').trim().toLowerCase();
  return v == 'true' || v == '1' || v == 'yes';
}

String get environment {
  final env = _env('ENVIRONMENT').trim().toLowerCase();
  return env.isNotEmpty ? env : 'prod';
}
String get opensubtitlesApiKey => _env('OPENSUBTITLES_API_KEY');
String get mixpanelApiKey {
  final key = _env('MIXPANEL_API_KEY');
  return key.isNotEmpty ? key : _env('MIXPANEL_TOKEN');
}
