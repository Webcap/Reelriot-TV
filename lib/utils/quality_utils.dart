import 'package:reelriot_tv/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class QualityUtils {
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
      return diffDays <= 30 ? 'CAM' : 'HD';
    } catch (e) {
      debugPrint('[QualityUtils] Error parsing date: $e');
      return null;
    }
  }

  /// Fetches the quality badge, including checking for Supabase overrides.
  static Future<String?> getQualityBadgeAsync({
    required int mediaId,
    required String? releaseDate,
    required bool isMovie,
  }) async {
    // 1. TV shows are always HD for now
    if (!isMovie) return 'HD';

    // 2. Check for manual override in Supabase
    try {
      final response = await Supabase.instance.client
          .from('media_quality_overrides')
          .select('quality')
          .eq('media_id', mediaId.toString())
          .maybeSingle();
      if (response != null && response['quality'] != null) {
        return response['quality'] as String;
      }
    } catch (e) {
      // Silent fail for overrides
    }

    // 3. Fallback to synchronous logic
    final syncQuality = getQualityBadgeSync(releaseDate: releaseDate, isMovie: isMovie);
    
    // 4. If it's a movie and marked as CAM, check for digital release on TMDB
    if (isMovie && syncQuality == 'CAM') {
      final isDigital = await ApiService().isDigitalRelease(mediaId);
      if (isDigital) return 'HD';
    }

    return syncQuality;
  }
}
