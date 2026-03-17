import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:caffeine_core/caffeine_core.dart';
import 'package:flutter/foundation.dart';

class WatchHistoryService {
  final _supabase = Supabase.instance.client;

  Future<void> saveProgress({
    required dynamic item,
    required bool isMovie,
    int? season,
    int? episode,
    required Duration position,
    required Duration duration,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final mediaId = isMovie ? (item as MovieDetail).id : (item as TvShowDetail).id;
    final title = isMovie ? (item as MovieDetail).title : (item as TvShowDetail).name;
    final posterPath = isMovie ? (item as MovieDetail).posterPath : (item as TvShowDetail).posterPath;
    final backdropPath = isMovie ? (item as MovieDetail).backdropPath : (item as TvShowDetail).backdropPath;
    final overview = isMovie ? (item as MovieDetail).overview : (item as TvShowDetail).overview;

    // Mark as completed when >= 90% watched
    final pct = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;
    final completed = pct >= 0.9;

    try {
      debugPrint('[WatchHistory] 💾 Saving progress for $title (ID: $mediaId) at ${position.inSeconds}s${completed ? ' [COMPLETED]' : ''}');
      await _supabase.from('watch_history').upsert({
        'user_id': user.id,
        'media_id': mediaId,
        'type': isMovie ? 'movie' : 'tv',
        'title': title,
        'poster_path': posterPath,
        'backdrop_path': backdropPath,
        'overview': overview,
        'season': season,
        'episode': episode,
        'position_ms': position.inMilliseconds,
        'duration_ms': duration.inMilliseconds,
        'completed': completed,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id, media_id, type, season, episode');
      debugPrint('[WatchHistory] ✅ Progress saved successfully');
    } catch (e) {
      debugPrint('[WatchHistory] ❌ Error saving watch history: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getHistory() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    try {
      final res = await _supabase
          .from('watch_history')
          .select()
          .eq('user_id', user.id)
          .neq('completed', true)   // exclude fully-watched items
          .order('updated_at', ascending: false)
          .limit(20);

      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('Error fetching watch history: $e');
      return [];
    }
  }

  Future<Duration?> getSavedProgress(int mediaId, bool isMovie, {int? season, int? episode}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      var query = _supabase
          .from('watch_history')
          .select('position_ms')
          .eq('user_id', user.id)
          .eq('media_id', mediaId)
          .eq('type', isMovie ? 'movie' : 'tv');

      if (!isMovie) {
        query = query.eq('season', season as Object).eq('episode', episode as Object);
      }

      final res = await query.maybeSingle();
      if (res != null && res['position_ms'] != null) {
        return Duration(milliseconds: res['position_ms'] as int);
      }
    } catch (e) {
      debugPrint('Error fetching saved progress: $e');
    }
    return null;
  }
}
