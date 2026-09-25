import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:caffeine_core/caffeine_core.dart' as core;
import 'package:reelriot_tv/constants.dart';
import 'package:reelriot_tv/env.dart';
import 'package:reelriot_tv/services/settings_service.dart';
import 'package:http/http.dart' as http;

class ApiService {
  String get _tmdbKey => tmdbApiKey;
  String get tmdbBaseUrl => tmdbApiBaseUrl;
  String get caffeineBaseUrl => caffeineApiUrl.replaceFirst(RegExp(r'/$'), '');
  String get language => SettingsService().language;
  String get audioLanguage => SettingsService().defaultAudioLanguage;
  String get region => SettingsService().region;
  
  static const String _browserUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  /// Headers for Caffeine API requests — includes Authorization when a key is set.
  Map<String, String> get _caffeineApiHeaders {
    final headers = <String, String>{'User-Agent': _browserUserAgent};
    final key = caffeineApiKey;
    if (key.isNotEmpty) headers['Authorization'] = 'Bearer $key';
    return headers;
  }

  Future<Map<String, dynamic>> loadConfig() async {
    return core.fetchConfig(
      caffeineBaseUrl,
      apiKey: caffeineApiKey,
      platform: 'tv',
      environment: environment,
    );
  }

  /// Fetches the unified discovery feed (Community Trending, AI Picks, etc.)
  Future<Map<String, dynamic>> fetchDiscovery({String? userId, String? mediaType, String? region}) async {
    var url = '$caffeineBaseUrl/v1/discovery';
    final params = <String, String>{};
    if (userId != null && userId != 'null') params['userId'] = userId;
    if (mediaType != null) params['mediaType'] = mediaType;
    if (region != null) params['region'] = region;
    
    if (params.isNotEmpty) {
      final query = Uri(queryParameters: params).query;
      url += '?$query';
    }

    final res = await http.get(Uri.parse(url), headers: _caffeineApiHeaders).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('Failed to load discovery feed: ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Fetches server-computed watch-time stats (minutes watched per media
  /// type) for the given user over the trailing [days] window. Returns
  /// e.g. {'movies': {'minutes': 135}, 'tv': {'minutes': 420}}.
  Future<Map<String, dynamic>> fetchWatchStats(String userId, {int days = 14}) async {
    final url = '$caffeineBaseUrl/v1/user/$userId/watch-stats?days=$days';
    final res = await http.get(Uri.parse(url), headers: _caffeineApiHeaders).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) {
      throw Exception('Failed to load watch stats: ${res.statusCode}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['stats'] as Map<String, dynamic>?) ?? {};
  }

  /// Invalidates the server-side watch-stats cache so the next
  /// [fetchWatchStats] call reflects recently saved progress.
  Future<void> invalidateWatchStatsCache(String userId) async {
    final url = '$caffeineBaseUrl/v1/user/$userId/watch-stats/cache';
    try {
      await http.delete(Uri.parse(url), headers: _caffeineApiHeaders).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[ApiService] ⚠️ Failed to invalidate watch-stats cache: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Watch history: legacy /history (continue-watching progress + removal)
  // ─────────────────────────────────────────────────────────────────────

  /// Upserts continue-watching progress, or marks an item completed and logs
  /// a playback_history_events row when `completed: true` or the elapsed/
  /// duration ratio crosses the server's own completion threshold.
  Future<Map<String, dynamic>> postHistory(String userId, Map<String, dynamic> body) async {
    final url = '$caffeineBaseUrl/v1/user/$userId/history';
    final res = await http
        .post(Uri.parse(url), headers: {..._caffeineApiHeaders, 'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('postHistory failed: ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Removes a single item (movie, or one episode when season_num/episode_num
  /// are included) from continue-watching and playback_history_events.
  Future<void> deleteHistory(String userId, Map<String, dynamic> body) async {
    final url = '$caffeineBaseUrl/v1/user/$userId/history';
    final res = await http
        .delete(Uri.parse(url), headers: {..._caffeineApiHeaders, 'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200 && res.statusCode != 404) {
      throw Exception('deleteHistory failed: ${res.statusCode}');
    }
  }

  /// Unified chronological history: in-progress items plus one row per
  /// completed play (no aggregate counter — count matching rows for a
  /// rewatch count).
  Future<Map<String, dynamic>> getHistory(String userId, {String? type, String? status, int limit = 100}) async {
    final params = <String, String>{'limit': '$limit'};
    if (type != null) params['type'] = type;
    if (status != null) params['status'] = status;
    final query = Uri(queryParameters: params).query;
    final url = '$caffeineBaseUrl/v1/user/$userId/history?$query';
    final res = await http.get(Uri.parse(url), headers: _caffeineApiHeaders).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('getHistory failed: ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Wipes all watch history (continue-watching + completed plays) for the user.
  Future<void> deleteHistoryAll(String userId) async {
    final url = '$caffeineBaseUrl/v1/user/$userId/history/all';
    final res = await http.delete(Uri.parse(url), headers: _caffeineApiHeaders).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('deleteHistoryAll failed: ${res.statusCode}');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Watch history: scrobble lifecycle (real playback tracking)
  // ─────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> scrobbleStart(String userId, Map<String, dynamic> body) async {
    final url = '$caffeineBaseUrl/v1/user/$userId/scrobble/start';
    final res = await http
        .post(Uri.parse(url), headers: {..._caffeineApiHeaders, 'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('scrobbleStart failed: ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> scrobbleProgress(String userId, Map<String, dynamic> body) async {
    final url = '$caffeineBaseUrl/v1/user/$userId/scrobble/progress';
    final res = await http
        .post(Uri.parse(url), headers: {..._caffeineApiHeaders, 'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('scrobbleProgress failed: ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> scrobbleStop(String userId, Map<String, dynamic> body) async {
    final url = '$caffeineBaseUrl/v1/user/$userId/scrobble/stop';
    final res = await http
        .post(Uri.parse(url), headers: {..._caffeineApiHeaders, 'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('scrobbleStop failed: ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ─────────────────────────────────────────────────────────────────────
  // Watch history: /history/watches (Trakt-style manual "add a watch")
  // ─────────────────────────────────────────────────────────────────────

  /// Always logs a new watch event (never upserts) — used for manual
  /// "mark as watched"/rewatch actions with no real playback session.
  Future<Map<String, dynamic>> postHistoryWatch(String userId, Map<String, dynamic> body) async {
    final url = '$caffeineBaseUrl/v1/user/$userId/history/watches';
    final res = await http
        .post(Uri.parse(url), headers: {..._caffeineApiHeaders, 'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('postHistoryWatch failed: ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Lists individual logged watch events for one item, most recent first.
  Future<Map<String, dynamic>> getHistoryWatches(
    String userId, {
    required String mediaType,
    required int mediaId,
    int? seasonNum,
    int? episodeNum,
  }) async {
    final params = <String, String>{'media_type': mediaType, 'media_id': '$mediaId'};
    if (seasonNum != null) params['season_num'] = '$seasonNum';
    if (episodeNum != null) params['episode_num'] = '$episodeNum';
    final query = Uri(queryParameters: params).query;
    final url = '$caffeineBaseUrl/v1/user/$userId/history/watches?$query';
    final res = await http.get(Uri.parse(url), headers: _caffeineApiHeaders).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('getHistoryWatches failed: ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Removes a single logged watch event; returns the new watch count.
  Future<Map<String, dynamic>> deleteHistoryWatch(String userId, String watchId) async {
    final url = '$caffeineBaseUrl/v1/user/$userId/history/watches/$watchId';
    final res = await http.delete(Uri.parse(url), headers: _caffeineApiHeaders).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('deleteHistoryWatch failed: ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// TV App polls this to see if it's been linked.
  Future<http.Response> pollPairing(String code) async {
    final url = Uri.parse('$caffeineBaseUrl/tv/pair?code=${Uri.encodeComponent(code)}');
    return http.get(url, headers: _caffeineApiHeaders).timeout(const Duration(seconds: 10));
  }

  /// Explicitly confirm pairing (usually done from phone/web, but here for completeness).
  ///
  /// Only the confirming device's own access token is needed — the backend
  /// verifies it identifies a real session, then mints the TV an
  /// independent magic-link token via the Admin API rather than forwarding
  /// this device's tokens (see caffeine-api's /tv/pair/confirm).
  Future<http.Response> confirmPairing(String code, String accessToken) async {
    final url = Uri.parse('$caffeineBaseUrl/tv/pair/confirm');
    return http.post(
      url,
      headers: {..._caffeineApiHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'code': code,
        'access_token': accessToken,
      }),
    ).timeout(const Duration(seconds: 10));
  }

  Future<core.MovieListResponse> fetchPopularMovies() async {
    final url = core.Endpoints.popularMoviesUrl(tmdbBaseUrl, _tmdbKey, language);
    return _fetchMovieList(url);
  }

  Future<core.MovieListResponse> fetchTrendingMovies() async {
    final url = core.Endpoints.trendingMoviesUrl(tmdbBaseUrl, _tmdbKey, false, language);
    return _fetchMovieList(url);
  }

  Future<core.MovieListResponse> fetchTopRatedMovies() async {
    final url = core.Endpoints.topRatedMoviesUrl(tmdbBaseUrl, _tmdbKey, language, region: region);
    return _fetchMovieList(url);
  }

  Future<core.MovieListResponse> fetchNowPlayingMovies() async {
    final url = core.Endpoints.nowPlayingMoviesUrl(tmdbBaseUrl, _tmdbKey, language);
    return _fetchMovieList(url);
  }

  Future<core.MovieListResponse> fetchUpcomingMovies() async {
    final url = core.Endpoints.upcomingMoviesUrl(tmdbBaseUrl, _tmdbKey, language);
    return _fetchMovieList(url);
  }

  Future<core.MovieListResponse> fetchMovieRecommendations(int movieId, {int page = 1}) async {
    final url = core.Endpoints.movieRecommendationsUrl(tmdbBaseUrl, _tmdbKey, movieId, page, language);
    return _fetchMovieList(url);
  }

  Future<core.CreditsResponse> fetchMovieCredits(int movieId) async {
    final url = core.Endpoints.movieCreditsUrl(tmdbBaseUrl, _tmdbKey, movieId, language);
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Failed to load movie credits');
    return core.CreditsResponse.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<core.MovieDetail> fetchMovieDetail(int movieId) async {
    final url = core.Endpoints.movieDetailsUrl(tmdbBaseUrl, _tmdbKey, movieId, language);
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Failed to load movie');
    return core.MovieDetail.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<core.MovieCollection> fetchMovieCollection(int collectionId) async {
    final url = core.Endpoints.movieCollectionUrl(tmdbBaseUrl, _tmdbKey, collectionId, language);
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Failed to load movie collection');
    return core.MovieCollection.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<core.TvListResponse> fetchPopularTv() async {
    final url = core.Endpoints.popularTvUrl(tmdbBaseUrl, _tmdbKey, language);
    return _fetchTvList(url);
  }

  Future<core.TvListResponse> fetchTrendingTv() async {
    final url = core.Endpoints.trendingTvUrl(tmdbBaseUrl, _tmdbKey, language);
    return _fetchTvList(url);
  }

  Future<core.TvListResponse> fetchTopRatedTv() async {
    final url = core.Endpoints.topRatedTvUrl(tmdbBaseUrl, _tmdbKey, language);
    return _fetchTvList(url);
  }

  Future<core.TvListResponse> fetchAiringToday() async {
    final url = '$tmdbBaseUrl/tv/airing_today?api_key=$_tmdbKey&language=$language';
    return _fetchTvList(url);
  }

  Future<core.TvListResponse> fetchTvRecommendations(int tvId, {int page = 1}) async {
    final url = core.Endpoints.tvRecommendationsUrl(tmdbBaseUrl, _tmdbKey, tvId, page, language);
    return _fetchTvList(url);
  }

  Future<core.CreditsResponse> fetchTvCredits(int tvId) async {
    final url = core.Endpoints.tvCreditsUrl(tmdbBaseUrl, _tmdbKey, tvId, language);
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Failed to load TV credits');
    return core.CreditsResponse.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<core.TvShowDetail> fetchTvDetail(int tvId) async {
    final url = core.Endpoints.tvDetailsUrl(tmdbBaseUrl, _tmdbKey, tvId, language);
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Failed to load show (Status: ${res.statusCode}, ID: $tvId)');
    return core.TvShowDetail.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<core.TvSeasonDetailResponse> fetchSeasonDetail(int tvId, int seasonNumber) async {
    final url = core.Endpoints.tvSeasonDetailUrl(tmdbBaseUrl, _tmdbKey, tvId, seasonNumber, language);
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Failed to load season (Status: ${res.statusCode}, ID: $tvId, Season: $seasonNumber)');
    return core.TvSeasonDetailResponse.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<core.PersonDetail> fetchPersonDetail(int personId) async {
    final url = core.Endpoints.personDetailsUrl(tmdbBaseUrl, _tmdbKey, personId, language);
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Failed to load person details');
    return core.PersonDetail.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<core.CombinedCreditsResponse> fetchPersonCombinedCredits(int personId) async {
    final url = core.Endpoints.personCombinedCreditsUrl(tmdbBaseUrl, _tmdbKey, personId, language);
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Failed to load combined credits');
    return core.CombinedCreditsResponse.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<String?> fetchMovieExternalIds(int movieId) async {
    final url = '$tmdbBaseUrl/movie/$movieId/external_ids?api_key=$_tmdbKey';
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body);
    return data['imdb_id'];
  }

  Future<String?> fetchTvExternalIds(int tvId) async {
    final url = '$tmdbBaseUrl/tv/$tvId/external_ids?api_key=$_tmdbKey';
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body);
    return data['imdb_id'];
  }

  Future<core.ProviderStreamResponse> fetchMovieStream(int movieId, {String provider = 'vidsrcsu'}) async {
    final url = core.Endpoints.streamMovieUrl(caffeineBaseUrl, provider, movieId.toString(), language: audioLanguage, country: region);
    final res = await http.get(Uri.parse(url), headers: _caffeineApiHeaders).timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      debugPrint('[ApiService] ❌ Movie stream fetch failed for $provider: ${res.statusCode} ${res.body}');
      throw Exception('Stream failed with status ${res.statusCode}');
    }
    return core.ProviderStreamResponse.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<core.ProviderStreamResponse> fetchTvStream(
      int tmdbId, int season, int episode, {String provider = 'vidsrcsu'}) async {
    final url = core.Endpoints.streamTvUrl(caffeineBaseUrl, provider, tmdbId.toString(), season, episode, language: audioLanguage, country: region);
    final res = await http.get(Uri.parse(url), headers: _caffeineApiHeaders).timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      debugPrint('[ApiService] ❌ TV stream fetch failed for $provider: ${res.statusCode} ${res.body}');
      throw Exception('Stream failed with status ${res.statusCode}');
    }
    return core.ProviderStreamResponse.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<core.MovieListResponse> searchMovies(String query) async {
    final url = core.Endpoints.movieSearchUrl(tmdbBaseUrl, _tmdbKey, query, false, language);
    return _fetchMovieList(url);
  }

   Future<core.MovieListResponse> fetchMoviesByProvider(int providerId, {int page = 1, String sortBy = 'popularity.desc'}) async {
    final url = core.Endpoints.discoverMoviesUrl(tmdbBaseUrl, _tmdbKey, page, language, withProviders: providerId, sortBy: sortBy, region: region);
    return _fetchMovieList(url);
  }

  Future<core.TvListResponse> fetchTvByProvider(int providerId, {int page = 1, String sortBy = 'popularity.desc'}) async {
    final url = core.Endpoints.discoverTvUrl(tmdbBaseUrl, _tmdbKey, page, language, withProviders: providerId, sortBy: sortBy, region: region);
    return _fetchTvList(url);
  }

  Future<core.TvListResponse> searchTv(String query) async {
    final url = core.Endpoints.tvSearchUrl(tmdbBaseUrl, _tmdbKey, query, false, language);
    return _fetchTvList(url);
  }

  Future<core.MovieListResponse> fetchMoviesByGenre(int genreId, {int page = 1, String sortBy = 'popularity.desc'}) async {
    final url = core.Endpoints.moviesForGenreUrl(tmdbBaseUrl, _tmdbKey, genreId, page, language, sortBy: sortBy);
    return _fetchMovieList(url);
  }

  Future<core.TvListResponse> fetchTvByGenre(int genreId, {int page = 1, String sortBy = 'popularity.desc'}) async {
    final url = core.Endpoints.tvShowsForGenreUrl(tmdbBaseUrl, _tmdbKey, genreId, page, language, sortBy: sortBy);
    return _fetchTvList(url);
  }

  Future<core.MovieListResponse> _fetchMovieList(String url) async {
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('Failed to load movies (Status: ${res.statusCode}, URL: $url)');
    }
    return core.MovieListResponse.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<core.TvListResponse> _fetchTvList(String url) async {
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('Failed to load TV (Status: ${res.statusCode}, URL: $url)');
    }
    return core.TvListResponse.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Fetches media quality from the centralized Caffeine API (/v1/quality/:type/:id).
  Future<String?> fetchMediaQuality(String type, int id) async {
    try {
      final url = core.Endpoints.qualityUrl(caffeineBaseUrl, type, id);
      final res = await http
          .get(Uri.parse(url), headers: _caffeineApiHeaders)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['success'] == true && data['quality'] != null) {
          return (data['quality'] as String).toUpperCase();
        }
      }
    } catch (e) {
      debugPrint('[ApiService] Error fetching media quality for $type:$id: $e');
    }
    return null;
  }

  /// Fetches a paginated batch of titles for the "See More" screen,
  /// resolving against TMDB trending, popular, genre, or discovery based
  /// on section title and metadata.
  Future<List<core.MovieListItem>> fetchCategoryItems({
    required String title,
    String? sectionType,
    required bool isMovie,
    required int page,
    int? genreId,
  }) async {
    final lowerTitle = title.toLowerCase().trim();
    final lowerType = (sectionType ?? '').toLowerCase().trim();
    final targetType = isMovie ? 'movie' : 'tv';

    String? url;

    // 1. Explicit or detected Genres matching
    final genreMapMovies = {
      'action': 28,
      'adventure': 12,
      'animation': 16,
      'anime': 16,
      'comedy': 35,
      'crime': 80,
      'documentary': 99,
      'drama': 18,
      'family': 10751,
      'fantasy': 14,
      'history': 36,
      'horror': 27,
      'music': 10402,
      'musical': 10402,
      'mystery': 9648,
      'romance': 10749,
      'romantic': 10749,
      'sci-fi': 878,
      'science fiction': 878,
      'thriller': 53,
      'war': 10752,
      'western': 37,
    };

    final genreMapTv = {
      'action': 10759,
      'adventure': 10759,
      'action & adventure': 10759,
      'animation': 16,
      'anime': 16,
      'comedy': 35,
      'crime': 80,
      'documentary': 99,
      'drama': 18,
      'family': 10751,
      'kids': 10762,
      'mystery': 9648,
      'news': 10763,
      'reality': 10764,
      'sci-fi': 10765,
      'science fiction': 10765,
      'sci-fi & fantasy': 10765,
      'soap': 10766,
      'talk': 10767,
      'war': 10768,
      'war & politics': 10768,
      'western': 37,
    };

    int? matchedGenreId = genreId;
    if (matchedGenreId == null) {
      final activeGenreMap = isMovie ? genreMapMovies : genreMapTv;
      for (final entry in activeGenreMap.entries) {
        if (lowerTitle == entry.key || lowerTitle.contains(entry.key)) {
          matchedGenreId = entry.value;
          break;
        }
      }
    }

    if (matchedGenreId != null) {
      url = isMovie
          ? core.Endpoints.moviesForGenreUrl(tmdbBaseUrl, _tmdbKey, matchedGenreId, page, language)
          : core.Endpoints.tvShowsForGenreUrl(tmdbBaseUrl, _tmdbKey, matchedGenreId, page, language);
    }
    // 2. Trending
    else if (lowerTitle.contains('trending') || lowerType == 'tmdb') {
      url = '$tmdbBaseUrl/trending/$targetType/week?api_key=$_tmdbKey&language=$language&page=$page';
    }
    // 3. Popular / Community Trending / Trending on Reelriot
    else if (lowerTitle.contains('popular') || lowerType == 'community' || lowerTitle.contains('reelriot')) {
      url = '$tmdbBaseUrl/$targetType/popular?api_key=$_tmdbKey&language=$language&page=$page';
    }
    // 4. Top Rated / Critically Acclaimed
    else if (lowerTitle.contains('top rated') || lowerTitle.contains('acclaimed') || lowerTitle.contains('best')) {
      url = isMovie
          ? '$tmdbBaseUrl/movie/top_rated?api_key=$_tmdbKey&language=$language&page=$page&region=$region'
          : '$tmdbBaseUrl/tv/top_rated?api_key=$_tmdbKey&language=$language&page=$page';
    }
    // 5. Fresh Drops / New Releases / Now Playing / Airing
    else if (lowerTitle.contains('fresh') || lowerTitle.contains('new') || lowerTitle.contains('drop') || lowerTitle.contains('playing') || lowerTitle.contains('airing')) {
      if (isMovie) {
        url = '$tmdbBaseUrl/movie/now_playing?api_key=$_tmdbKey&language=$language&page=$page';
      } else {
        url = '$tmdbBaseUrl/tv/on_the_air?api_key=$_tmdbKey&language=$language&page=$page';
      }
    }
    // 6. Upcoming / Coming Soon
    else if (lowerTitle.contains('upcoming') || lowerTitle.contains('soon')) {
      if (isMovie) {
        url = '$tmdbBaseUrl/movie/upcoming?api_key=$_tmdbKey&language=$language&page=$page';
      } else {
        url = '$tmdbBaseUrl/discover/tv?api_key=$_tmdbKey&language=$language&sort_by=first_air_date.desc&page=$page';
      }
    }
    // 7. Holiday & Seasonal (Halloween, Christmas, etc.)
    else if (lowerType == 'holiday' || lowerTitle.contains('halloween') || lowerTitle.contains('spooky') || lowerTitle.contains('christmas') || lowerTitle.contains('holiday')) {
      if (lowerTitle.contains('halloween') || lowerTitle.contains('spooky') || lowerTitle.contains('horror')) {
        url = '$tmdbBaseUrl/discover/$targetType?api_key=$_tmdbKey&language=$language&sort_by=popularity.desc&page=$page&with_genres=27';
      } else {
        final q = Uri.encodeComponent(lowerTitle.contains('christmas') ? 'christmas' : 'holiday');
        url = '$tmdbBaseUrl/search/$targetType?api_key=$_tmdbKey&language=$language&query=$q&page=$page';
      }
    }
    // 8. Viral on Social
    else if (lowerType == 'social' || lowerTitle.contains('social') || lowerTitle.contains('viral')) {
      url = '$tmdbBaseUrl/trending/$targetType/week?api_key=$_tmdbKey&language=$language&page=$page';
    }
    // 9. Fallback Search by title keywords, or general Discover by popularity
    else {
      final clean = title.replaceAll(RegExp(r'magic|picks|collection|specials|featured|spotlight|ai', caseSensitive: false), '').trim();
      if (clean.length >= 3) {
        final q = Uri.encodeComponent(clean);
        url = '$tmdbBaseUrl/search/$targetType?api_key=$_tmdbKey&language=$language&query=$q&page=$page';
      } else {
        url = '$tmdbBaseUrl/discover/$targetType?api_key=$_tmdbKey&language=$language&sort_by=popularity.desc&page=$page';
      }
    }

    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        final fallbackUrl = '$tmdbBaseUrl/discover/$targetType?api_key=$_tmdbKey&language=$language&sort_by=popularity.desc&page=$page';
        final fbRes = await http.get(Uri.parse(fallbackUrl)).timeout(const Duration(seconds: 10));
        if (fbRes.statusCode != 200) return [];
        final data = jsonDecode(fbRes.body) as Map<String, dynamic>;
        final results = (data['results'] as List<dynamic>?) ?? [];
        return _parseMovieItems(results, targetType);
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final results = (data['results'] as List<dynamic>?) ?? [];

      if (results.isEmpty && page == 1) {
        final fallbackUrl = '$tmdbBaseUrl/discover/$targetType?api_key=$_tmdbKey&language=$language&sort_by=popularity.desc&page=1';
        final fbRes = await http.get(Uri.parse(fallbackUrl)).timeout(const Duration(seconds: 10));
        if (fbRes.statusCode == 200) {
          final fbData = jsonDecode(fbRes.body) as Map<String, dynamic>;
          return _parseMovieItems((fbData['results'] as List<dynamic>?) ?? [], targetType);
        }
      }

      return _parseMovieItems(results, targetType);
    } catch (e) {
      debugPrint('[ApiService] ⚠️ Error fetching category items for "$title" (page $page): $e');
      return [];
    }
  }

  List<core.MovieListItem> _parseMovieItems(List<dynamic> rawList, String targetType) {
    return rawList
        .whereType<Map>()
        .map((m) {
          final map = Map<String, dynamic>.from(m);
          map['media_type'] ??= targetType;
          return core.MovieListItem.fromJson(map);
        })
        .where((item) =>
            item.id > 0 &&
            ((item.posterPath != null && item.posterPath!.isNotEmpty) ||
             (item.backdropPath != null && item.backdropPath!.isNotEmpty)))
        .toList();
  }
}

