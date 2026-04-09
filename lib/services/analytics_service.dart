import 'package:mixpanel_flutter/mixpanel_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';

class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  static AnalyticsService get instance => _instance;

  AnalyticsService._internal();

  Mixpanel? _mixpanel;
  bool _initialized = false;
  final _supabase = Supabase.instance.client;
  String? _appVersion;

  Future<void> initialize(String token) async {
    if (token.isEmpty) {
      debugPrint('Mixpanel token is empty, skipping initialization');
      return;
    }

    if (_initialized) return;

    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = '${info.version}+${info.buildNumber}';

      _mixpanel = await Mixpanel.init(token, trackAutomaticEvents: true);
      _initialized = true;
      debugPrint('Mixpanel initialized successfully');
      trackEvent('App Started');
    } catch (e) {
      debugPrint('Failed to initialize Mixpanel: $e');
    }
  }

  /// Track a general user engagement event (Mixpanel + Supabase)
  void trackEvent(String eventName, [Map<String, dynamic>? properties]) {
    // 1. Log to Mixpanel for product analytics
    if (_initialized && _mixpanel != null) {
      try {
        _mixpanel!.track(eventName, properties: properties);
      } catch (e) {
        debugPrint('Failed to track Mixpanel event: $eventName: $e');
      }
    }

    // 2. Log to Supabase for detailed internal technical tracking
    _logToSupabase(eventName, properties);
  }

  /// Track a technical Quality of Service (QoS) event (Supabase only to save Mixpanel quota)
  void trackQoSEvent(String eventName, [Map<String, dynamic>? properties]) {
    debugPrint('Analytics [QoS]: $eventName ${properties ?? ""}');
    _logToSupabase(eventName, properties, isQoS: true);
  }

  Future<void> _logToSupabase(String eventName, Map<String, dynamic>? properties,
      {bool isQoS = false}) async {
    try {
      final session = _supabase.auth.currentSession;
      final userId = session?.user.id;

      final payload = {
        'event_name': eventName,
        'platform': 'tv',
        'sub_platform': Platform.isAndroid ? 'android_tv' : 'tizen',
        'user_id': userId,
        'is_qos': isQoS,
        'properties': properties ?? {},
        'app_version': _appVersion ?? 'unknown',
      };

      // Fire and forget to avoid blocking UI
      _supabase.from('detailed_events').insert(payload).then((_) {
        // Success
      }).catchError((e) {
        debugPrint('Failed to log event to Supabase: $e');
      });
    } catch (e) {
      // Ignore errors in analytics logging to prevent app crashes
    }
  }

  void identify(String userId) {
    if (!_initialized || _mixpanel == null) return;
    debugPrint('Mixpanel identify: $userId');
    _mixpanel!.identify(userId);
  }

  void setUserProfile(String key, dynamic value) {
    if (!_initialized || _mixpanel == null) return;
    debugPrint('Mixpanel setProfile: $key = $value');
    _mixpanel!.getPeople().set(key, value);
  }

  void reset() {
    if (!_initialized || _mixpanel == null) return;
    debugPrint('Mixpanel reset');
    _mixpanel!.reset();
  }
}

