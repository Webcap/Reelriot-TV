import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:reelriot_tv/env.dart';

/// Monitors the Caffeine API's /status endpoint and notifies listeners when
/// the API is unreachable or returns a non-200 response.
///
/// Usage:
///   OutageService.instance.isApiDown  // `ValueNotifier<bool>`
///   OutageService.instance.start();   // call once in main
///   OutageService.instance.dispose(); // call on app teardown
class OutageService {
  OutageService._();
  static final OutageService instance = OutageService._();

  /// True when the API is considered down.
  final ValueNotifier<bool> isApiDown = ValueNotifier(false);

  /// Non-null when a message should be shown to the user.
  final ValueNotifier<String?> outageMessage = ValueNotifier(null);

  Timer? _timer;
  bool _checking = false;

  static const Duration _pollInterval = Duration(seconds: 30);
  static const Duration _requestTimeout = Duration(seconds: 8);

  /// Starts periodic polling. Safe to call multiple times (idempotent).
  void start() {
    if (_timer != null && _timer!.isActive) return;
    debugPrint('[OutageService] 🚦 Started polling Caffeine API health');
    _check(); // Immediate first check
    _timer = Timer.periodic(_pollInterval, (_) => _check());
  }

  /// Forces an immediate re-check and returns when complete.
  Future<void> forceCheck() => _check();

  /// Stops periodic polling.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;

    try {
      final base = caffeineApiUrl.replaceFirst(RegExp(r'/$'), '');
      final uri = Uri.parse('$base/status');
      debugPrint('[OutageService] 🔍 Checking API health: $uri');

      final res = await http.get(uri).timeout(_requestTimeout);

      // If we get a response (even 401 or 404), the server is alive.
      // We only consider it an "outage" if we can't reach the server at all.
      if (res.statusCode == 200 || res.statusCode == 401 || res.statusCode == 404) {
        _setOnline();
      } else {
        _setOffline('Service returned status ${res.statusCode}.');
      }
    } on TimeoutException {
      _setOffline('The Caffeine API is taking too long to respond. Please try again shortly.');
    } catch (e) {
      _setOffline('Unable to reach the Caffeine API. Please check your network connection.');
    } finally {
      _checking = false;
    }
  }

  void _setOnline() {
    if (isApiDown.value) {
      debugPrint('[OutageService] ✅ API is back online');
    }
    isApiDown.value = false;
    outageMessage.value = null;
  }

  void _setOffline(String message) {
    debugPrint('[OutageService] ❌ API outage detected: $message');
    isApiDown.value = true;
    outageMessage.value = message;
  }

  void dispose() {
    stop();
    isApiDown.dispose();
    outageMessage.dispose();
  }
}

