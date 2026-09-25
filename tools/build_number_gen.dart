// ignore_for_file: avoid_print
import 'dart:io';

/// Build Number & Version Generator for ReelRiot TV.
///
/// Features:
/// - Auto-increment build number (+1)
/// - Supports SemVer (e.g. 1.0.0+X) and CalVer (YYYY.MM.DD+X)
/// - Git commit-count based build number option
/// - Timestamp based build number option
/// - Updates pubspec.yaml atomically
///
/// Usage:
///   dart run tools/build_number_gen.dart                 # Increments build number by +1 (keeps version name)
///   dart run tools/build_number_gen.dart --calver        # Updates version name to CalVer (YYYY.MM.DD) & increments build
///   dart run tools/build_number_gen.dart --git           # Sets build number to git commit count
///   dart run tools/build_number_gen.dart --timestamp     # Sets build number to timestamp
///   dart run tools/build_number_gen.dart --build 15      # Sets build number explicitly
///   dart run tools/build_number_gen.dart --version 1.0.1 # Sets version name explicitly
///   dart run tools/build_number_gen.dart --sync          # Reads and prints current version without writing
///   dart run tools/build_number_gen.dart --dry-run       # Previews changes without modifying files

void main(List<String> args) {
  File pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    pubspecFile = File('../pubspec.yaml');
    if (!pubspecFile.existsSync()) {
      stderr.writeln('Error: pubspec.yaml not found. Please run from project root.');
      exit(1);
    }
  }

  final pubspecContent = pubspecFile.readAsStringSync();
  final versionRegex = RegExp(r'^version:\s*([^\s+]+)(?:\+(\d+))?', multiLine: true);
  final match = versionRegex.firstMatch(pubspecContent);

  if (match == null) {
    stderr.writeln('Error: Could not find valid "version:" entry in pubspec.yaml');
    exit(1);
  }

  final currentVersionName = match.group(1) ?? '1.0.0';
  final currentBuildNumber = int.tryParse(match.group(2) ?? '1') ?? 1;

  // Parse CLI flags
  bool isDryRun = args.contains('--dry-run');
  bool isSyncOnly = args.contains('--sync') || args.contains('--sync-only');
  bool useGit = args.contains('--git');
  bool useTimestamp = args.contains('--timestamp');
  bool useCalVer = args.contains('--calver');

  String? customVersion;
  int? customBuild;

  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--version' || args[i] == '-v') {
      if (i + 1 < args.length) customVersion = args[i + 1];
    } else if (args[i] == '--build' || args[i] == '-b') {
      if (i + 1 < args.length) customBuild = int.tryParse(args[i + 1]);
    } else if (args[i] == '--help' || args[i] == '-h') {
      _printHelp();
      return;
    }
  }

  if (isSyncOnly) {
    final fullVersion = match.group(2) != null
        ? '$currentVersionName+$currentBuildNumber'
        : currentVersionName;
    print(fullVersion);
    return;
  }

  // Calculate new version name
  String newVersionName;
  if (customVersion != null) {
    newVersionName = customVersion;
  } else if (useCalVer) {
    final now = DateTime.now();
    final yyyy = now.year.toString();
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    newVersionName = '$yyyy.$mm.$dd';
  } else {
    newVersionName = currentVersionName;
  }

  // Calculate new build number
  int newBuildNumber;
  if (customBuild != null) {
    newBuildNumber = customBuild;
  } else if (useGit) {
    newBuildNumber = _getGitCommitCount() ?? (currentBuildNumber + 1);
  } else if (useTimestamp) {
    final now = DateTime.now();
    final y = (now.year % 10).toString();
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    newBuildNumber = int.tryParse('$y$mm$dd$hh$min') ?? (currentBuildNumber + 1);
  } else {
    newBuildNumber = currentBuildNumber + 1;
  }

  final newFullVersion = '$newVersionName+$newBuildNumber';
  final oldFullVersion = match.group(2) != null
      ? '$currentVersionName+$currentBuildNumber'
      : currentVersionName;

  print('========================================');
  print('ReelRiot TV Build Generator');
  print('========================================');
  print('Previous Version : $oldFullVersion');
  print('New Version      : $newFullVersion');
  print('Version Name     : $newVersionName');
  print('Build Number     : $newBuildNumber');
  print('Dry Run          : $isDryRun');
  print('========================================');

  if (isDryRun) {
    print('[Dry Run] No files modified.');
    return;
  }

  // Update pubspec.yaml
  final updatedPubspec = pubspecContent.replaceFirst(
    versionRegex,
    'version: $newFullVersion',
  );
  pubspecFile.writeAsStringSync(updatedPubspec);
  print('Updated pubspec.yaml -> version: $newFullVersion');
  print('\nSuccess! Build version set to $newFullVersion');
}

int? _getGitCommitCount() {
  try {
    final result = Process.runSync('git', ['rev-list', '--count', 'HEAD']);
    if (result.exitCode == 0) {
      return int.tryParse(result.stdout.toString().trim());
    }
  } catch (_) {}
  return null;
}

void _printHelp() {
  print('''
ReelRiot TV Build Number & Version Generator

Usage:
  dart run tools/build_number_gen.dart [options]

Options:
  --help, -h          Show this help message
  --dry-run           Preview version changes without writing to files
  --sync              Print current version from pubspec.yaml without incrementing
  --calver            Update version name with today's CalVer date (YYYY.MM.DD)
  --version, -v <val> Specify custom version name (e.g. 1.0.1 or 2026.09.08)
  --build, -b <num>   Specify custom build number integer (e.g. 2, 100)
  --git               Use git commit count as build number
  --timestamp         Use timestamp (YMMddHHmm) as build number

Default behavior (no args):
  Increments build number by +1 (e.g. 1.0.0+1 -> 1.0.0+2), preserving version name.
''');
}
