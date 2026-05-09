import 'package:media_kit/media_kit.dart';
import 'package:caffeine_core/caffeine_core.dart' as core;
import 'package:reelriot_tv/services/player/caffeine_player_controller.dart';

class VideoUtils {
  /// Process VTT file timestamps to fix formatting issues
  static String processVttFileTimestamps(String vttContent) {
    if (vttContent.trim().isEmpty) return '';

    final lines = vttContent.split('\n');
    final processedLines = <String>[];

    // Add WEBVTT header if missing
    if (!vttContent.trim().startsWith('WEBVTT')) {
      processedLines.add('WEBVTT\n');
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.contains('-->') && trimmed.length == 23) {
        // MM:SS.mmm --> MM:SS.mmm (23 chars)
        // Convert to HH:MM:SS.mmm --> HH:MM:SS.mmm (29 chars)
        final startTime = trimmed.substring(0, 9);
        final endTime = trimmed.substring(14);
        processedLines.add('00:$startTime --> 00:$endTime');
      } else {
        processedLines.add(line);
      }
    }

    return processedLines.join('\n');
  }

  /// Parse and create subtitle tracks from subtitle links
  static Future<List<CaffeinePlayerSubtitlesSource>> parseSubtitles({
    required List<core.SubtitleLink> subtitles,
    required String defaultLanguage,
    required bool fetchAllLanguages,
    required Future<String?> Function(String) getSubtitleContent,
  }) async {
    final List<CaffeinePlayerSubtitlesSource> subs = [];

    if (subtitles.isEmpty) {
      return subs;
    }

    // 1. Identify which subtitles match the preferred language
    final preferredIndices = <int>{};
    int? bestPreferredIndex;
    for (int i = 0; i < subtitles.length; i++) {
      final lang = (subtitles[i].label ?? '').toLowerCase();
      if (lang.startsWith(defaultLanguage.toLowerCase()) ||
          lang == defaultLanguage.toLowerCase()) {
        preferredIndices.add(i);
        bestPreferredIndex ??= i;
      }
    }

    // 2. If no preferred language found, try to find English as fallback if it wasn't the default
    if (preferredIndices.isEmpty &&
        defaultLanguage.toLowerCase() != 'english') {
      for (int i = 0; i < subtitles.length; i++) {
        if (_isDefaultEnglish(subtitles[i].label ?? '')) {
          preferredIndices.add(i);
          bestPreferredIndex ??= i;
          break; // Just one fallback is enough
        }
      }
    }

    // 3. Fallback to the first one if still nothing
    if (preferredIndices.isEmpty) {
      preferredIndices.add(0);
      bestPreferredIndex = 0;
    }

    // 4. Determine which subtitles to fetch
    final List<int> indicesToFetch = [];
    if (fetchAllLanguages) {
      indicesToFetch.addAll(Iterable.generate(subtitles.length));
    } else {
      // Just fetch the preferred ones (or the fallback)
      indicesToFetch.addAll(preferredIndices);
    }

    // 5. Fetch and process
    for (final i in indicesToFetch) {
      try {
        final url = subtitles[i].file ?? '';
        if (url.isEmpty) continue;

        final content = await getSubtitleContent(url);
        if (content == null) continue;

        final isDefault = subtitles[i].isDefault == true || i == bestPreferredIndex;

        final uriPath =
            Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
        final isSrt =
            uriPath.endsWith('.srt') ||
            (subtitles[i].label ?? '').contains('OpenSubtitles');

        final processedContent = isSrt
            ? content
            : processVttFileTimestamps(content);

        subs.add(
          CaffeinePlayerSubtitlesSource(
            name: subtitles[i].label ?? 'Unknown',
            data: processedContent,
            isDefault: isDefault,
          ),
        );
      } catch (e) {
        continue;
      }
    }

    return subs;
  }

  static bool _isDefaultEnglish(String language) {
    final lower = language.toLowerCase();
    return lower == 'english' || lower == 'en' || lower.contains('english');
  }
}
