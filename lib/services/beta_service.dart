import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service managing beta build channel access and encrypted credential storage.
class BetaService {
  static const _storage = FlutterSecureStorage();
  static const _keyBetaKey = 'beta_access_key';
  static const _keyBuildChannel = 'build_channel';

  /// Retrieves the stored beta access key, if any.
  static Future<String?> getBetaKey() => _storage.read(key: _keyBetaKey);

  /// Stores a validated or user-provided beta access key.
  static Future<void> setBetaKey(String key) =>
      _storage.write(key: _keyBetaKey, value: key.trim());

  /// Gets the current active build channel (defaults to 'stable').
  static Future<String> getBuildChannel() async =>
      (await _storage.read(key: _keyBuildChannel)) ?? 'stable';

  /// Sets the active build channel (e.g. 'stable', 'beta', 'dev').
  static Future<void> setBuildChannel(String channel) =>
      _storage.write(key: _keyBuildChannel, value: channel.trim().toLowerCase());

  /// Resets back to the stable channel and deletes stored keys.
  static Future<void> clearBeta() async {
    await _storage.delete(key: _keyBetaKey);
    await _storage.write(key: _keyBuildChannel, value: 'stable');
  }
}
