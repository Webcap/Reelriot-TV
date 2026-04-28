import 'package:caffeine_core/caffeine_core.dart';
import 'package:reelriot_tv/screens/tv_detail_screen.dart';
import 'package:reelriot_tv/services/api_service.dart';
import 'package:reelriot_tv/widgets/poster_card.dart';
import 'package:reelriot_tv/utils/quality_utils.dart';
import 'package:flutter/material.dart';

class TvShowsScreen extends StatefulWidget {
  const TvShowsScreen({super.key});

  @override
  State<TvShowsScreen> createState() => _TvShowsScreenState();
}

class _TvShowsScreenState extends State<TvShowsScreen> {
  final ApiService _api = ApiService();
  List<TvListItem>? _popular;
  List<TvListItem>? _trending;
  List<TvListItem>? _topRated;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final popular = await _api.fetchPopularTv();
      final trending = await _api.fetchTrendingTv();
      final topRated = await _api.fetchTopRatedTv();
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
        _buildSection('Popular TV', _popular),
        _buildSection('Popular Shows This Week', _trending),
        _buildSection('Top Rated TV', _topRated),
      ],
    );
  }

  Widget _buildSection(String title, List<TvListItem>? items) {
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
                final t = items[index];
                return PosterCard(
                  posterPath: t.posterPath,
                  title: t.name ?? 'TV',
                  onTap: () => _openDetail(t.id),
                  quality: QualityUtils.getQualityBadgeSync(
                    releaseDate: t.firstAirDate,
                    isMovie: false,
                  ),
                  mediaId: t.id,
                  isMovie: false,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openDetail(int tvId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TvDetailScreen(tvId: tvId),
      ),
    );
  }
}
