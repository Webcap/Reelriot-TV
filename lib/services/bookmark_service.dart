import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:caffeine_core/caffeine_core.dart';
import 'package:flutter/foundation.dart';
import 'package:reelriot_tv/utils/auth_error_utils.dart';

class BookmarkService {
  final _supabase = Supabase.instance.client;

  Future<bool> isBookmarked(int id, bool isMovie) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    try {
      final res = await _supabase
          .from('bookmarks')
          .select(isMovie ? 'movies' : 'tv_shows')
          .eq('user_id', user.id)
          .limit(1);

      if (res.isEmpty) return false;
      final List<dynamic> items = res[0][isMovie ? 'movies' : 'tv_shows'] ?? [];
      return items.any((item) => item['id'] == id);
    } catch (e) {
      debugPrint('Error checking bookmark: $e');
      await handleIfUnrecoverableAuthError(e);
      return false;
    }
  }

  Future<void> toggleBookmark(dynamic item, bool isMovie) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not signed in');

    try {
      final res = await _supabase
          .from('bookmarks')
          .select('movies, tv_shows')
          .eq('user_id', user.id)
          .limit(1);

      Map<String, dynamic>? data = res.isNotEmpty ? res[0] : null;
      List<dynamic> movies = data?['movies'] ?? [];
      List<dynamic> tv = data?['tv_shows'] ?? [];

      if (isMovie) {
        final movie = item as MovieDetail;
        final index = movies.indexWhere((m) => m['id'] == movie.id);
        if (index != -1) {
          movies.removeAt(index);
        } else {
          movies.add({
            'id': movie.id,
            'title': movie.title,
            'poster_path': movie.posterPath,
            'backdrop_path': movie.backdropPath,
            'overview': movie.overview,
            'vote_average': movie.voteAverage,
          });
        }
      } else {
        final show = item as TvShowDetail;
        final index = tv.indexWhere((t) => t['id'] == show.id);
        if (index != -1) {
          tv.removeAt(index);
        } else {
          tv.add({
            'id': show.id,
            'name': show.name,
            'poster_path': show.posterPath,
            'backdrop_path': show.backdropPath,
            'overview': show.overview,
            'vote_average': show.voteAverage,
          });
        }
      }

      if (data == null) {
        await _supabase.from('bookmarks').insert({
          'user_id': user.userMetadata?['id'] ?? user.id, // Some systems use metadata id
          'movies': movies,
          'tv_shows': tv,
        });
      } else {
        await _supabase
            .from('bookmarks')
            .update({
              'movies': movies,
              'tv_shows': tv,
            })
            .eq('user_id', user.id);
      }
    } catch (e) {
      debugPrint('Error toggling bookmark: $e');
      await handleIfUnrecoverableAuthError(e);
      rethrow;
    }
  }
}
