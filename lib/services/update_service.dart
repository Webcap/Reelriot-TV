import 'package:caffeine_core/caffeine_core.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:reelriot_tv/services/analytics_service.dart';
import 'package:reelriot_tv/services/beta_service.dart';
import 'package:uuid/uuid.dart';

class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  String? _lastCaffeineApiUrl;
  String? _lastApiKey;
  String? _deviceId;

  /// Timestamp of the last successful update check, used to enforce the
  /// 4-hour re-check cooldown and prevent redundant telemetry per session.
  DateTime? _lastUpdateCheck;

  /// Returns true when enough time has passed to warrant a fresh check.
  bool get shouldRecheck {
    if (_lastUpdateCheck == null) return true;
    return DateTime.now().difference(_lastUpdateCheck!) > const Duration(hours: 4);
  }

  Future<String> _getOrCreateDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    try {
      final prefs = await SharedPreferences.getInstance();
      String? id = prefs.getString('tv_anonymous_device_id');
      if (id == null || id.isEmpty) {
        // Use UUID v4 for cryptographically strong uniqueness.
        // The old timestamp+modulo approach had only ~9000 unique values
        // and could collide across devices starting simultaneously.
        id = 'tv_${const Uuid().v4()}';
        await prefs.setString('tv_anonymous_device_id', id);
      }
      _deviceId = id;
      return id;
    } catch (_) {
      // Even the fallback uses UUID so no two devices share a bucket.
      return 'tv_${const Uuid().v4()}';
    }
  }

  /// Compares current version with latest version using the new structured API.
  Future<UpdateInfo> checkForUpdate(
    String caffeineApiUrl, {
    String env = 'prod',
    String? buildChannel,
    String? betaKey,
    String? apiKey,
  }) async {
    _lastCaffeineApiUrl = caffeineApiUrl;
    _lastApiKey = apiKey;

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.buildNumber.isNotEmpty && packageInfo.buildNumber != '0'
        ? '${packageInfo.version}+${packageInfo.buildNumber}'
        : packageInfo.version;
    final deviceId = await _getOrCreateDeviceId();

    // Determine target build channel and key
    final targetChannel = buildChannel ?? await BetaService.getBuildChannel();
    final targetKey = betaKey ?? await BetaService.getBetaKey();

    // Fetch from new structured endpoint with version, channel, and device ID for rollouts
    final updateInfo = await fetchUpdateInfo(
      caffeineApiUrl: caffeineApiUrl,
      platform: 'tv',
      environment: env,
      buildChannel: targetChannel,
      betaKey: targetKey,
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
        buildChannel: targetChannel,
      );
    }

    final latestVersion = updateInfo.latestVersion;
    final isUpdateAvailable = isVersionHigher(latestVersion, currentVersion);
    
    debugPrint('[UpdateService] 🔍 Checking structured update: Channel=$targetChannel, Current=$currentVersion, Latest=$latestVersion, Avail=$isUpdateAvailable');
    _lastUpdateCheck = DateTime.now();

    return UpdateInfo(
      isUpdateAvailable: isUpdateAvailable,
      latestVersion: latestVersion,
      currentVersion: currentVersion,
      isForced: updateInfo.isForced,
      downloadUrl: updateInfo.downloadUrl,
      changelog: updateInfo.changelog,
      buildChannel: updateInfo.buildChannel,
      releaseTag: updateInfo.releaseTag,
      buildNotes: updateInfo.buildNotes,
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
  final String buildChannel;
  final String? releaseTag;
  final String? buildNotes;

  UpdateInfo({
    required this.isUpdateAvailable,
    required this.latestVersion,
    required this.currentVersion,
    required this.isForced,
    this.downloadUrl,
    this.changelog,
    this.buildChannel = 'stable',
    this.releaseTag,
    this.buildNotes,
  });
}
