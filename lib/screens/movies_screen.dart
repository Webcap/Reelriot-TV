import 'package:caffeine_core/caffeine_core.dart';
import 'package:reelriot_tv/screens/movie_detail_screen.dart';
import 'package:reelriot_tv/screens/see_more_screen.dart';
import 'package:reelriot_tv/services/api_service.dart';
import 'package:reelriot_tv/widgets/poster_card.dart';
import 'package:reelriot_tv/widgets/see_more_poster_card.dart';
import 'package:reelriot_tv/widgets/tv_skeleton_loader.dart';
import 'package:reelriot_tv/utils/quality_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
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
      
      final rawSections = discovery['sections'] ?? discovery['rows'];
      final List<DiscoverySection> parsedSections = rawSections is List
          ? rawSections
              .whereType<Map>()
              .map((s) => DiscoverySection.fromJson(Map<String, dynamic>.from(s)))
              .where((s) => s.isEnabled && s.items.isNotEmpty)
              .toList()
          : [];

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
      return const TvBrowseScreenSkeleton(sectionCount: 3);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
      itemCount: _sections!.length,
      itemBuilder: (context, index) {
        final section = _sections![index];
        return _buildSection(section);
      },
    );
  }

  Widget _buildSection(DiscoverySection section) {
    final title = section.title;
    final items = section.items;
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
            height: 268,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: items.length >= 4 ? items.length + 1 : items.length,
              itemBuilder: (context, index) {
                if (index == items.length) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: SeeMorePosterCard(
                      title: title,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SeeMoreScreen(
                              title: title,
                              items: items,
                              isMovie: true,
                              sectionType: section.type,
                              mediaType: 'movie',
                            ),
                          ),
                        );
                      },
                    ),
                  );
                }
                final m = items[index];
                final isLast = items.length < 4 && index == items.length - 1;

                return Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: PosterCard(
                    posterPath: m.posterPath,
                    title: m.title ?? 'Movie',
                    onTap: () => _openDetail(m.id),
                    quality: QualityUtils.getQualityBadgeSync(
                      mediaId: m.id,
                      releaseDate: m.releaseDate,
                      isMovie: true,
                    ),
                    mediaId: m.id,
                    isMovie: true,
                    releaseDate: m.releaseDate,
                    onKeyEvent: isLast
                        ? (node, event) {
                            if (TvKeys.isRight(event.logicalKey)) {
                              if (event is KeyDownEvent) {
                                SystemSound.play(SystemSoundType.click);
                                HapticFeedback.lightImpact();
                              }
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          }
                        : null,
                  ),
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
