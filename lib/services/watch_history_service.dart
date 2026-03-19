import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:caffeine_core/caffeine_core.dart';
import 'package:flutter/foundation.dart';

class WatchHistoryService {
  final SupabaseClient _supabase;

  WatchHistoryService({SupabaseClient? client}) 
      : _supabase = client ?? Supabase.instance.client;

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
      // 1. Fetch ALL existing rows for this user
      final res = await _supabase
          .from('watch_history')
          .select()
          .eq('user_id', user.id);

      List<dynamic> movies = [];
      List<dynamic> tvShows = [];
      final List<dynamic> rowIdsToDelete = [];

      if (res.isNotEmpty) {
        for (var row in res) {
          movies.addAll(row['movies'] as List? ?? []);
          tvShows.addAll(row['tv_shows'] as List? ?? []);
          // Collect IDs if they exist to clean up later
          if (row['id'] != null) rowIdsToDelete.add(row['id']);
        }
      }

      // 2. Prepare the item and deduplicate lists
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
        tvShows.removeWhere((t) {
          final m = t as Map;
          return m['id'] == show.id && m['season_num'] == season && m['episode_num'] == episode;
        });
        tvShows.insert(0, {
          'id': show.id,
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

      // Sort before deduplication to ensure newest wins
      movies.sort((a, b) {
        final da = (a as Map)['date_watched'] as String? ?? '';
        final db = (b as Map)['date_watched'] as String? ?? '';
        return db.compareTo(da);
      });
      tvShows.sort((a, b) {
        final da = (a as Map)['date_added'] as String? ?? '';
        final db = (b as Map)['date_added'] as String? ?? '';
        return db.compareTo(da);
      });

      // Final deduplication for merging across rows
      final seenMovieIds = <dynamic>{};
      movies = movies.where((m) => seenMovieIds.add((m as Map)['id'])).toList();
      
      final seenTvKeys = <String>{};
      tvShows = tvShows.where((t) {
        final m = t as Map;
        return seenTvKeys.add('${m['id']}_${m['season_num']}_${m['episode_num']}');
      }).toList();

      // 3. Consolidated Upsert
      await _supabase.from('watch_history').upsert({
        'user_id': user.id,
        'movies': movies,
        'tv_shows': tvShows,
        'updated_at': now,
      });

      // 4. Cleanup redundant rows if we found multiple
      if (res.length > 1 && rowIdsToDelete.isNotEmpty) {
        try {
           // To consolidate, we delete the old existing row IDs.
           // Since we already performed a fresh upsert, we can remove the ones we found.
           for (final id in rowIdsToDelete) {
             await _supabase.from('watch_history').delete().eq('id', id);
           }
           debugPrint('[WatchHistory] 🧹 Cleaned up ${rowIdsToDelete.length} redundant rows');
        } catch (e) {
           debugPrint('[WatchHistory] ⚠️ Cleanup failed: $e');
        }
      }

      debugPrint('[WatchHistory] ✅ Progress saved & consolidated for ${isMovie ? 'Movie' : 'TV Show'}');
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
          .eq('user_id', user.id);

      if (res.isEmpty) return [];
      
      List<dynamic> allMovies = [];
      List<dynamic> allTvShows = [];

      for (var row in res) {
        allMovies.addAll(row['movies'] as List? ?? []);
        allTvShows.addAll(row['tv_shows'] as List? ?? []);
      }

      List<dynamic> rawItems = [];
      if (mediaType == 'movie') {
        rawItems = allMovies;
      } else if (mediaType == 'tv') {
        rawItems = allTvShows;
      } else {
        rawItems = [...allMovies, ...allTvShows];
      }

      // Sort before deduplication to ensure newest wins
      rawItems.sort((a, b) {
        final doubleA = (a as Map)['date_watched'] ?? a['date_added'] ?? '';
        final doubleB = (b as Map)['date_watched'] ?? b['date_added'] ?? '';
        return (doubleB as String).compareTo(doubleA as String);
      });

      // Final deduplication for merging across rows
      final seenIds = <String>{};
      rawItems = rawItems.where((item) {
        final m = item as Map;
        final id = m['id'];
        final type = m.containsKey('series_name') ? 'tv' : 'movie';
        final key = type == 'tv' ? '${id}_${m['season_num']}_${m['episode_num']}' : '$id';
        return seenIds.add(key);
      }).toList();

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
        final isTv = m.containsKey('series_name');
        m['type'] = isTv ? 'tv' : 'movie';
        
        // For TV shows, the TMDB ID for the series is either in 'series_id' 
        // or 'id' (if saved by the TV app). Mobile app uses 'series_id'.
        if (isTv) {
          m['media_id'] = m['series_id'] ?? m['id'];
          m['title'] = m['series_name'];
          m['season'] = m['season_num'];
          m['episode'] = m['episode_num'];
        } else {
          m['media_id'] = m['id'];
        }

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
          .eq('user_id', user.id);

      if (res.isEmpty) return null;
      
      List<dynamic> allItems = [];
      for (var row in res) {
        allItems.addAll(row[isMovie ? 'movies' : 'tv_shows'] as List? ?? []);
      }
      
      if (isMovie) {
        final match = allItems.firstWhere(
          (m) => (m as Map)['id'] == mediaId,
          orElse: () => null,
        );
        if (match != null) return Duration(seconds: match['elapsed'] as int? ?? 0);
      } else {
        final match = allItems.firstWhere(
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

  Future<void> clearHistory({required String mediaType}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final column = mediaType == 'movie' ? 'movies' : 'tv_shows';
      await _supabase.from('watch_history').update({column: []}).eq('user_id', user.id);
      debugPrint('[WatchHistory] 🧹 Cleared $mediaType history');
    } catch (e) {
      debugPrint('[WatchHistory] ❌ Error clearing history: $e');
    }
  }

  Future<Map<String, dynamic>?> getLastWatchedEpisodeForShow(int tvId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final res = await _supabase
          .from('watch_history')
          .select('tv_shows')
          .eq('user_id', user.id);

      if (res.isEmpty) return null;
      
      List<dynamic> allTvShows = [];
      for (var row in res) {
        allTvShows.addAll(row['tv_shows'] as List? ?? []);
      }
      
      final matches = allTvShows.where((t) => ((t as Map)['series_id'] ?? t['id']) == tvId).toList();
      if (matches.isEmpty) return null;

      // Sort by date_added to find the absolute last one watched
      matches.sort((a, b) {
        final da = (a as Map)['date_added'] as String? ?? '';
        final db = (b as Map)['date_added'] as String? ?? '';
        return db.compareTo(da);
      });

      return Map<String, dynamic>.from(matches.first as Map);
    } catch (e) {
      debugPrint('[WatchHistory] ❌ Error fetching last watched: $e');
    }
    return null;
  }
}
