import 'package:reelriot_tv/services/api_service.dart';
import 'package:flutter/material.dart';

class QualityUtils {
  static final Map<String, String> _cache = {};

  static String? getQualityBadgeSync({
    required String? releaseDate,
    required bool isMovie,
  }) {
    if (!isMovie) return 'HD';
    if (releaseDate == null || releaseDate.isEmpty) return null;

    try {
      final release = DateTime.parse(releaseDate);
      final now = DateTime.now();

      if (release.isAfter(now)) return 'SOON';

      final diffDays = now.difference(release).inDays;
      // 90-day CAM window aligned with caffeine-api standard
      return diffDays < 90 ? 'CAM' : 'HD';
    } catch (e) {
      debugPrint('[QualityUtils] Error parsing date: $e');
      return null;
    }
  }

  /// Fetches the quality badge from the centralized Caffeine API.
  /// Uses in-memory cache to prevent duplicate requests across screens and lists.
  static Future<String?> getQualityBadgeAsync({
    required int mediaId,
    required String? releaseDate,
    required bool isMovie,
  }) async {
    // TV shows are always HD
    if (!isMovie) return 'HD';

    final mediaType = isMovie ? 'movie' : 'tv';
    final cacheKey = '$mediaType:$mediaId';

    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    // Fallback sync estimate while awaiting or on failure
    final syncQuality = getQualityBadgeSync(releaseDate: releaseDate, isMovie: isMovie);

    try {
      final serverQuality = await ApiService().fetchMediaQuality(mediaType, mediaId);
      if (serverQuality != null && serverQuality.isNotEmpty) {
        _cache[cacheKey] = serverQuality;
        return serverQuality;
      }
    } catch (e) {
      debugPrint('[QualityUtils] Error resolving quality for $cacheKey: $e');
    }

    if (syncQuality != null) {
      _cache[cacheKey] = syncQuality;
    }
    return syncQuality;
  }
}
