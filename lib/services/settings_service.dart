import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../env.dart';
import 'dart:ui' as ui;
import 'analytics_service.dart';

class SettingsService extends ChangeNotifier {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  late SharedPreferences _prefs;
  bool _initialized = false;
  bool _isOffline = false;

  bool get isOffline => _isOffline;
  set isOffline(bool value) {
    _isOffline = value;
    notifyListeners();
  }

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _useExternalSubtitles = _prefs.getBool(_keyUseExternalSubtitles) ?? true;
    _initialized = true;
  }

  static const String _keyLanguage = 'preferred_language';
  static const String _keyRegion = 'preferred_region';
  static const String _keyDefaultAudioLanguage = 'default_audio_language';
  static const String _keyUseExternalSubtitles = 'use_external_subtitles';

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

  String _opensubtitlesKey = opensubtitlesApiKey;
  String get opensubtitlesKey => _opensubtitlesKey;
  
  bool _useExternalSubtitles = true;
  bool get useExternalSubtitles => _useExternalSubtitles;

  Future<void> setUseExternalSubtitles(bool value) async {
    _useExternalSubtitles = value;
    await _prefs.setBool(_keyUseExternalSubtitles, value);
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

    if (config['opensubtitles_key'] != null) {
      _opensubtitlesKey = config['opensubtitles_key'];
    }

    if (config['use_external_subtitles'] != null) {
      _useExternalSubtitles = config['use_external_subtitles'] == true || config['use_external_subtitles'].toString().toLowerCase() == 'true';
      _prefs.setBool(_keyUseExternalSubtitles, _useExternalSubtitles);
    }

    if (config['mixpanel_token'] != null && config['mixpanel_token'].toString().isNotEmpty) {
      AnalyticsService.instance.initialize(config['mixpanel_token'].toString());
    }

    notifyListeners();
  }
}
