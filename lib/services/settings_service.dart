import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui' as ui;

class SettingsService extends ChangeNotifier {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  late SharedPreferences _prefs;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _initialized = true;
  }

  static const String _keyLanguage = 'preferred_language';
  static const String _keyRegion = 'preferred_region';
  static const String _keyDefaultAudioLanguage = 'default_audio_language';

  String get language {
    // 1. Check saved preference
    final saved = _prefs.getString(_keyLanguage);
    if (saved != null) return saved;

    // 2. Fallback to system language
    final systemLocale = ui.PlatformDispatcher.instance.locale.languageCode;
    return systemLocale;
  }

  Future<void> setLanguage(String langCode) async {
    await _prefs.setString(_keyLanguage, langCode);
    notifyListeners();
  }

  String get defaultAudioLanguage {
    return _prefs.getString(_keyDefaultAudioLanguage) ?? language;
  }

  Future<void> setDefaultAudioLanguage(String langCode) async {
    await _prefs.setString(_keyDefaultAudioLanguage, langCode);
    notifyListeners();
  }

  String get region {
    return _prefs.getString(_keyRegion) ?? 'US';
  }

  Future<void> setRegion(String regionCode) async {
    await _prefs.setString(_keyRegion, regionCode);
    notifyListeners();
  }

  bool _sportsEnabled = true;
  bool get sportsEnabled => _sportsEnabled;

  bool _adsEnabled = true;
  bool get adsEnabled => _adsEnabled;

  void updateFromConfig(Map<String, dynamic> config) {
    // Check various keys for sports availability
    _sportsEnabled = (config['enable_ott'] == true ||
            config['enable_ott'].toString().toLowerCase() == 'true') ||
        (config['sports_enabled'] == true ||
            config['sports_enabled'].toString().toLowerCase() == 'true');

    // Check various keys for ads availability
    _adsEnabled = (config['enable_ads'] == true ||
            config['enable_ads'].toString().toLowerCase() == 'true') ||
        (config['ads_enabled'] == true ||
            config['ads_enabled'].toString().toLowerCase() == 'true');

    notifyListeners();
  }
}
