import 'package:caffeine_core/caffeine_core.dart';
import 'package:reelriot_tv/screens/movie_detail_screen.dart';
import 'package:reelriot_tv/services/api_service.dart';
import 'package:reelriot_tv/widgets/poster_card.dart';
import 'package:reelriot_tv/utils/quality_utils.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:reelriot_tv/models/discovery_section.dart';

class MoviesScreen extends StatefulWidget {
  const MoviesScreen({super.key});

  @override
  State<MoviesScreen> createState() => _MoviesScreenState();
}

class _MoviesScreenState extends State<MoviesScreen> {
  final ApiService _api = ApiService();
  List<DiscoverySection>? _sections;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      final discovery = await _api.fetchDiscovery(
        userId: userId,
        mediaType: 'movie',
        region: _api.region,
      );
      
      final List<DiscoverySection> parsedSections = (discovery['sections'] as List)
          .map((s) => DiscoverySection.fromJson(s))
          .where((s) => s.isEnabled && s.items.isNotEmpty)
          .toList();

      if (mounted) {
        setState(() {
          _sections = parsedSections;
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

    if (_sections == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
      itemCount: _sections!.length,
      itemBuilder: (context, index) {
        final section = _sections![index];
        return _buildSection(section.title, section.items);
      },
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
