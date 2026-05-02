import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:caffeine_core/caffeine_core.dart';
import 'package:flutter/foundation.dart';

class WatchHistoryService extends ChangeNotifier {
  static final WatchHistoryService _instance = WatchHistoryService._internal();

  factory WatchHistoryService({SupabaseClient? client}) {
    if (client != null) {
      _instance._supabase = client;
    }
    return _instance;
  }

  WatchHistoryService._internal()
      : _supabase = Supabase.instance.client;

  SupabaseClient _supabase;

  // ── Concurrency & Caching ──────────────────────────────────────────
  bool _isSaving = false;
  Map<String, dynamic>? _pendingSave;
  Future<void>? _activeSaveProcess;
  final Map<String, List<Map<String, dynamic>>> _cachedHistory = {};
  final Map<String, DateTime> _lastFetchTime = {};
  
  /// Awaits any active background save processes to complete.
  /// Use this before refreshing history after a player session ends.
  Future<void> waitForPendingSaves() async {
    while (_activeSaveProcess != null) {
      debugPrint('[WatchHistory] ⏳ Waiting for pending saves...');
      await _activeSaveProcess;
    }
  }

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
    if (user == null || item == null) return;


    final saveData = {
      'item': item,
      'isMovie': isMovie,
      'season': season,
      'episode': episode,
      'episodeId': episodeId,
      'episodeName': episodeName,
      'position': position,
      'duration': duration,
    };

    _pendingSave = saveData;

    if (_isSaving) {
      return _activeSaveProcess;
    }

