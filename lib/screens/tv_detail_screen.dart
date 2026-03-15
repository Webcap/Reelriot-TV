import 'package:caffeine_core/caffeine_core.dart';
import 'package:caffeine_tv/constants.dart';
import 'package:caffeine_tv/screens/player_screen.dart';
import 'package:caffeine_tv/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

class TvDetailScreen extends StatefulWidget {
  const TvDetailScreen({super.key, required this.tvId});

  final int tvId;

  @override
  State<TvDetailScreen> createState() => _TvDetailScreenState();
}

class _TvDetailScreenState extends State<TvDetailScreen> {
  final ApiService _api = ApiService();
  TvShowDetail? _show;
  Map<int, TvSeasonDetailResponse>? _seasons;
  int? _selectedSeason;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final show = await _api.fetchTvDetail(widget.tvId);
      if (mounted) {
        setState(() {
          _show = show;
          _seasons = {};
          if (show.numberOfSeasons != null && show.numberOfSeasons! > 0) {
            _selectedSeason = 1;
          }
        });
        if (_selectedSeason != null) _loadSeason(_selectedSeason!);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _loadSeason(int num) async {
    if (_seasons!.containsKey(num)) return;
    try {
      final detail = await _api.fetchSeasonDetail(widget.tvId, num);
      if (mounted) setState(() => _seasons![num] = detail);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B0F14),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () { setState(() => _error = null); _load(); }, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_show == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B0F14),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final show = _show!;
    final backdropUrl = show.backdropPath != null && show.backdropPath!.isNotEmpty
        ? '$tmdbImageBaseUrl/w780${show.backdropPath}'
        : null;
    final seasonDetail = _selectedSeason != null && _seasons != null
        ? _seasons![_selectedSeason!]
        : null;
    final episodes = seasonDetail?.episodes ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (backdropUrl != null)
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: backdropUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => const ColoredBox(color: Color(0xFF1a1a2e)),
                errorWidget: (context, url, error) => const ColoredBox(color: Color(0xFF1a1a2e)),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (show.posterPath != null && show.posterPath!.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: '$tmdbImageBaseUrl/w500${show.posterPath}',
                            width: 200,
                            height: 300,
                            fit: BoxFit.cover,
                          ),
                        ),
                      const SizedBox(width: 32),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              show.name ?? 'TV Show',
                              style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                            ),
                            if (show.firstAirDate != null) ...[
                              const SizedBox(height: 8),
                              Text(show.firstAirDate!, style: const TextStyle(color: Colors.white70, fontSize: 18)),
                            ],
                            if (show.overview != null && show.overview!.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(
                                show.overview!,
                                style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.4),
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (show.numberOfSeasons != null && show.numberOfSeasons! > 0) ...[
                    const Text('Season', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 44,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: show.numberOfSeasons!,
                        itemBuilder: (context, i) {
                          final num = i + 1;
                          final selected = _selectedSeason == num;
                          return Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Focus(
                              onKeyEvent: (_, event) {
                                if (event is KeyDownEvent &&
                                    (event.logicalKey == LogicalKeyboardKey.enter ||
                                        event.logicalKey == LogicalKeyboardKey.select)) {
                                  setState(() {
                                    _selectedSeason = num;
                                    _loadSeason(num);
                                  });
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              },
                              child: Material(
                                color: selected ? const Color(0xFFDC2626) : Colors.white24,
                                borderRadius: BorderRadius.circular(8),
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _selectedSeason = num;
                                      _loadSeason(num);
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    child: Center(child: Text('$num', style: const TextStyle(color: Colors.white, fontSize: 16))),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  const Text('Episodes', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: episodes.isEmpty
                        ? const Center(child: Text('Select a season', style: TextStyle(color: Colors.white54)))
                        : ListView.builder(
                            itemCount: episodes.length,
                            itemBuilder: (context, index) {
                              final ep = episodes[index];
                              return Focus(
                                onKeyEvent: (_, event) {
                                  if (event is KeyDownEvent &&
                                      (event.logicalKey == LogicalKeyboardKey.enter ||
                                          event.logicalKey == LogicalKeyboardKey.select)) {
                                    _playEpisode(ep.seasonNumber, ep.episodeNumber);
                                    return KeyEventResult.handled;
                                  }
                                  return KeyEventResult.ignored;
                                },
                                child: ListTile(
                                  leading: ep.stillPath != null && ep.stillPath!.isNotEmpty
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: CachedNetworkImage(
                                            imageUrl: '$tmdbImageBaseUrl/w200${ep.stillPath}',
                                            width: 80,
                                            height: 45,
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      : const SizedBox(width: 80, height: 45, child: Icon(Icons.tv, color: Colors.white38)),
                                  title: Text(
                                    'E${ep.episodeNumber} ${ep.name ?? ""}',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  subtitle: ep.overview != null && ep.overview!.isNotEmpty
                                      ? Text(ep.overview!, style: const TextStyle(color: Colors.white54, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis)
                                      : null,
                                  onTap: () => _playEpisode(ep.seasonNumber, ep.episodeNumber),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _playEpisode(int season, int episode) async {
    if (_show == null) return;
    try {
      final response = await _api.fetchTvStream(_show!.id, season, episode);
      if (!response.success || response.links == null || response.links!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No stream available')));
        }
        return;
      }
      final link = response.links!.first;
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PlayerScreen(
              url: link.url,
              title: '${_show!.name} S${season}E$episode',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Playback error: $e')));
      }
    }
  }
}
