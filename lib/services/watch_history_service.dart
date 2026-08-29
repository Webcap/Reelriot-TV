import 'dart:async';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:caffeine_core/caffeine_core.dart';
import 'package:flutter/foundation.dart';
import 'package:reelriot_tv/services/api_service.dart';

/// Generates a client-side UUID v4, used as a scrobble session_id and as the
/// idempotency key for manual watch events. The backend's own UUID
/// validation accepts this format; an invalid/missing id is simply
/// server-generated instead, so this is a resilience nicety, not a
/// requirement.
String _generateUuidV4() {
  final rand = Random.secure();
  final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int start, int end) =>
      bytes.sublist(start, end).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

class _ActiveScrobbleSession {
  _ActiveScrobbleSession(this.sessionId, this.mediaKey);
  final String sessionId;
  final String mediaKey;
}

/// Watch-history/rewatch tracking, backed by the Caffeine API. Rewatch
/// counts are derived by counting matching playback_history_events rows
/// (via GET /history/watches) — there is no stored "times watched" counter,
/// matching Trakt's own model and the mobile/web clients built this session.
class WatchHistoryService extends ChangeNotifier {
  static final WatchHistoryService _instance = WatchHistoryService._internal();

  factory WatchHistoryService({SupabaseClient? client}) {
    if (client != null) {
      _instance._supabase = client;
    }
    return _instance;
  }

  WatchHistoryService._internal() : _supabase = Supabase.instance.client;

  SupabaseClient _supabase;
  final ApiService _api = ApiService();

  // ── Concurrency & Caching ──────────────────────────────────────────
  bool _isSaving = false;
  Map<String, dynamic>? _pendingSave;
  Future<void>? _activeSaveProcess;
  final Map<String, List<Map<String, dynamic>>> _cachedHistory = {};
  final Map<String, DateTime> _lastFetchTime = {};

  // ── Scrobble session tracking ────────────────────────────────────────
  _ActiveScrobbleSession? _activeSession;

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

