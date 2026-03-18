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
    String? episodeName,
    required Duration position,
    required Duration duration,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      // 1. Fetch the user's single flattened row
      final res = await _supabase
          .from('watch_history')
          .select('movies, tv_shows')
          .eq('user_id', user.id)
          .limit(1);

      final data = res.isNotEmpty ? res[0] : null;
      List<dynamic> movies = data?['movies'] as List<dynamic>? ?? [];
      List<dynamic> tvShows = data?['tv_shows'] as List<dynamic>? ?? [];

      // 2. Prepare the item with keys matching mobile schema
      final now = DateTime.now().toIso8601String();
      final elapsed = position.inSeconds;
      final remaining = (duration - position).inSeconds;
      
      if (isMovie) {
        final movie = item as MovieDetail;
        movies.removeWhere((m) => (m as Map)['id'] == movie.id);
        movies.insert(0, {
          'id': movie.id,
          'title': movie.title,
          'poster_path': movie.posterPath,
          'backdrop_path': movie.backdropPath,
          'overview': movie.overview,
          'release_year': movie.releaseDate != null && movie.releaseDate!.length >= 4 
              ? int.tryParse(movie.releaseDate!.substring(0, 4)) 
              : null,
          'elapsed': elapsed,
          'remaining': remaining,
          'date_watched': now,
        });
      } else {
        final show = item as TvShowDetail;
        // Season/Episode detail needs to be found if we only have the show detail
        // But in PlayerScreen we usually have season/episode numbers.
        tvShows.removeWhere((t) {
          final m = t as Map;
          return m['id'] == show.id && m['season_num'] == season && m['episode_num'] == episode;
        });
        tvShows.insert(0, {
          'id': show.id, // Using show ID for consistency with mobile RecentEpisode
          'series_name': show.name,
          'episode_name': episodeName,
          'poster_path': show.posterPath,
          'backdrop_path': show.backdropPath,
          'season_num': season,
          'episode_num': episode,
          'elapsed': elapsed,
          'remaining': remaining,
          'date_added': now,
          'series_id': show.id,
        });
      }

      // 3. Upsert the row
      await _supabase.from('watch_history').upsert({
        'user_id': user.id,
        'movies': movies,
        'tv_shows': tvShows,
        'updated_at': now,
      });

      debugPrint('[WatchHistory] ✅ Progress saved for ${isMovie ? 'Movie' : 'TV Show'} (ID: ${isMovie ? (item as MovieDetail).id : (item as TvShowDetail).id})');
    } catch (e) {
      debugPrint('[WatchHistory] ❌ Error saving progress: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getHistory({String? mediaType}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    try {
      final res = await _supabase
          .from('watch_history')
          .select('movies, tv_shows')
          .eq('user_id', user.id)
          .limit(1);

      if (res.isEmpty) return [];
      
      final data = res[0];
      List<dynamic> rawItems = [];
      
      if (mediaType == 'movie') {
        rawItems = data['movies'] as List<dynamic>? ?? [];
      } else if (mediaType == 'tv') {
        rawItems = data['tv_shows'] as List<dynamic>? ?? [];
      } else {
        // Combined
        rawItems = [
          ...(data['movies'] as List? ?? []),
          ...(data['tv_shows'] as List? ?? []),
        ];
      }

      // Filter out completed (>= 95% like mobile)
      final items = rawItems.where((item) {
        final m = item as Map;
        final elapsed = m['elapsed'] as int? ?? 0;
        final remaining = m['remaining'] as int? ?? 0;
        final total = elapsed + remaining;
        if (total <= 0) return true;
        return (elapsed / total) < 0.95;
      }).toList();

      // Normalize keys for the UI (media_id, type)
      final normalized = items.map((item) {
        final m = Map<String, dynamic>.from(item as Map);
        m['media_id'] = m['id'];
        m['type'] = m.containsKey('series_name') ? 'tv' : 'movie';
        if (m['type'] == 'tv') m['title'] = m['series_name'];
        // position_ms and duration_ms for existing UI compatibility
        m['position_ms'] = (m['elapsed'] as int? ?? 0) * 1000;
        m['duration_ms'] = ((m['elapsed'] as int? ?? 0) + (m['remaining'] as int? ?? 0)) * 1000;
        return m;
      }).toList();

      // Sort by date
      normalized.sort((a, b) {
        final da = a['date_watched'] ?? a['date_added'] ?? '';
        final db = b['date_watched'] ?? b['date_added'] ?? '';
        return db.compareTo(da);
      });

      debugPrint('[WatchHistory] 🔍 Fetched ${normalized.length} items (Filter: $mediaType)');
      return normalized;
    } catch (e) {
      debugPrint('[WatchHistory] ❌ Error fetching history: $e');
      return [];
    }
  }

  Future<Duration?> getSavedProgress(int mediaId, bool isMovie, {int? season, int? episode}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final res = await _supabase
          .from('watch_history')
          .select(isMovie ? 'movies' : 'tv_shows')
          .eq('user_id', user.id)
          .limit(1);

      if (res.isEmpty) return null;
      
      final List<dynamic> items = res[0][isMovie ? 'movies' : 'tv_shows'] ?? [];
      
      if (isMovie) {
        final match = items.firstWhere(
          (m) => (m as Map)['id'] == mediaId,
          orElse: () => null,
        );
        if (match != null) return Duration(seconds: match['elapsed'] as int? ?? 0);
      } else {
        final match = items.firstWhere(
          (t) {
            final m = t as Map;
            return m['id'] == mediaId && m['season_num'] == season && m['episode_num'] == episode;
          },
          orElse: () => null,
        );
        if (match != null) return Duration(seconds: match['elapsed'] as int? ?? 0);
      }
    } catch (e) {
      debugPrint('[WatchHistory] ❌ Error fetching progress: $e');
    }
    return null;
  }
}
