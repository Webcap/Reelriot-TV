import 'package:caffeine_core/caffeine_core.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:reelriot_tv/services/analytics_service.dart';

class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  String? _lastCaffeineApiUrl;
  String? _lastApiKey;
  String? _deviceId;

  Future<String> _getOrCreateDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    try {
      final prefs = await SharedPreferences.getInstance();
      String? id = prefs.getString('tv_anonymous_device_id');
      if (id == null || id.isEmpty) {
        id = 'tv_anon_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (DateTime.now().microsecondsSinceEpoch % 9000))}';
        await prefs.setString('tv_anonymous_device_id', id);
      }
      _deviceId = id;
      return id;
    } catch (_) {
      return 'tv_anon_fallback';
    }
  }

  /// Compares current version with latest version using the new structured API.
  Future<UpdateInfo> checkForUpdate(String caffeineApiUrl,
      {String env = 'prod', String? apiKey}) async {
    _lastCaffeineApiUrl = caffeineApiUrl;
    _lastApiKey = apiKey;

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.buildNumber.isNotEmpty && packageInfo.buildNumber != '0'
        ? '${packageInfo.version}+${packageInfo.buildNumber}'
        : packageInfo.version;
    final deviceId = await _getOrCreateDeviceId();

    // Fetch from new structured endpoint with version and device ID for rollouts
    final updateInfo = await fetchUpdateInfo(
      caffeineApiUrl: caffeineApiUrl,
      platform: 'tv',
      environment: env,
      clientVersion: packageInfo.version,
      anonymousId: deviceId,
      apiKey: apiKey,
    );

    if (updateInfo == null) {
      return UpdateInfo(
        isUpdateAvailable: false,
        latestVersion: currentVersion,
        currentVersion: currentVersion,
        isForced: false,
      );
    }

    final latestVersion = updateInfo.latestVersion;
    final isUpdateAvailable = isVersionHigher(latestVersion, currentVersion);
    
    debugPrint('[UpdateService] 🔍 Checking structured update: Current=$currentVersion, Latest=$latestVersion, Avail=$isUpdateAvailable');

    return UpdateInfo(
      isUpdateAvailable: isUpdateAvailable,
      latestVersion: latestVersion,
      currentVersion: currentVersion,
      isForced: updateInfo.isForced,
      downloadUrl: updateInfo.downloadUrl,
      changelog: updateInfo.changelog,
    );
  }

  /// Report telemetry events: 'version_check', 'forced_prompt_shown', 'update_download_clicked'
  Future<void> reportTelemetry({
    required String eventType,
    String? caffeineApiUrl,
    String? apiKey,
    bool isForcedPrompt = false,
  }) async {
    final apiUrl = caffeineApiUrl ?? _lastCaffeineApiUrl;
    if (apiUrl == null || apiUrl.isEmpty) return;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final deviceId = await _getOrCreateDeviceId();

      // Dispatch to Mixpanel for product telemetry
      AnalyticsService.instance.trackEvent('TV Update Telemetry', {
        'event_type': eventType,
        'client_version': packageInfo.version,
        'is_forced': isForcedPrompt,
      });

      // Dispatch to Caffeine API for fleet telemetry
      await sendUpdateTelemetry(
        caffeineApiUrl: apiUrl,
        platform: 'tv',
        clientVersion: packageInfo.version,
        eventType: eventType,
        deviceId: deviceId,
        isForcedPrompt: isForcedPrompt,
        apiKey: apiKey ?? _lastApiKey,
      );
    } catch (e) {
      debugPrint('[UpdateService] Failed to report telemetry: $e');
    }
  }

  /// Determines whether [latest] is strictly newer than [current].
  /// Handles SemVer, CalVer, leading 'v', build metadata ('+'), and avoids downgrade loops.
  bool isVersionHigher(String latest, String current) {
    if (latest.isEmpty || current.isEmpty) return false;

    // Normalize: strip leading 'v' / 'V' and trim whitespace
    final cleanLatest = latest.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final cleanCurrent = current.trim().replaceFirst(RegExp(r'^[vV]'), '');

    if (cleanLatest == cleanCurrent) return false;

    try {
      // Split base version from build metadata (e.g. "1.0.0+2" -> "1.0.0" and "2")
      final latestParts = cleanLatest.split('+');
      final currentParts = cleanCurrent.split('+');

      final latestBase = latestParts[0].split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final currentBase = currentParts[0].split('.').map((e) => int.tryParse(e) ?? 0).toList();

      final maxLen = latestBase.length > currentBase.length ? latestBase.length : currentBase.length;

      for (var i = 0; i < maxLen; i++) {
        final l = i < latestBase.length ? latestBase[i] : 0;
        final c = i < currentBase.length ? currentBase[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }

      // Base numbers are equal: check build numbers if present
      final lBuildStr = latestParts.length > 1 ? latestParts[1] : null;
      final cBuildStr = currentParts.length > 1 ? currentParts[1] : null;

      if (lBuildStr != null && cBuildStr != null) {
        final lBuild = int.tryParse(lBuildStr);
        final cBuild = int.tryParse(cBuildStr);
        if (lBuild != null && cBuild != null) {
          return lBuild > cBuild;
        }
        return lBuildStr.compareTo(cBuildStr) > 0;
      } else if (lBuildStr != null && cBuildStr == null) {
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('[UpdateService] Error comparing versions: $e');
      return false;
    }
  }
}

class UpdateInfo {
  final bool isUpdateAvailable;
  final String latestVersion;
  final String currentVersion;
  final bool isForced;
  final String? downloadUrl;
  final String? changelog;

  UpdateInfo({
    required this.isUpdateAvailable,
    required this.latestVersion,
    required this.currentVersion,
    required this.isForced,
    this.downloadUrl,
    this.changelog,
  });
}
