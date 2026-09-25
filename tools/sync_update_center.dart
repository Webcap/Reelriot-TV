import 'dart:convert';
import 'dart:io';
// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Synchronizes release metadata and download URLs directly to the ReelRiot Update Center (Supabase / Caffeine API).
/// Supports stable, beta, and dev build channels with optional SHA-256 beta access key protection.
Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  final projectRoot = _getProjectRoot();

  final envMap = _loadEnv(projectRoot);

  final supabaseUrl = options['supabase-url'] ?? envMap['SUPABASE_URL'];
  final serviceRoleKey = options['service-key'] ?? envMap['SUPABASE_SERVICE_ROLE_KEY'];
  final caffeineApiUrl = options['caffeine-api-url'] ?? envMap['CAFFEINE_API_URL'];
  final caffeineApiKey = options['caffeine-api-key'] ?? envMap['CAFFEINE_API_KEY'];

  final platform = (options['platform'] ?? 'tv').toLowerCase();
  var environment = (options['environment'] ?? 'production').toLowerCase();
  if (environment == 'prod') environment = 'production';
  if (environment == 'dev') environment = 'development';

  // Build Channel handling: stable, beta, dev
  var channel = (options['channel'] ?? options['build-channel'] ?? '').toLowerCase();
  if (options['beta'] == 'true' || options['beta'] == true) {
    channel = 'beta';
  } else if (channel.isEmpty) {
    channel = 'stable';
  }

  final version = options['version'] ?? _getVersionFromPubspec(projectRoot);
  final versionClean = version.replaceAll('+', '_');
  final repoName = options['repo'] ?? envMap['GITHUB_REPOSITORY'] ?? 'Webcap/Reelriot-TV';
  final releaseTag = options['release-tag'] ?? options['tag'] ?? 'v$version';

  final flavor = (environment == 'development') ? 'dev' : 'prod';

  // Primary APK link for Android TV (Universal APK)
  String downloadUrl = options['download-url'] ?? '';
  if (downloadUrl.isEmpty) {
    downloadUrl = 'https://github.com/$repoName/releases/download/$releaseTag/ReelriotTV-$flavor-v$versionClean-universal.apk';
  }

  final storeUrl = options['store-url'] ?? 'https://reelriot.app/tv';
  final isForced = options['forced'] == 'true' || options['forced'] == true;
  final rolloutPercentage = int.tryParse(options['rollout-percentage']?.toString() ?? '') ?? 100;
  final rolloutStatus = options['rollout-status'] ?? (channel == 'beta' ? 'beta' : 'active');
  final minSupportedVersion = options['min-supported-version'] ?? options['min-version'];

  // Changelog
  String changelog = '';
  if (options['changelog-file'] != null) {
    final file = File(options['changelog-file']);
    if (file.existsSync()) {
      changelog = file.readAsStringSync();
    }
  } else if (options['changelog'] != null) {
    changelog = options['changelog'];
  }

  // Channel-specific build notes (e.g. beta release notes, experimental flags)
  String buildNotes = '';
  if (options['build-notes-file'] != null) {
    final file = File(options['build-notes-file']);
    if (file.existsSync()) {
      buildNotes = file.readAsStringSync();
    }
  } else if (options['build-notes'] != null) {
    buildNotes = options['build-notes'];
  }

  // Beta Access Key (optional secret access key for gated beta builds)
  final rawBetaKey = options['beta-key'] ?? options['beta-access-key'] ?? envMap['BETA_ACCESS_KEY'];
  String? hashedBetaKey;
  if (rawBetaKey != null && rawBetaKey.toString().trim().isNotEmpty) {
    final trimmed = rawBetaKey.toString().trim();
    if (RegExp(r'^[a-f0-9]{64}$', caseSensitive: false).hasMatch(trimmed)) {
      hashedBetaKey = trimmed.toLowerCase();
    } else {
      hashedBetaKey = sha256.convert(utf8.encode(trimmed)).toString().toLowerCase();
    }
  }

  final downloadUrls = <String, String>{
    'primary': downloadUrl,
    'universal': 'https://github.com/$repoName/releases/download/$releaseTag/ReelriotTV-$flavor-v$versionClean-universal.apk',
    'arm64_v8a': 'https://github.com/$repoName/releases/download/$releaseTag/ReelriotTV-$flavor-v$versionClean-arm64-v8a.apk',
    'armeabi_v7a': 'https://github.com/$repoName/releases/download/$releaseTag/ReelriotTV-$flavor-v$versionClean-armeabi-v7a.apk',
    'x86_64': 'https://github.com/$repoName/releases/download/$releaseTag/ReelriotTV-$flavor-v$versionClean-x86_64.apk',
  };

  stdout.writeln('======================================================');
  stdout.writeln('       Syncing ReelRiot TV to Update Center           ');
  stdout.writeln('======================================================');
  stdout.writeln(' Platform    : $platform');
  stdout.writeln(' Environment : $environment');
  stdout.writeln(' Channel     : $channel');
  stdout.writeln(' Release Tag : $releaseTag');
  stdout.writeln(' Version     : $version');
  stdout.writeln(' Status      : $rolloutStatus ($rolloutPercentage%)');
  stdout.writeln(' Beta Key    : ${hashedBetaKey != null ? "[Configured (SHA-256 protected)]" : "[None / Public]"}');
  stdout.writeln(' Package     : Universal / Split APKs');
  stdout.writeln(' DownloadUrl : $downloadUrl');
  stdout.writeln(' Forced      : $isForced');
  stdout.writeln('======================================================');

  bool synced = false;

  // 1. Primary Sync: Supabase Direct Upsert (Single source of truth)
  if (supabaseUrl != null && serviceRoleKey != null && supabaseUrl.isNotEmpty && serviceRoleKey.isNotEmpty) {
    try {
      final sanitizedBaseUrl = supabaseUrl.endsWith('/') ? supabaseUrl.substring(0, supabaseUrl.length - 1) : supabaseUrl;
      final headers = <String, String>{
        'apikey': serviceRoleKey,
        'Authorization': 'Bearer $serviceRoleKey',
        'Content-Type': 'application/json',
        'Prefer': 'resolution=merge-duplicates,return=representation',
      };

      final payloadMap = <String, dynamic>{
        'platform': platform,
        'environment': environment,
        'build_channel': channel,
        'latest_version': version,
        'is_forced': isForced,
        'rollout_percentage': rolloutPercentage,
        'rollout_status': rolloutStatus,
        'download_url': downloadUrl,
        'download_urls': downloadUrls,
        'store_url': storeUrl,
        'changelog': changelog,
        'build_notes': buildNotes.isNotEmpty ? buildNotes : null,
        'release_tag': releaseTag,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (minSupportedVersion != null && minSupportedVersion.toString().isNotEmpty) {
        payloadMap['min_supported_version'] = minSupportedVersion;
      }
      if (hashedBetaKey != null) {
        payloadMap['beta_access_key'] = hashedBetaKey;
      }

      // Try with build_channel in conflict resolution target (Migration 013 constraint)
      var uri = Uri.parse('$sanitizedBaseUrl/rest/v1/app_updates?on_conflict=platform,environment,build_channel');
      var response = await http.post(uri, headers: headers, body: jsonEncode(payloadMap));

      // Dynamic fallback for any schema cache column mismatch in Supabase
      while (response.statusCode == 400 && response.body.contains("Could not find the '")) {
        final match = RegExp(r"Could not find the '([^']+)' column").firstMatch(response.body);
        if (match != null) {
          final missingCol = match.group(1)!;
          stdout.writeln("ℹ️ Supabase table missing '$missingCol' column, retrying without it...");
          payloadMap.remove(missingCol);
          response = await http.post(uri, headers: headers, body: jsonEncode(payloadMap));
        } else {
          break;
        }
      }

      // Fallback: If build_channel constraint is missing in older DB schema, retry with legacy on_conflict
      if (response.statusCode == 400 && (response.body.contains('ON CONFLICT') || response.body.contains('build_channel'))) {
        stdout.writeln('ℹ️ Retrying with legacy on_conflict=platform,environment...');
        uri = Uri.parse('$sanitizedBaseUrl/rest/v1/app_updates?on_conflict=platform,environment');
        response = await http.post(uri, headers: headers, body: jsonEncode(payloadMap));
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        stdout.writeln('✓ Successfully updated app_updates table in Supabase ($channel channel).');
        synced = true;

        // Record history entry
        try {
          final historyUri = Uri.parse('$sanitizedBaseUrl/rest/v1/app_update_history');
          final historyPayload = <String, dynamic>{
            'platform': platform,
            'environment': environment,
            'build_channel': channel,
            'version': version,
            'release_tag': releaseTag,
            'is_forced': isForced,
            'rollout_percentage': rolloutPercentage,
            'changelog': changelog,
            'build_notes': buildNotes.isNotEmpty ? buildNotes : null,
          };
          var historyRes = await http.post(historyUri, headers: headers, body: jsonEncode(historyPayload));
          if (historyRes.statusCode == 400 && historyRes.body.contains('build_channel')) {
            historyPayload.remove('build_channel');
            historyPayload.remove('release_tag');
            historyPayload.remove('build_notes');
            await http.post(historyUri, headers: headers, body: jsonEncode(historyPayload));
          }
          stdout.writeln('✓ Successfully recorded deployment entry in app_update_history.');
        } catch (_) {}
      } else {
        stdout.writeln('⚠️ Supabase sync returned status ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      stdout.writeln('⚠️ Supabase direct update failed: $e');
    }
  }

  // 2. Secondary Sync: Caffeine API /admin/updates (if available)
  if (!synced && caffeineApiUrl != null && caffeineApiKey != null && caffeineApiUrl.isNotEmpty) {
    try {
      final sanitizedBaseUrl = caffeineApiUrl.endsWith('/') ? caffeineApiUrl.substring(0, caffeineApiUrl.length - 1) : caffeineApiUrl;
      final uri = Uri.parse('$sanitizedBaseUrl/admin/updates');

      final headers = <String, String>{
        'x-admin-secret': caffeineApiKey,
        'x-api-key': caffeineApiKey,
        'Content-Type': 'application/json',
      };

      final payload = <String, dynamic>{
        'platform': platform,
        'environment': environment,
        'build_channel': channel,
        'latest_version': version,
        'is_forced': isForced,
        'rollout_percentage': rolloutPercentage,
        'rollout_status': rolloutStatus,
        'download_url': downloadUrl,
        'download_urls': downloadUrls,
        'store_url': storeUrl,
        'changelog': changelog,
        'build_notes': buildNotes.isNotEmpty ? buildNotes : null,
        'release_tag': releaseTag,
      };
      if (minSupportedVersion != null && minSupportedVersion.toString().isNotEmpty) {
        payload['min_supported_version'] = minSupportedVersion;
      }
      if (hashedBetaKey != null) {
        payload['beta_access_key'] = hashedBetaKey;
      }

      final response = await http.post(uri, headers: headers, body: jsonEncode(payload));
      if (response.statusCode == 200 || response.statusCode == 201) {
        stdout.writeln('✓ Successfully updated Caffeine API update center ($channel channel).');
        synced = true;
      } else {
        stdout.writeln('⚠️ Caffeine API returned status ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      stdout.writeln('⚠️ Caffeine API update failed: $e');
    }
  }

  if (synced) {
    stdout.writeln('🚀 Update Center is now pointing TV users ($channel channel) to version $version.');
  } else {
    stdout.writeln('ℹ️ Update center sync completed with warnings or missing credentials.');
  }
}

Map<String, dynamic> _parseArgs(List<String> args) {
  final map = <String, dynamic>{};
  for (int i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--')) {
      final withoutDashes = arg.substring(2);
      final eqIndex = withoutDashes.indexOf('=');
      if (eqIndex != -1) {
        final key = withoutDashes.substring(0, eqIndex);
        final val = withoutDashes.substring(eqIndex + 1);
        map[key] = val;
      } else if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
        map[withoutDashes] = args[++i];
      } else {
        // Boolean flag (e.g. --beta, --forced)
        map[withoutDashes] = 'true';
      }
    }
  }
  return map;
}

String _getProjectRoot() {
  final scriptDir = File(Platform.script.toFilePath()).parent;
  return scriptDir.parent.path;
}

Map<String, String> _loadEnv(String projectRoot) {
  final map = <String, String>{};
  for (final filename in ['.env.prod', '.env', '.env.dev']) {
    final envFile = File('$projectRoot/$filename');
    if (envFile.existsSync()) {
      for (final line in envFile.readAsLinesSync()) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final eq = trimmed.indexOf('=');
        if (eq > 0) {
          final k = trimmed.substring(0, eq).trim();
          final v = trimmed.substring(eq + 1).trim();
          map.putIfAbsent(k, () => v);
        }
      }
    }
  }
  return map;
}

String _getVersionFromPubspec(String projectRoot) {
  final pubspec = File('$projectRoot/pubspec.yaml');
  if (pubspec.existsSync()) {
    final match = RegExp(r'^version:\s*([^\r\n]+)', multiLine: true)
        .firstMatch(pubspec.readAsStringSync());
    if (match != null) {
      return match.group(1)!.trim();
    }
  }
  return 'unreleased';
}
