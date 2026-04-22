import 'dart:convert';
import 'package:caffeine_core/caffeine_core.dart';
import 'package:reelriot_tv/env.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class RecommendationResult {
  final List<MovieListItem> items;
  final String? anchorTitle;

  RecommendationResult({required this.items, this.anchorTitle});
}

class RecommendationService {
  String get _baseUrl => caffeineApiUrl.replaceFirst(RegExp(r'/$'), '');

  Future<RecommendationResult> getRecommendations({String? situation, String? mediaType}) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;

    final url = Uri.parse('$_baseUrl/recommendations').replace(queryParameters: {
      'userId': ?userId,
      if (situation != null && situation.isNotEmpty) 'situation': situation,
      if (mediaType != null && mediaType.isNotEmpty) 'mediaType': mediaType,
    });

    try {
      final headers = <String, String>{};
      if (caffeineApiKey.isNotEmpty) {
        headers['Authorization'] = 'Bearer $caffeineApiKey';
      }

      final response = await http.get(url, headers: headers).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return RecommendationResult(items: []);

      final data = jsonDecode(response.body);
      if (data['success'] == true && data['recommendations'] != null) {
        final List<dynamic> recs = data['recommendations'];
        final items = recs.map((item) {
          return MovieListItem.fromJson(Map<String, dynamic>.from(item as Map));
        }).toList();
        return RecommendationResult(
          items: items,
          anchorTitle: data['anchorTitle'],
        );
      }
    } catch (e) {
      debugPrint('Error fetching recommendations: $e');
    }
    return RecommendationResult(items: []);
  }
}