    _isSaving = true;
    _activeSaveProcess = _runSaveLoop();
    return _activeSaveProcess;
  }

  Future<void> _runSaveLoop() async {
    bool changed = false;
    try {
      while (_pendingSave != null) {
        final data = _pendingSave!;
        _pendingSave = null;
        final result = await _executeSave(data);
        if (result) changed = true;
      }
    } finally {
      _isSaving = false;
      _activeSaveProcess = null;
      if (changed) {
        notifyListeners();
      }
    }
  }

  Future<bool> _executeSave(Map<String, dynamic> data) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    try {
      final dynamic item = data['item'];
      final bool isMovie = data['isMovie'];
      final int? season = data['season'];
      final int? episode = data['episode'];
      final String? episodeName = data['episodeName'];
      final Duration position = data['position'];
      final Duration duration = data['duration'];

      final elapsed = position.inMilliseconds;
      final total = duration.inMilliseconds;
      final progress = total > 0 ? (elapsed / total) : 0.0;
      final isFinished = progress >= 0.90; 

      String? title;
      String? posterPath;
      String? backdropPath;
      int? mediaId;

      String? mType;
      if (isMovie) {
        if (item is MovieDetail) {
          mediaId = item.id;
          title = item.title;
          posterPath = item.posterPath;
          backdropPath = item.backdropPath;
          mType = item.mediaType;
        } else if (item is MovieListItem) {
          mediaId = item.id;
          title = item.title;
          posterPath = item.posterPath;
          backdropPath = item.backdropPath;
          mType = item.mediaType;
        } else if (item is Map) {
          final dynamic rawMediaId = item['media_id'] ?? item['id'];
          mediaId = rawMediaId is int ? rawMediaId : int.tryParse(rawMediaId?.toString() ?? '');
          title = item['title'];
          posterPath = item['poster_path'];
          backdropPath = item['backdrop_path'];
          mType = item['mediaType'] ?? item['type'] ?? item['media_type'];
        } else {
          return false;
        }
      } else {
        if (item is TvShowDetail) {
          mediaId = item.id;
          title = item.name;
          posterPath = item.posterPath;
          backdropPath = item.backdropPath;
        } else if (item is TvListItem) {
          mediaId = item.id;
          title = item.name;
          posterPath = item.posterPath;
          backdropPath = item.backdropPath;
        } else if (item is Map) {
          final dynamic rawMediaId = item['media_id'] ?? item['id'];
          mediaId = rawMediaId is int ? rawMediaId : int.tryParse(rawMediaId?.toString() ?? '');
          title = item['name'] ?? item['title'];
          posterPath = item['poster_path'];
          backdropPath = item['backdrop_path'];
          mType = item['mediaType'] ?? item['type'] ?? item['media_type'];
        } else {
          return false;
        }
      }
      
      final bool isSportsTitle = title != null && (title.contains(' at ') || title.contains(' vs '));
      if (mType == 'live' || mediaId == -100 || isSportsTitle) {
        debugPrint('[WatchHistory] ℹ️ Skipping watch history for live/sports content: $title');
        return false;
      }
      
      if (mediaId == null) return false;

      // Only clear cache if we're actually going to save/update something
      _cachedHistory.clear();
      _lastFetchTime.clear();

      final now = DateTime.now().toIso8601String();

      if (isFinished) {
        // --- COMPLETED ---
        if (isMovie) {
          await _supabase.from('continue_watching_history')
            .delete()
            .eq('user_id', user.id)
            .eq('media_type', 'movie')
            .eq('media_id', mediaId);
        } else {
          await _supabase.from('continue_watching_history')
            .delete()
            .eq('user_id', user.id)
            .eq('media_type', 'tv')
            .eq('media_id', mediaId)
            .eq('season_num', season ?? 0)
            .eq('episode_num', episode ?? 0);
        }

        List<dynamic>? watchDates;
        int timesWatched = 1;
        int prevTimeWatchedMs = 0;

        final completionQuery = _supabase.from('completed_watch_history')
            .select()
            .eq('user_id', user.id)
            .eq('media_type', isMovie ? 'movie' : 'tv')
            .eq('media_id', mediaId);

        final res = await (isMovie ? completionQuery : completionQuery.eq('season_num', season ?? 0).eq('episode_num', episode ?? 0)).maybeSingle();
        
        if (res != null) {
          var wDatesRaw = res['watch_dates'];
          if (wDatesRaw is List) {
            watchDates = List.from(wDatesRaw);
          } else {
            watchDates = [];
          }
          final lastWatchedStr = watchDates.isNotEmpty ? watchDates.last as String : '';
          
          timesWatched = (res['times_watched'] as int) + 1;
          prevTimeWatchedMs = res['time_watched_ms'] as int;

          if (lastWatchedStr.isNotEmpty) {
            final lastWatched = DateTime.parse(lastWatchedStr);
            if (DateTime.now().difference(lastWatched).inMinutes < 5) {
              return false; 
            }
          }
        }
        
        watchDates ??= [];
        watchDates.add(now);

        final upsertData = {
          if (res != null && res['id'] != null) 'id': res['id'],
          'user_id': user.id,
          'media_type': isMovie ? 'movie' : 'tv',
          'media_id': mediaId,
          'season_num': season,
          'episode_num': episode,
          'title': title,
          'poster_path': posterPath,
          'backdrop_path': backdropPath,
          'time_watched_ms': prevTimeWatchedMs + elapsed,
          'times_watched': timesWatched,
          'watch_dates': watchDates,
          'updated_at': now,
        };

        await _supabase.from('completed_watch_history').upsert(
          upsertData, 
          onConflict: 'user_id,media_id,season_num,episode_num'
        );
        debugPrint('[WatchHistory] ✅ Marked ${isMovie ? 'Movie' : 'TV Show'} as Completed');

      } else {
        // --- CONTINUE WATCHING ---
        final cwQuery = _supabase.from('continue_watching_history')
            .select()
            .eq('user_id', user.id)
            .eq('media_type', isMovie ? 'movie' : 'tv')
            .eq('media_id', mediaId);
            
        final res = await (isMovie ? cwQuery : cwQuery.eq('season_num', season ?? 0).eq('episode_num', episode ?? 0)).maybeSingle();

        final upsertData = {
          if (res != null && res['id'] != null) 'id': res['id'],
          'user_id': user.id,
          'media_type': isMovie ? 'movie' : 'tv',
          'media_id': mediaId,
          'season_num': season,
          'episode_num': episode,
          'title': title,
          'episode_name': episodeName,
          'poster_path': posterPath,
          'backdrop_path': backdropPath,
          'elapsed_ms': elapsed,
          'duration_ms': total,
          'updated_at': now,
        };

        await _supabase.from('continue_watching_history')
            .upsert(
              upsertData,
              onConflict: 'user_id,media_id,season_num,episode_num'
            )
            .timeout(const Duration(seconds: 10));
        debugPrint('[WatchHistory] ✅ Saved Continue Watching Progress');
      }

      _cachedHistory.clear();
      _lastFetchTime.clear();
      return true;
    } catch (e) {
      debugPrint('[WatchHistory] ❌ Error in _executeSave: $e');
      return false;
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

  Future<void> markSeasonAsComplete({
    required TvShowDetail item,
    required int season,
    required List<TvEpisode> episodes,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final now = DateTime.now().toIso8601String();
    
    _cachedHistory.clear();
    _lastFetchTime.clear();

    try {
      final List<Map<String, dynamic>> completedUpserts = [];
      
      for (final ep in episodes) {
        completedUpserts.add({
          'user_id': user.id,
          'media_type': 'tv',
          'media_id': item.id,
          'season_num': season,
          'episode_num': ep.episodeNumber,
          'title': item.name,
          'poster_path': item.posterPath,
          'backdrop_path': item.backdropPath,
          'time_watched_ms': 3600000, // 1 hour
          'times_watched': 1,
          'watch_dates': [now],
          'updated_at': now,
        });
      }

      await Future.wait([
        _supabase.from('completed_watch_history').upsert(
          completedUpserts,
          onConflict: 'user_id,media_id,season_num,episode_num'
        ),
        _supabase.from('continue_watching_history')
          .delete()
          .eq('user_id', user.id)
          .eq('media_type', 'tv')
          .eq('media_id', item.id)
          .eq('season_num', season),
      ]);
      
      debugPrint('[WatchHistory] ✅ Marked Season $season as Completed');
    } catch (e) {
      debugPrint('[WatchHistory] ❌ Error in markSeasonAsComplete: $e');
    }
  }

  Future<void> markUntilEpisodeAsComplete({
    required TvShowDetail item,
    required int season,
    required int untilEpisode,
    required List<TvEpisode> allEpisodes,
  }) async {
    final episodesToMark = allEpisodes.where((e) => e.episodeNumber <= untilEpisode).toList();
    await markSeasonAsComplete(item: item, season: season, episodes: episodesToMark);
  }

  Future<void> removeSeasonFromHistory({
    required int id,
    required int season,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      await Future.wait([
        _supabase.from('continue_watching_history')
          .delete()
          .eq('user_id', user.id)
          .eq('media_type', 'tv')
          .eq('media_id', id)
          .eq('season_num', season),
        _supabase.from('completed_watch_history')
          .delete()
          .eq('user_id', user.id)
          .eq('media_type', 'tv')
          .eq('media_id', id)
          .eq('season_num', season),
      ]);
      
      _cachedHistory.clear();
      _lastFetchTime.clear();
      debugPrint('[WatchHistory] 🗑️ Removed Season $season from History');
    } catch (e) {
      debugPrint('[WatchHistory] ❌ Error removing season history: $e');
    }
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
      if (isMovie) {
        await _supabase.from('continue_watching_history')
          .delete()
          .eq('user_id', user.id)
          .eq('media_type', 'movie')
          .eq('media_id', id);
      } else {
        await _supabase.from('continue_watching_history')
          .delete()
          .eq('user_id', user.id)
          .eq('media_type', 'tv')
          .eq('media_id', id)
          .eq('season_num', season ?? 0)
          .eq('episode_num', episode ?? 0);
      }
      
      _cachedHistory.clear();
      _lastFetchTime.clear();
      debugPrint('[WatchHistory] 🗑️ Removed from Continue Watching');
    } catch (e) {
      debugPrint('[WatchHistory] ❌ Error removing: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getHistory({String? mediaType, bool includeCompleted = false, bool forceRefresh = false}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    final cacheKey = mediaType ?? 'all';

    try {
      final lastFetch = _lastFetchTime[cacheKey];
      final cacheAge = lastFetch != null 
          ? DateTime.now().difference(lastFetch) 
          : const Duration(hours: 1);

      if (!forceRefresh && _cachedHistory.containsKey(cacheKey) && cacheAge < const Duration(minutes: 1)) {
        return _cachedHistory[cacheKey]!;
      }

      var cwQuery = _supabase.from('continue_watching_history').select().eq('user_id', user.id);
      if (mediaType != null) {
        cwQuery = cwQuery.eq('media_type', mediaType);
      }
      final cwRes = await cwQuery.order('updated_at', ascending: false);
      
      List<dynamic> completedRes = [];
      if (includeCompleted) {
        var compQuery = _supabase.from('completed_watch_history').select().eq('user_id', user.id);
        if (mediaType != null) {
          compQuery = compQuery.eq('media_type', mediaType);
        }
        completedRes = await compQuery.order('updated_at', ascending: false);
      }

      final normalized = <Map<String, dynamic>>[];

      for (var row in cwRes) {
        normalized.add({
          'type': row['media_type'],
          'media_id': row['media_id'],
          'title': row['title'],
          'series_name': row['media_type'] == 'tv' ? row['title'] : null,
          'season_num': row['season_num'],
          'episode_num': row['episode_num'],
          'episode_name': row['episode_name'],
          'poster_path': row['poster_path'],
          'backdrop_path': row['backdrop_path'],
          'position_ms': row['elapsed_ms'] ?? 0,
          'duration_ms': row['duration_ms'] ?? 0,
          'date_watched': row['updated_at'],
          'date_added': row['updated_at'],
          'id': row['media_id'],
          'is_completed': false,
        });
      }

      for (var row in completedRes) {
        normalized.add({
          'type': row['media_type'],
          'media_id': row['media_id'],
          'title': row['title'],
          'series_name': row['media_type'] == 'tv' ? row['title'] : null,
          'season_num': row['season_num'],
          'episode_num': row['episode_num'],
          'episode_name': null, // We don't store episode name in completed_watch_history yet
          'poster_path': row['poster_path'],
          'backdrop_path': row['backdrop_path'],
          'position_ms': row['time_watched_ms'] ?? 0,
          'duration_ms': row['time_watched_ms'] ?? 0, 
          'date_watched': row['updated_at'],
          'date_added': row['updated_at'],
          'id': row['media_id'],
          'is_completed': true,
        });
      }

      normalized.sort((a, b) => (b['date_watched'] ?? '').compareTo(a['date_watched'] ?? ''));

      final seenSeriesIds = <int>{};
      final seenMovieIds = <int>{};
      final dedupedItems = <Map<String, dynamic>>[];
      
      for (final m in normalized) {
        final isTv = m['type'] == 'tv';
        if (isTv) {
          final sId = m['media_id'] as int;
          if (seenSeriesIds.add(sId)) dedupedItems.add(m);
        } else {
          final mId = m['media_id'] as int;
          if (seenMovieIds.add(mId)) dedupedItems.add(m);
        }
      }

      _cachedHistory[cacheKey] = dedupedItems;
      _lastFetchTime[cacheKey] = DateTime.now();

      return dedupedItems;
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
      var cwQuery = _supabase.from('continue_watching_history')
        .select()
        .eq('user_id', user.id)
        .eq('media_type', isMovie ? 'movie' : 'tv')
        .eq('media_id', mediaId);
      
      if (!isMovie && season != null && episode != null) {
        cwQuery = cwQuery.eq('season_num', season).eq('episode_num', episode);
      }

      final cwRes = await cwQuery.maybeSingle();

      if (cwRes != null) {
        final elapsed = cwRes['elapsed_ms'] as int? ?? 0;
        final remaining = (cwRes['duration_ms'] as int? ?? 0) - elapsed;
        return {
          'elapsed': Duration(milliseconds: elapsed),
          'remaining': Duration(milliseconds: remaining < 0 ? 0 : remaining),
          'is_finished': false,
        };
      }

      var compQuery = _supabase.from('completed_watch_history')
        .select()
        .eq('user_id', user.id)
        .eq('media_type', isMovie ? 'movie' : 'tv')
        .eq('media_id', mediaId);

      if (!isMovie && season != null && episode != null) {
        compQuery = compQuery.eq('season_num', season).eq('episode_num', episode);
      }

      final compRes = await compQuery.maybeSingle();

      if (compRes != null) {
        return {
          'elapsed': Duration.zero,
          'remaining': Duration.zero,
          'is_finished': true,
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
      await _supabase.from('continue_watching_history').delete().eq('user_id', user.id).eq('media_type', mediaType);
      
      _cachedHistory.clear();
      _lastFetchTime.clear();
      debugPrint('[WatchHistory] 🧹 Cleared $mediaType history');
    } catch (e) {
      debugPrint('[WatchHistory] ❌ Error clearing history: $e');
    }
  }

  Future<Map<String, dynamic>?> getLastWatchedEpisodeForShow(int tvId, {bool forceRefresh = false}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final history = await getHistory(mediaType: 'tv', includeCompleted: true, forceRefresh: forceRefresh);
      final matches = history.where((h) => h['media_id'] == tvId).toList();
      if (matches.isEmpty) return null;

      return matches.first;
    } catch (e) {
      debugPrint('[WatchHistory] ❌ Error fetching last watched: $e');
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getRecentlyWatchedShows({bool forceRefresh = false}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    try {
      final history = await getHistory(mediaType: 'tv', includeCompleted: true, forceRefresh: forceRefresh);
      
      final shows = <Map<String, dynamic>>[];
      for (var m in history) {
        shows.add({
          'id': m['media_id'],
          'name': m['title'] ?? m['series_name'],
          'poster_path': m['poster_path'],
          'backdrop_path': m['backdrop_path'],
          'date_added': m['date_added'],
          'season_num': m['season_num'],
          'episode_num': m['episode_num'],
          'episode_name': m['episode_name'],
          'is_completed': m['is_completed'] ?? false,
        });
      }
      return shows;
    } catch (e) {
      debugPrint('[WatchHistory] ❌ Error fetching recently watched shows: $e');
      return [];
    }
  }

  /// Manually clears cache and notifies listeners to trigger a UI refresh.
  void refresh() {
    _cachedHistory.clear();
    _lastFetchTime.clear();
    notifyListeners();
  }
}
