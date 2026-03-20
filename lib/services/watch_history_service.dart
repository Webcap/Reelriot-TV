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
    int? episodeId,
    String? episodeName,
    required Duration position,
    required Duration duration,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final now = DateTime.now().toIso8601String();
      final elapsed = position.inSeconds;
      final remaining = (duration - position).inSeconds;

      String? title;
      String? posterPath;
      String? backdropPath;
      String? overview;
      int? id;
      int? releaseYear;

      if (isMovie) {
        if (item is MovieDetail) {
          id = item.id;
          title = item.title;
          posterPath = item.posterPath;
          backdropPath = item.backdropPath;
          overview = item.overview;
          releaseYear = item.releaseDate != null && item.releaseDate!.length >= 4 
              ? int.tryParse(item.releaseDate!.substring(0, 4)) 
              : null;
        } else if (item is MovieListItem) {
          id = item.id;
          title = item.title;
          posterPath = item.posterPath;
          backdropPath = item.backdropPath;
          overview = item.overview;
          releaseYear = item.releaseDate != null && item.releaseDate!.length >= 4 
              ? int.tryParse(item.releaseDate!.substring(0, 4)) 
              : null;
        } else {
          debugPrint('[WatchHistory] ⚠️ Item is not MovieDetail or MovieListItem, cannot save movie progress.');
          return;
        }
      } else {
        if (item is Map) {
          debugPrint('[WatchHistory] ℹ️ Item is a Map (likely Live Stream), skipping watch history for now.');
          return;
        }
        
        if (item is TvShowDetail) {
          id = item.id;
          title = item.name;
          posterPath = item.posterPath;
          backdropPath = item.backdropPath;
          overview = item.overview;
        } else if (item is MovieListItem) {
          id = item.id;
          title = item.title;
          posterPath = item.posterPath;
          backdropPath = item.backdropPath;
          overview = item.overview;
        } else {
           debugPrint('[WatchHistory] ⚠️ Item is not TvShowDetail or MovieListItem, cannot save show progress.');
           return;
        }
      }

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
          if (row['id'] != null) rowIdsToDelete.add(row['id']);
        }
      }

      if (isMovie) {
        movies.removeWhere((m) => (m as Map)['id'] == id);
        movies.insert(0, {
          'id': id,
          'title': title,
          'poster_path': posterPath,
          'backdrop_path': backdropPath,
          'overview': overview,
          'release_year': releaseYear,
          'elapsed': elapsed,
          'remaining': remaining,
          'date_watched': now,
        });
      } else {
        tvShows.removeWhere((t) {
          final m = t as Map;
          final currentId = m['series_id'] ?? m['id'];
          return currentId == id && 
                 m['season_num'] == season && 
                 m['episode_num'] == episode;
        });
        tvShows.insert(0, {
          'id': episodeId ?? id,
          'series_name': title,
          'episode_name': episodeName,
          'poster_path': posterPath,
          'backdrop_path': backdropPath,
          'season_num': season,
          'episode_num': episode,
          'elapsed': elapsed,
          'remaining': remaining,
          'date_added': now,
          'series_id': id,
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
        final sId = m['series_id'] ?? m['id'];
        return seenTvKeys.add('${sId}_${m['season_num']}_${m['episode_num']}');
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

  Future<void> markAsComplete({
    required dynamic item,
    required bool isMovie,
    int? season,
    int? episode,
    int? episodeId,
    String? episodeName,
  }) async {
    // We use a dummy 1-hour duration to mark as fully watched
    const duration = Duration(hours: 1);
    await saveProgress(
      item: item,
      isMovie: isMovie,
      season: season,
      episode: episode,
      episodeId: episodeId,
      episodeName: episodeName,
      position: duration,
      duration: duration,
    );
  }

  Future<void> removeFromHistory({
    required int id,
    required bool isMovie,
    int? season,
    int? episode,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final res = await _supabase.from('watch_history').select().eq('user_id', user.id);
      if (res.isEmpty) return;

      List<dynamic> movies = [];
      List<dynamic> tvShows = [];
      for (var row in res) {
        movies.addAll(row['movies'] as List? ?? []);
        tvShows.addAll(row['tv_shows'] as List? ?? []);
      }

      if (isMovie) {
        movies.removeWhere((m) => (m as Map)['id'] == id);
      } else {
        tvShows.removeWhere((t) {
          final m = t as Map;
          final currentId = m['series_id'] ?? m['id'];
          if (season != null && episode != null) {
            return currentId == id && m['season_num'] == season && m['episode_num'] == episode;
          }
          return currentId == id;
        });
      }

      await _supabase.from('watch_history').upsert({
        'user_id': user.id,
        'movies': movies,
        'tv_shows': tvShows,
        'updated_at': DateTime.now().toIso8601String(),
      });
      debugPrint('[WatchHistory] 🗑️ Removed $id from history');
    } catch (e) {
      debugPrint('[WatchHistory] ❌ Error removing from history: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getHistory({String? mediaType, bool includeCompleted = false}) async {
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

      // Final deduplication: Keep only the absolute latest entry for each series or movie.
      final seenSeriesIds = <int>{};
      final seenMovieIds = <int>{};
      
      final dedupedItems = <dynamic>[];
      for (final item in rawItems) {
        final m = item as Map;
        final isTv = m.containsKey('series_name');
        
        if (isTv) {
          final sId = (m['series_id'] ?? m['id']) as int;
          if (seenSeriesIds.add(sId)) {
            dedupedItems.add(item);
          }
        } else {
          final mId = (m['id']) as int;
          if (seenMovieIds.add(mId)) {
            dedupedItems.add(item);
          }
        }
      }

      // Filter out completed (>= 90% like mobile) unless includeCompleted is true
      final items = includeCompleted ? dedupedItems : dedupedItems.where((item) {
        final m = item as Map;
        final elapsed = m['elapsed'] as int? ?? 0;
        final remaining = m['remaining'] as int? ?? 0;
        final total = elapsed + remaining;
        if (total <= 0) return true;
        return (elapsed / total) < 0.9;
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
    final info = await getWatchProgressInfo(mediaId, isMovie, season: season, episode: episode);
    return info?['elapsed'] as Duration?;
  }

  Future<Map<String, dynamic>?> getWatchProgressInfo(int mediaId, bool isMovie, {int? season, int? episode}) async {
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
      
      Map? match;
      if (isMovie) {
        match = allItems.firstWhere(
          (m) => (m as Map)['id'] == mediaId,
          orElse: () => null,
        );
      } else {
        match = allItems.firstWhere(
          (t) {
            final m = t as Map;
            final currentId = m['series_id'] ?? m['id'];
            return currentId == mediaId && m['season_num'] == season && m['episode_num'] == episode;
          },
          orElse: () => null,
        );
      }

      if (match != null) {
        final elapsed = match['elapsed'] as int? ?? 0;
        final remaining = match['remaining'] as int? ?? 0;
        return {
          'elapsed': Duration(seconds: elapsed),
          'remaining': Duration(seconds: remaining),
          'is_finished': (elapsed + remaining) > 0 && (elapsed / (elapsed + remaining)) >= 0.9,
        };
      }
    } catch (e) {
      debugPrint('[WatchHistory] ❌ Error fetching progress info: $e');
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
      
      final matches = allTvShows.where((t) {
        final currentId = (t as Map)['series_id'] ?? t['id'];
        return currentId == tvId;
      }).toList();
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

  /// Returns a list of unique TV shows the user has recently watched.
  Future<List<Map<String, dynamic>>> getRecentlyWatchedShows() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    try {
      final res = await _supabase
          .from('watch_history')
          .select('tv_shows')
          .eq('user_id', user.id);

      if (res.isEmpty) return [];

      final allTvShows = <dynamic>[];
      for (var row in res) {
        allTvShows.addAll(row['tv_shows'] as List? ?? []);
      }

      // Sort by date_added newest first
      allTvShows.sort((a, b) {
        final da = (a as Map)['date_added'] as String? ?? '';
        final db = (b as Map)['date_added'] as String? ?? '';
        return db.compareTo(da);
      });

      final seenSeriesIds = <int>{};
      final shows = <Map<String, dynamic>>[];

      for (var t in allTvShows) {
        final m = t as Map;
        final sId = (m['series_id'] ?? m['id']) as int;
        if (seenSeriesIds.add(sId)) {
          shows.add({
            'id': sId,
            'name': m['series_name'],
            'poster_path': m['poster_path'],
            'backdrop_path': m['backdrop_path'],
            'date_added': m['date_added'],
          });
        }
      }

      return shows;
    } catch (e) {
      debugPrint('[WatchHistory] ❌ Error fetching recently watched shows: $e');
      return [];
    }
  }
}
