import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/external_subtitles.dart';

class SubtitleService {
  static const String _baseUrl = 'https://api.opensubtitles.com/api/v1';

  Future<List<SubtitleData>> searchSubtitles({
    required int tmdbId,
    required String languageCode,
    required String apiKey,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    if (tmdbId == 0 || apiKey.isEmpty) return [];

    // Use parent_tmdb_id for episodes as required by OpenSubtitles API
    final String idParam = (seasonNumber != null && episodeNumber != null) 
        ? 'parent_tmdb_id' 
        : 'tmdb_id';

    String url = '$_baseUrl/subtitles?$idParam=$tmdbId&languages=$languageCode&ai_translated=exclude';
    if (seasonNumber != null && episodeNumber != null) {
      url += '&season_number=$seasonNumber&episode_number=$episodeNumber';
    }

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Api-Key': apiKey,
          'Accept': 'application/json',
          'User-Agent': 'caffeine_tv v1.0.0',
          'X-User-Agent': 'caffeine_tv v1.0.0',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return [];
      }

      final data = jsonDecode(response.body);
      return ExternalSubtitle.fromJson(data).data ?? [];
    } catch (e) {
      return [];
    }
  }

  Future<String?> downloadSubtitle(int fileId, String apiKey) async {
    if (apiKey.isEmpty) return null;

    const url = '$_baseUrl/download';
    final body = jsonEncode({'file_id': fileId});

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Api-Key': apiKey,
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'User-Agent': 'caffeine_tv v1.0.0',
        },
        body: body,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body);
      return SubtitleDownload.fromJson(data).link;
    } catch (e) {
      return null;
    }
  }

  Future<String?> getSubtitleContent(String url) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'caffeine_tv v1.0.0',
        },
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return response.body;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
