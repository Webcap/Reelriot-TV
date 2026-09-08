import 'package:reelriot_tv/services/api_service.dart';
import 'package:flutter/material.dart';

class QualityUtils {
  static final Map<String, String?> _cache = {};
  static final Map<String, Future<String?>> _pendingRequests = {};

  /// Clears the in-memory cache and any pending requests.
  static void clearCache() {
    _cache.clear();
    _pendingRequests.clear();
  }

  static String? getQualityBadgeSync({
    int? mediaId,
    required String? releaseDate,
    required bool isMovie,
  }) {
    if (!isMovie) return 'HD';

    if (mediaId != null) {
      final cacheKey = 'movie:$mediaId';
      if (_cache.containsKey(cacheKey) && _cache[cacheKey] != null) {
        return _cache[cacheKey];
      }
    }

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
  /// Uses in-memory cache and in-flight request deduplication to prevent
  /// duplicate network requests across screens and simultaneously rendered cards.
  static Future<String?> getQualityBadgeAsync({
    required int mediaId,
    required String? releaseDate,
    required bool isMovie,
  }) async {
    // TV shows are always HD
    if (!isMovie) return 'HD';

    final mediaType = isMovie ? 'movie' : 'tv';
    final cacheKey = '$mediaType:$mediaId';

    // 1. Return from cache if already resolved
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    // 2. Return in-flight Future if request is already ongoing (prevents thundering herd)
    if (_pendingRequests.containsKey(cacheKey)) {
      return _pendingRequests[cacheKey];
    }

    // Fallback sync estimate while awaiting or on network failure
    final syncQuality = getQualityBadgeSync(
      mediaId: mediaId,
      releaseDate: releaseDate,
      isMovie: isMovie,
    );

    final future = () async {
      try {
        final serverQuality = await ApiService().fetchMediaQuality(mediaType, mediaId);
        if (serverQuality != null && serverQuality.isNotEmpty) {
          _cache[cacheKey] = serverQuality;
          return serverQuality;
        }
      } catch (e) {
        debugPrint('[QualityUtils] Error resolving quality for $cacheKey: $e');
      }

      // Return sync estimate on failure without poisoning cache so it can retry
      return syncQuality;
    }();

    _pendingRequests[cacheKey] = future;
    try {
      return await future;
    } finally {
      _pendingRequests.remove(cacheKey);
    }
  }
}
