import 'package:mixpanel_flutter/mixpanel_flutter.dart';
import 'package:flutter/foundation.dart';

class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  static AnalyticsService get instance => _instance;

  AnalyticsService._internal();

  Mixpanel? _mixpanel;
  bool _initialized = false;

  Future<void> initialize(String token) async {
    if (token.isEmpty) {
      debugPrint('Mixpanel token is empty, skipping initialization');
      return;
    }
    
    if (_initialized) return;

    try {
      _mixpanel = await Mixpanel.init(token, trackAutomaticEvents: true);
      _initialized = true;
      debugPrint('Mixpanel initialized successfully');
      trackEvent('App Started');
    } catch (e) {
      debugPrint('Failed to initialize Mixpanel: $e');
    }
  }

  void trackEvent(String eventName, [Map<String, dynamic>? properties]) {
    if (!_initialized || _mixpanel == null) {
      debugPrint('Mixpanel not initialized, skipping event: $eventName');
      return;
    }

    try {
      debugPrint('Mixpanel track: $eventName ${properties ?? ""}');
      _mixpanel!.track(eventName, properties: properties);
    } catch (e) {
      debugPrint('Failed to track Mixpanel event: $eventName: $e');
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
