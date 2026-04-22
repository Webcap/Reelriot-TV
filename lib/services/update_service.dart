import 'package:caffeine_core/caffeine_core.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';

class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  /// Compares current version with latest version using the new structured API.
  Future<UpdateInfo> checkForUpdate(String caffeineApiUrl,
      {String env = 'prod', String? apiKey}) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    // Fetch from new structured endpoint
    final updateInfo = await fetchUpdateInfo(
      caffeineApiUrl: caffeineApiUrl,
      platform: 'tv',
      environment: env,
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
