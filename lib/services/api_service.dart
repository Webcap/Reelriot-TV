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
  
  static const String _browserUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// Headers for Caffeine API requests — includes Authorization when a key is set.
  Map<String, String> get _caffeineApiHeaders {
    final headers = <String, String>{'User-Agent': _browserUserAgent};
    final key = caffeineApiKey;
    if (key.isNotEmpty) headers['Authorization'] = 'Bearer $key';
    return headers;
  }

  Future<Map<String, dynamic>> loadConfig() async {
    return core.fetchConfig(caffeineBaseUrl, apiKey: caffeineApiKey);
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

  /// TV App polls this to see if it's been linked.
  Future<http.Response> pollPairing(String code) async {
    final url = Uri.parse('$caffeineBaseUrl/tv/pair?code=${Uri.encodeComponent(code)}');
    return http.get(url, headers: _caffeineApiHeaders).timeout(const Duration(seconds: 10));
  }

  /// Explicitly confirm pairing (usually done from phone/web, but here for completeness).
  Future<http.Response> confirmPairing(String code, String accessToken, String refreshToken) async {
    final url = Uri.parse('$caffeineBaseUrl/tv/pair/confirm');
    return http.post(
      url,
      headers: {..._caffeineApiHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'code': code,
        'access_token': accessToken,
        'refresh_token': refreshToken,
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

  Future<core.ProviderStreamResponse> fetchMovieStream(int movieId, {String provider = 'vixsrc'}) async {
    final url = core.Endpoints.streamMovieUrl(caffeineBaseUrl, provider, movieId.toString(), language: audioLanguage, country: region);
    final res = await http.get(Uri.parse(url), headers: _caffeineApiHeaders).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      debugPrint('[ApiService] ❌ Movie stream fetch failed for $provider: ${res.statusCode} ${res.body}');
      throw Exception('Stream failed with status ${res.statusCode}');
    }
    return core.ProviderStreamResponse.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<core.ProviderStreamResponse> fetchTvStream(
      int tmdbId, int season, int episode, {String provider = 'vixsrc'}) async {
    final url = core.Endpoints.streamTvUrl(caffeineBaseUrl, provider, tmdbId.toString(), season, episode, language: audioLanguage, country: region);
    final res = await http.get(Uri.parse(url), headers: _caffeineApiHeaders).timeout(const Duration(seconds: 30));
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

  Future<bool> isDigitalRelease(int movieId) async {
    try {
      final url = core.Endpoints.movieDetailsUrl(tmdbBaseUrl, _tmdbKey, movieId, language);
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return false;
      
      final data = jsonDecode(res.body);
      final homepage = data['homepage'] as String? ?? '';
      final productionCompanies = data['production_companies'] as List? ?? [];

      const streamers = ["netflix.com", "amazon.com", "apple.com", "disneyplus.com", "hbomax.com", "paramountplus.com", "peacocktv.com"];
      if (streamers.any((s) => homepage.contains(s))) return true;

      const digitalStudios = ["Netflix", "Amazon Studios", "Apple", "Disney", "Paramount+", "Peacock", "Hulu", "HBO"];
      if (productionCompanies.any((c) => digitalStudios.any((s) => (c['name'] as String).contains(s)))) return true;

      // Also check release dates for type 4 (Digital) or 5 (Physical)
      final releaseUrl = '$tmdbBaseUrl/movie/$movieId/release_dates?api_key=$_tmdbKey';
      final releaseRes = await http.get(Uri.parse(releaseUrl)).timeout(const Duration(seconds: 10));
      if (releaseRes.statusCode == 200) {
        final releaseData = jsonDecode(releaseRes.body);
        final results = releaseData['results'] as List? ?? [];
        for (var country in results) {
          final dates = country['release_dates'] as List? ?? [];
          for (var d in dates) {
            final type = d['type'] as int?;
            if (type == 4 || type == 5) {
              final releaseDateStr = d['release_date'] as String?;
              if (releaseDateStr != null) {
                final rDate = DateTime.parse(releaseDateStr);
                if (rDate.isBefore(DateTime.now())) return true;
              }
            }
          }
        }
      }

      return false;
    } catch (e) {
      debugPrint('[ApiService] Error checking digital release: $e');
      return false;
    }
  }
}
