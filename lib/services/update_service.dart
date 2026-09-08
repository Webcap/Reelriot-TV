import 'package:caffeine_core/caffeine_core.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

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
    final currentVersion = packageInfo.version;
    final deviceId = await _getOrCreateDeviceId();

    // Fetch from new structured endpoint with version and device ID for rollouts
    final updateInfo = await fetchUpdateInfo(
      caffeineApiUrl: caffeineApiUrl,
      platform: 'tv',
      environment: env,
      clientVersion: currentVersion,
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
    final isUpdateAvailable = _isVersionHigher(latestVersion, currentVersion);
    
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

  bool _isVersionHigher(String latest, String current) {
    try {
      final latestParts = latest.split('.').map(int.parse).toList();
      final currentParts = current.split('.').map(int.parse).toList();

      for (var i = 0; i < latestParts.length; i++) {
        if (i >= currentParts.length) return true;
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }
      return false;
    } catch (e) {
      // Fallback to simple string comparison or return false if invalid
      return latest != current;
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
