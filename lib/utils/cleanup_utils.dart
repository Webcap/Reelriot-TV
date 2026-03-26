import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Automatically deletes any .apk files in the temporary directory.
/// Useful for cleaning up update installers after app restart.
Future<void> cleanupUpdateFiles() async {
  try {
    final tempDir = await getTemporaryDirectory();
    if (tempDir.existsSync()) {
      final files = tempDir.listSync();
      for (final file in files) {
        if (file is File && file.path.toLowerCase().endsWith('.apk')) {
          debugPrint('[Cleanup] Deleting update file: ${file.path}');
          await file.delete();
        }
      }
    }
  } catch (e) {
    debugPrint('[Cleanup] Error: $e');
  }
}
