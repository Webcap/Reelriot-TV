import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/external_subtitles.dart';

class SubtitleService {
  static const String _baseUrl = 'https://api.opensubtitles.com/api/v1';

  Future<List<SubtitleData>> searchSubtitles({
    required String imdbId,
    required String languageCode,
    required String apiKey,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    if (imdbId.isEmpty || apiKey.isEmpty) return [];

    String url = '$_baseUrl/subtitles?imdb_id=$imdbId&languages=$languageCode&ai_translated=exclude';
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
}
