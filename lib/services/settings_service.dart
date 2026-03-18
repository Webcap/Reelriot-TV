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

  bool _sportsEnabled = true;
  bool get sportsEnabled => _sportsEnabled;

  void updateFromConfig(Map<String, dynamic> config) {
    _sportsEnabled = config['enable_ott'] == true ||
        config['enable_ott'].toString().toLowerCase() == 'true';
    notifyListeners();
  }
}
