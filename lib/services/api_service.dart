import 'dart:convert';

import 'package:caffeine_core/caffeine_core.dart' as core;
import 'package:caffeine_tv/constants.dart';
import 'package:caffeine_tv/env.dart';
import 'package:caffeine_tv/services/settings_service.dart';
import 'package:http/http.dart' as http;

class ApiService {
  String get _tmdbKey => tmdbApiKey;
  String get tmdbBaseUrl => tmdbApiBaseUrl;
  String get caffeineBaseUrl => caffeineApiUrl.replaceFirst(RegExp(r'/$'), '');
  String get language => SettingsService().language;

  Future<Map<String, dynamic>> loadConfig() async {
    return core.fetchConfig(caffeineBaseUrl);
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
    final url = core.Endpoints.topRatedMoviesUrl(tmdbBaseUrl, _tmdbKey, language);
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
    if (res.statusCode != 200) throw Exception('Failed to load show');
    return core.TvShowDetail.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<core.TvSeasonDetailResponse> fetchSeasonDetail(int tvId, int seasonNumber) async {
    final url = core.Endpoints.tvSeasonDetailUrl(tmdbBaseUrl, _tmdbKey, tvId, seasonNumber, language);
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Failed to load season');
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

  Future<core.ProviderStreamResponse> fetchMovieStream(int movieId, {String provider = 'vixsrc'}) async {
    final url = core.Endpoints.streamMovieUrl(caffeineBaseUrl, provider, movieId.toString());
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw Exception('Stream failed');
    return core.ProviderStreamResponse.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<core.ProviderStreamResponse> fetchTvStream(
      int tmdbId, int season, int episode, {String provider = 'vixsrc'}) async {
    final url = core.Endpoints.streamTvUrl(caffeineBaseUrl, provider, tmdbId.toString(), season, episode);
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw Exception('Stream failed');
    return core.ProviderStreamResponse.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<core.MovieListResponse> searchMovies(String query) async {
    final url = core.Endpoints.movieSearchUrl(tmdbBaseUrl, _tmdbKey, query, false, language);
    return _fetchMovieList(url);
  }

   Future<core.MovieListResponse> fetchMoviesByProvider(int providerId, {int page = 1, String sortBy = 'popularity.desc'}) async {
    final url = core.Endpoints.discoverMoviesUrl(tmdbBaseUrl, _tmdbKey, page, language, withProviders: providerId, sortBy: sortBy);
    return _fetchMovieList(url);
  }

  Future<core.TvListResponse> fetchTvByProvider(int providerId, {int page = 1, String sortBy = 'popularity.desc'}) async {
    final url = core.Endpoints.discoverTvUrl(tmdbBaseUrl, _tmdbKey, page, language, withProviders: providerId, sortBy: sortBy);
    return _fetchTvList(url);
  }

  Future<core.TvListResponse> searchTv(String query) async {
    final url = core.Endpoints.tvSearchUrl(tmdbBaseUrl, _tmdbKey, query, false, language);
    return _fetchTvList(url);
  }

  Future<core.MovieListResponse> _fetchMovieList(String url) async {
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Failed to load movies');
    return core.MovieListResponse.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<core.TvListResponse> _fetchTvList(String url) async {
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Failed to load TV');
    return core.TvListResponse.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }
}