  /// Extracts {mediaId, title, posterPath, backdropPath, mediaType} from the
  /// loosely-typed `item` passed by player_screen.dart. Returns null if the
  /// item is unrecognized or represents live/sports content that shouldn't
  /// be tracked.
  Map<String, dynamic>? _extractItemInfo(dynamic item, bool isMovie) {
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
        return null;
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
        return null;
      }
    }

    final bool isSportsTitle = title != null && (title.contains(' at ') || title.contains(' vs '));
    if (mType == 'live' || mediaId == -100 || isSportsTitle) {
      debugPrint('[WatchHistory] ℹ️ Skipping watch history for live/sports content: $title');
      return null;
    }
    if (mediaId == null) return null;

    return {
      'mediaId': mediaId,
      'title': title,
      'posterPath': posterPath,
      'backdropPath': backdropPath,
    };
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

      final info = _extractItemInfo(item, isMovie);
      if (info == null) return false;

      final int mediaId = info['mediaId'];
      final String? title = info['title'];
      final String? posterPath = info['posterPath'];
      final String? backdropPath = info['backdropPath'];

      final elapsed = position.inMilliseconds;
      final total = duration.inMilliseconds;
      final progress = total > 0 ? (elapsed / total) : 0.0;
      final isFinished = progress >= 0.90;

      final mediaKey = '${isMovie ? 'movie' : 'tv'}_${mediaId}_${season ?? 0}_${episode ?? 0}';

      // A different item started saving without the previous one finishing —
      // abandon the old session rather than force-closing it; its last
      // scrobble/progress call already left continue_watching_history at the
      // right resume point.
      if (_activeSession != null && _activeSession!.mediaKey != mediaKey) {
        _activeSession = null;
      }

      final body = <String, dynamic>{
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
        'platform': 'tv',
      };

      _cachedHistory.clear();
      _lastFetchTime.clear();

      if (_activeSession == null) {
        final sessionId = _generateUuidV4();
        final res = await _api.scrobbleStart(user.id, {...body, 'session_id': sessionId});
        _activeSession = _ActiveScrobbleSession((res['session_id'] as String?) ?? sessionId, mediaKey);
      }

      if (isFinished) {
        await _api.scrobbleStop(user.id, {...body, 'session_id': _activeSession!.sessionId});
        _activeSession = null;
        debugPrint('[WatchHistory] ✅ Marked ${isMovie ? 'Movie' : 'TV Show'} as Completed');
      } else {
        await _api.scrobbleProgress(user.id, {...body, 'session_id': _activeSession!.sessionId});
        debugPrint('[WatchHistory] ✅ Saved Continue Watching Progress');
      }

      _cachedHistory.clear();
      _lastFetchTime.clear();

      // Fire-and-forget: don't let the Caffeine API's own watch-stats cache
      // go stale after this save, so the profile screen's stats reflect it
      // promptly instead of waiting out the server cache TTL.
      unawaited(_api.invalidateWatchStatsCache(user.id));

      return true;
    } catch (e) {
      debugPrint('[WatchHistory] ❌ Error in _executeSave: $e');
      return false;
    }
  }

  /// Trakt-style "add a watch": always logs a new watch event, for manual
  /// mark-as-watched actions with no real playback session. [watchedAt]
  /// defaults to now; pass null explicitly via [unknownDate] for "unknown date".
  Future<void> addWatch({
    required dynamic item,
    required bool isMovie,
    int? season,
    int? episode,
    String? episodeName,
    DateTime? watchedAt,
    bool unknownDate = false,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final info = _extractItemInfo(item, isMovie);
    if (info == null) return;

    _cachedHistory.clear();
    _lastFetchTime.clear();

    try {
      await _api.postHistoryWatch(user.id, {
        'event_id': _generateUuidV4(),
        'media_type': isMovie ? 'movie' : 'tv',
        'media_id': info['mediaId'],
        'season_num': season,
        'episode_num': episode,
        'title': info['title'],
        'episode_name': episodeName,
        'poster_path': info['posterPath'],
        'backdrop_path': info['backdropPath'],
        'watched_at': unknownDate ? null : (watchedAt ?? DateTime.now()).toIso8601String(),
        'platform': 'tv',
      });
      debugPrint('[WatchHistory] ✅ Logged a watch for ${info['title']}');
    } catch (e) {
      debugPrint('[WatchHistory] ❌ Error in addWatch: $e');
    }

    _cachedHistory.clear();
    _lastFetchTime.clear();
    notifyListeners();
  }

  /// Simple "mark watched now" entrypoint, kept for existing call sites.
  Future<void> markAsComplete({
    required dynamic item,
    required bool isMovie,
    int? season,
    int? episode,
    int? episodeId,
    String? episodeName,
  }) async {
    await addWatch(
      item: item,
      isMovie: isMovie,
      season: season,
      episode: episode,
      episodeName: episodeName,
      watchedAt: DateTime.now(),
    );
  }

  Future<void> markSeasonAsComplete({
    required TvShowDetail item,
    required int season,
    required List<TvEpisode> episodes,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    _cachedHistory.clear();
    _lastFetchTime.clear();

    try {
      for (final ep in episodes) {
        await _api.postHistoryWatch(user.id, {
          'event_id': _generateUuidV4(),
          'media_type': 'tv',
          'media_id': item.id,
          'season_num': season,
          'episode_num': ep.episodeNumber,
          'title': item.name,
          'poster_path': item.posterPath,
          'backdrop_path': item.backdropPath,
          'watched_at': DateTime.now().toIso8601String(),
          'platform': 'tv',
        });
      }

      await _api.deleteHistory(user.id, {
        'media_type': 'tv',
        'media_id': item.id,
        'season_num': season,
      });

      debugPrint('[WatchHistory] ✅ Marked Season $season as Completed');
    } catch (e) {
      debugPrint('[WatchHistory] ❌ Error in markSeasonAsComplete: $e');
    }

    _cachedHistory.clear();
    _lastFetchTime.clear();
    notifyListeners();
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
      await _api.deleteHistory(user.id, {
        'media_type': 'tv',
        'media_id': id,
        'season_num': season,
      });

      _cachedHistory.clear();
      _lastFetchTime.clear();
      notifyListeners();
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
      await _api.deleteHistory(user.id, {
        'media_type': isMovie ? 'movie' : 'tv',
        'media_id': id,
        if (!isMovie) 'season_num': season ?? 0,
        if (!isMovie) 'episode_num': episode ?? 0,
      });

      _cachedHistory.clear();
      _lastFetchTime.clear();
      notifyListeners();
      debugPrint('[WatchHistory] 🗑️ Removed from history');
    } catch (e) {
      debugPrint('[WatchHistory] ❌ Error removing: $e');
    }
  }

  /// Fetches and normalizes history from the API, with a direct-Supabase
  /// read fallback on failure. Returns the *undeduped* list (one row per
  /// in-progress item, one row per completed play) — callers that want one
  /// entry per series (e.g. [getHistory]) dedupe on top of this.
  Future<List<Map<String, dynamic>>> _fetchRawHistory({
    String? mediaType,
    bool includeCompleted = false,
    bool forceRefresh = false,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    final cacheKey = '${mediaType ?? 'all'}_$includeCompleted';

    final lastFetch = _lastFetchTime[cacheKey];
    final cacheAge = lastFetch != null ? DateTime.now().difference(lastFetch) : const Duration(hours: 1);
    if (!forceRefresh && _cachedHistory.containsKey(cacheKey) && cacheAge < const Duration(minutes: 1)) {
      return _cachedHistory[cacheKey]!;
    }

    List<Map<String, dynamic>> normalized;
    try {
      final data = await _api.getHistory(
        user.id,
        type: mediaType,
        status: includeCompleted ? null : 'in_progress',
      );
      final rows = (data['history'] as List?) ?? [];
      normalized = rows.map((row) {
        final r = row as Map<String, dynamic>;
        return <String, dynamic>{
          'type': r['media_type'],
          'session_id': r['session_id'],
          'media_id': r['id'],
          'title': r['title'],
          'series_name': r['media_type'] == 'tv' ? r['title'] : null,
          'season_num': r['season_num'],
          'episode_num': r['episode_num'],
          'episode_name': r['episode_name'],
          'poster_path': r['poster_path'],
          'backdrop_path': r['backdrop_path'],
          'position_ms': r['elapsed_ms'] ?? 0,
          'duration_ms': r['duration_ms'] ?? 0,
          'date_watched': r['completed_at'] ?? r['updated_at'],
          'date_added': r['started_at'] ?? r['updated_at'],
          'id': r['id'],
          'is_completed': r['completed'] == true,
          'platform': r['platform'] ?? 'tv',
        };
      }).toList();
    } catch (e) {
      debugPrint('[WatchHistory] ⚠️ API history fetch failed, falling back to direct DB: $e');
      normalized = await _fetchRawHistoryFromSupabase(user.id, mediaType: mediaType, includeCompleted: includeCompleted);
    }

    normalized.sort((a, b) => (b['date_watched'] ?? '').compareTo(a['date_watched'] ?? ''));

    _cachedHistory[cacheKey] = normalized;
    _lastFetchTime[cacheKey] = DateTime.now();
    return normalized;
  }

  /// Read-only fallback used when the Caffeine API is unreachable. Reads the
  /// canonical playback_history_events table directly (never the deprecated
  /// completed_watch_history table) — a read fallback can't cause the
  /// counter-drift problems a write fallback would.
  Future<List<Map<String, dynamic>>> _fetchRawHistoryFromSupabase(
    String userId, {
    String? mediaType,
    bool includeCompleted = false,
  }) async {
    try {
      var cwQuery = _supabase.from('continue_watching_history').select().eq('user_id', userId);
      if (mediaType != null) cwQuery = cwQuery.eq('media_type', mediaType);
      final cwRes = await cwQuery.order('updated_at', ascending: false);

      List<dynamic> eventRes = [];
      if (includeCompleted) {
        var eventQuery = _supabase
            .from('playback_history_events')
            .select()
            .eq('user_id', userId)
            .eq('is_completed', true);
        if (mediaType != null) eventQuery = eventQuery.eq('media_type', mediaType);
        eventRes = await eventQuery.order('completed_at', ascending: false);
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

      for (var row in eventRes) {
        normalized.add({
          'type': row['media_type'],
          'session_id': row['id'],
          'media_id': row['media_id'],
          'title': row['title'],
          'series_name': row['media_type'] == 'tv' ? row['title'] : null,
          'season_num': row['season_num'],
          'episode_num': row['episode_num'],
          'episode_name': row['episode_name'],
          'poster_path': row['poster_path'],
          'backdrop_path': row['backdrop_path'],
          'position_ms': row['elapsed_ms'] ?? 0,
          'duration_ms': row['duration_ms'] ?? row['elapsed_ms'] ?? 0,
          'date_watched': row['completed_at'] ?? row['created_at'],
          'date_added': row['started_at'] ?? row['created_at'],
          'id': row['media_id'],
          'is_completed': true,
          'platform': row['platform'] ?? 'tv',
        });
      }

      return normalized;
    } catch (e) {
      debugPrint('[WatchHistory] ❌ Supabase fallback failed: $e');
      return [];
    }
  }

  /// One entry per series/movie (most recent activity), for grid/row display.
  Future<List<Map<String, dynamic>>> getHistory({
    String? mediaType,
    bool includeCompleted = false,
    bool forceRefresh = false,
  }) async {
    final raw = await _fetchRawHistory(mediaType: mediaType, includeCompleted: includeCompleted, forceRefresh: forceRefresh);

    final seenSeriesIds = <int>{};
    final seenMovieIds = <int>{};
    final dedupedItems = <Map<String, dynamic>>[];

    for (final m in raw) {
      final isTv = m['type'] == 'tv';
      final mediaId = m['media_id'];
      if (mediaId is! int) continue;
      if (isTv) {
        if (seenSeriesIds.add(mediaId)) dedupedItems.add(m);
      } else {
        if (seenMovieIds.add(mediaId)) dedupedItems.add(m);
      }
    }

    return dedupedItems;
  }

  Future<Duration?> getSavedProgress(int mediaId, bool isMovie, {int? season, int? episode}) async {
    final info = await getWatchProgressInfo(mediaId, isMovie, season: season, episode: episode);
    return info?['elapsed'] as Duration?;
  }

  Future<Map<String, dynamic>?> getWatchProgressInfo(int mediaId, bool isMovie, {int? season, int? episode}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final raw = await _fetchRawHistory(mediaType: isMovie ? 'movie' : 'tv', includeCompleted: true);
      final match = raw.firstWhere(
        (m) =>
            m['media_id'] == mediaId &&
            (isMovie || (m['season_num'] == season && m['episode_num'] == episode)),
        orElse: () => const {},
      );
      if (match.isEmpty) return null;

      if (match['is_completed'] == true) {
        return {'elapsed': Duration.zero, 'remaining': Duration.zero, 'is_finished': true};
      }

      final elapsed = match['position_ms'] as int? ?? 0;
      final remaining = (match['duration_ms'] as int? ?? 0) - elapsed;
      return {
        'elapsed': Duration(milliseconds: elapsed),
        'remaining': Duration(milliseconds: remaining < 0 ? 0 : remaining),
        'is_finished': false,
      };
    } catch (e) {
      debugPrint('[WatchHistory] ❌ Error fetching progress info: $e');
    }
    return null;
  }

  /// Per-episode progress/completion for one season, used by the TV show
  /// detail screen to render per-episode watched checkmarks.
  Future<List<Map<String, dynamic>>> getSeasonProgress(int tvId, int season) async {
    final raw = await _fetchRawHistory(mediaType: 'tv', includeCompleted: true);
    final Map<int, Map<String, dynamic>> episodeMap = {};

    for (final row in raw) {
      if (row['media_id'] != tvId || row['season_num'] != season) continue;
      final epNum = row['episode_num'] as int? ?? 0;
      episodeMap[epNum] = {
        'media_id': row['media_id'],
        'season_num': row['season_num'],
        'episode_num': epNum,
        'elapsed_ms': row['position_ms'] ?? 0,
        'duration_ms': row['duration_ms'] ?? 0,
        'is_completed': row['is_completed'] == true,
      };
    }

    return episodeMap.values.toList();
  }

  /// Individual logged watch events for one item, most recent first —
  /// powers a "watch history" list UI.
  Future<List<Map<String, dynamic>>> getWatchEvents({
    required int mediaId,
    required bool isMovie,
    int? season,
    int? episode,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    try {
      final data = await _api.getHistoryWatches(
        user.id,
        mediaType: isMovie ? 'movie' : 'tv',
        mediaId: mediaId,
        seasonNum: season,
        episodeNum: episode,
      );
      return List<Map<String, dynamic>>.from((data['watches'] as List?) ?? []);
    } catch (e) {
      debugPrint('[WatchHistory] ❌ Error fetching watch events: $e');
      return [];
    }
  }

  /// Removes a single logged watch; returns the new watch count.
  Future<int> removeWatchEvent(String watchId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return 0;

    try {
      final data = await _api.deleteHistoryWatch(user.id, watchId);
      _cachedHistory.clear();
      _lastFetchTime.clear();
      notifyListeners();
      return (data['watch_count'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('[WatchHistory] ❌ Error removing watch event: $e');
      return 0;
    }
  }

  Future<int> watchCount({required int mediaId, required bool isMovie, int? season, int? episode}) async {
    final events = await getWatchEvents(mediaId: mediaId, isMovie: isMovie, season: season, episode: episode);
    return events.length;
  }

  /// Clears continue-watching for one media type. No backend endpoint is
  /// shaped for this (bulk-by-type without a media_id), so this stays a
  /// direct Supabase delete — a plain row delete with no aggregate/counter
  /// logic, so it doesn't reintroduce the drift problem elsewhere fixed.
  Future<void> clearHistory({required String mediaType}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      await _supabase.from('continue_watching_history').delete().eq('user_id', user.id).eq('media_type', mediaType);

      _cachedHistory.clear();
      _lastFetchTime.clear();
      notifyListeners();
      debugPrint('[WatchHistory] 🧹 Cleared $mediaType history');
    } catch (e) {
      debugPrint('[WatchHistory] ❌ Error clearing history: $e');
    }
  }

  Future<Map<String, dynamic>?> getLastWatchedEpisodeForShow(int tvId, {bool forceRefresh = false}) async {
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
