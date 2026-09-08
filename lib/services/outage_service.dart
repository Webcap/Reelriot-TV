import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:reelriot_tv/env.dart';

/// Monitors the Caffeine API's health and notifies listeners when
/// the API is unreachable or returns a non-200 response.
///
/// This version supports real-time simulation via Supabase's `app_config` table.
class OutageService {
  OutageService._();
  static final OutageService instance = OutageService._();

  /// True when the API is considered down.
  final ValueNotifier<bool> isApiDown = ValueNotifier(false);

  /// Non-null when a message should be shown to the user.
  final ValueNotifier<String?> outageMessage = ValueNotifier(null);

  Timer? _timer;
  bool _checking = false;
  int _pauseCount = 0;
  RealtimeChannel? _subscription;

  static const String _configRowId = "00000000-0000-0000-0000-000000000001";
  static const Duration _pollInterval = Duration(seconds: 30);
  static const Duration _requestTimeout = Duration(seconds: 8);

  /// Starts periodic polling. Safe to call multiple times (idempotent).
  void start() {
    if (_pauseCount > 0) return;
    if (_timer != null && _timer!.isActive) return;
    debugPrint('[OutageService] 🚦 Started polling Caffeine API health');
    _check(); // Immediate first check
    _timer = Timer.periodic(_pollInterval, (_) => _check());
    _subscribeToRealtime();
  }

  void _subscribeToRealtime() {
    if (_subscription != null) return;

    try {
      _subscription = Supabase.instance.client
          .channel('public:app_config_outage')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'app_config',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: _configRowId,
            ),
            callback: (payload) {
              final newConfig = payload.newRecord['config'] as Map<String, dynamic>?;
              debugPrint('[OutageService] 🔄 Real-time update detected. Simulation: ${newConfig?['simulate_network_outage']}');
              _check();
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('[OutageService] ⚠️ Failed to subscribe to real-time updates: $e');
    }
  }

  /// Temporarily suspends polling. Increments a pause counter.
  void pause() {
    _pauseCount++;
    debugPrint('[OutageService] ⏸️ Pausing polling (count: $_pauseCount)');
    stop();
  }

  /// Resumes polling if no more pauses are active.
  void resume() {
    if (_pauseCount > 0) {
      _pauseCount--;
      debugPrint('[OutageService] ▶️ Resuming polling (remaining pauses: $_pauseCount)');
      if (_pauseCount == 0) {
        start();
      }
    }
  }

  /// Forces an immediate re-check and returns when complete.
  Future<void> forceCheck() => _check();

  /// Stops periodic polling.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _subscription?.unsubscribe();
    _subscription = null;
  }

  int _consecutiveFailures = 0;
  static const int _maxFailures = 3;

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;

    try {
      // 1. Check Supabase Simulation (Primary)
      if (environment == 'dev') {
        final response = await Supabase.instance.client
            .from('app_config')
            .select('config')
            .eq('id', _configRowId)
            .maybeSingle();

        if (response != null && response['config'] != null) {
          final config = response['config'] as Map<String, dynamic>;
          if (config['simulate_network_outage'] == true) {
            final msg = config['outage_message'] as String? ?? 
                'We\'re currently experiencing a service outage. Some features may be unavailable.';
            _setOffline(msg);
            _consecutiveFailures = 0; // Forced outage resets counter
            return;
          }
        }
      }

      // 2. API Status Check (Secondary)
      final base = caffeineApiUrl.replaceFirst(RegExp(r'/$'), '');
      final uri = Uri.parse('$base/status'); 
      
      final apiRes = await http.get(uri, headers: {
        'x-platform': 'tv',
      }).timeout(_requestTimeout);

      if (apiRes.statusCode == 503) {
        _setOffline('The Caffeine API is currently undergoing maintenance. Please try again shortly.');
        _consecutiveFailures = 0;
        return;
      }

      // If we reach here and it's 200, 401, or 404, the server is "alive".
      if (apiRes.statusCode == 200 || apiRes.statusCode == 401 || apiRes.statusCode == 404) {
        _consecutiveFailures = 0;
        _setOnline();
      } else {
        _handleFailure('Service returned status ${apiRes.statusCode}.');
      }
    } on TimeoutException {
      _handleFailure('The Caffeine API is taking too long to respond.');
    } catch (e) {
      _handleFailure('Unable to reach the Caffeine API.');
    } finally {
      _checking = false;
    }
  }

  void _handleFailure(String message) {
    _consecutiveFailures++;
    debugPrint('[OutageService] ⚠️ Health check failed ($_consecutiveFailures/$_maxFailures): $message');
    
    if (_consecutiveFailures >= _maxFailures) {
      _setOffline('$message Please check your network connection.');
    }
  }

  void _setOnline() {
    if (isApiDown.value != false) {
      debugPrint('[OutageService] ✅ API is back online. Removing overlay.');
      isApiDown.value = false;
      outageMessage.value = null;
    }
  }

  void _setOffline(String message) {
    if (isApiDown.value != true || outageMessage.value != message) {
      debugPrint('[OutageService] ❌ API outage detected: $message');
      isApiDown.value = true;
      outageMessage.value = message;
    }
  }

  void dispose() {
    stop();
    isApiDown.dispose();
    outageMessage.dispose();
  }
}
