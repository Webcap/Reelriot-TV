import 'package:caffeine_core/caffeine_core.dart';
import 'package:reelriot_tv/screens/movie_detail_screen.dart';
import 'package:reelriot_tv/services/api_service.dart';
import 'package:reelriot_tv/widgets/poster_card.dart';
import 'package:reelriot_tv/utils/quality_utils.dart';
import 'package:flutter/material.dart';

class MoviesScreen extends StatefulWidget {
  const MoviesScreen({super.key});

  @override
  State<MoviesScreen> createState() => _MoviesScreenState();
}

class _MoviesScreenState extends State<MoviesScreen> {
  final ApiService _api = ApiService();
  List<MovieListItem>? _popular;
  List<MovieListItem>? _trending;
  List<MovieListItem>? _topRated;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final popular = await _api.fetchPopularMovies();
      final trending = await _api.fetchTrendingMovies();
      final topRated = await _api.fetchTopRatedMovies();
      if (mounted) {
        setState(() {
          _popular = popular.results;
          _trending = trending.results;
          _topRated = topRated.results;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
      children: [
        _buildSection('Popular', _popular),
        _buildSection('Trending', _trending),
        _buildSection('Top Rated', _topRated),
      ],
    );
  }

  Widget _buildSection(String title, List<MovieListItem>? items) {
    if (items == null) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 230,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final m = items[index];
                return PosterCard(
                  posterPath: m.posterPath,
                  title: m.title ?? 'Movie',
                  onTap: () => _openDetail(m.id),
                  quality: QualityUtils.getQualityBadgeSync(
                    releaseDate: m.releaseDate,
                    isMovie: true,
                  ),
                  mediaId: m.id,
                  isMovie: true,
                  releaseDate: m.releaseDate,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openDetail(int movieId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MovieDetailScreen(movieId: movieId),
      ),
    );
  }
}
