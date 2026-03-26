import 'package:caffeine_core/caffeine_core.dart';
import 'package:caffeine_tv/screens/home_screen.dart';
import 'package:caffeine_tv/screens/movie_detail_screen.dart';
import 'package:caffeine_tv/screens/tv_detail_screen.dart';
import 'package:caffeine_tv/widgets/poster_card.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FavoritesScreen extends StatefulWidget {
  final GlobalKey<FavoritesScreenState>? favoritesKey;
  const FavoritesScreen({super.key, this.favoritesKey});

  @override
  State<FavoritesScreen> createState() => FavoritesScreenState();
}

class FavoritesScreenState extends State<FavoritesScreen> with AutomaticKeepAliveClientMixin {
  final _supabase = Supabase.instance.client;
  List<MovieListItem> _bookmarkedMovies = [];
  List<TvListItem> _bookmarkedTv = [];
  bool _loading = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchBookmarks();
  }

  void refresh() {
    _fetchBookmarks(quiet: true);
  }

  Future<void> _fetchBookmarks({bool quiet = false}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    // Only show full loading spinner if not quiet or if we have no data yet
    final showLoading = !quiet || (_bookmarkedMovies.isEmpty && _bookmarkedTv.isEmpty);

    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final res = await _supabase
          .from('bookmarks')
          .select('movies, tv_shows')
          .eq('user_id', user.id)
          .limit(1);

      if (res.isNotEmpty) {
        final moviesRaw = res[0]['movies'] as List<dynamic>? ?? [];
        final tvRaw = res[0]['tv_shows'] as List<dynamic>? ?? [];

        setState(() {
          _bookmarkedMovies = moviesRaw
              .map((e) => MovieListItem.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
          _bookmarkedTv = tvRaw
              .map((e) => TvListItem.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Error fetching bookmarks: $e');
      setState(() => _error = 'Failed to load favorites');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final user = _supabase.auth.currentUser;

    if (user == null) {
      return _buildLoginPrompt();
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFE60000)));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.white70, fontSize: 18)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchBookmarks,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE60000)),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_bookmarkedMovies.isEmpty && _bookmarkedTv.isEmpty) {
      return const Center(
        child: Text(
          'No favorites yet',
          style: TextStyle(color: Colors.white54, fontSize: 20),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'My Favorites',
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 32),
          if (_bookmarkedMovies.isNotEmpty) ...[
            _SectionHeader(title: 'Movies'),
            const SizedBox(height: 16),
            _buildGrid(_bookmarkedMovies, isMovie: true),
            const SizedBox(height: 48),
          ],
          if (_bookmarkedTv.isNotEmpty) ...[
            _SectionHeader(title: 'TV Shows'),
            const SizedBox(height: 16),
            _buildGrid(_bookmarkedTv, isMovie: false),
          ],
        ],
      ),
    );
  }

  Widget _buildGrid(List<dynamic> items, {required bool isMovie}) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        childAspectRatio: 0.7,
        crossAxisSpacing: 24,
        mainAxisSpacing: 24,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return PosterCard(
          posterPath: item.posterPath,
          title: isMovie ? (item as MovieListItem).title ?? '' : (item as TvListItem).name ?? '',
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => isMovie 
                  ? MovieDetailScreen(movieId: item.id)
                  : TvDetailScreen(tvId: item.id),
              ),
            );
            if (context.mounted) {
              HomeScreenState.of(context)?.setIndex(1);
            }
          },
        );
      },
    );
  }

  Widget _buildLoginPrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.favorite_border, size: 80, color: Colors.white24),
          const SizedBox(height: 24),
          const Text(
            'Sign in to see your favorites',
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Keep track of movies and shows you want to watch across all your devices.',
            style: TextStyle(color: Colors.white54, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pushNamed('/pairing'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE60000),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Sign In / Sign Up', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 24,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
