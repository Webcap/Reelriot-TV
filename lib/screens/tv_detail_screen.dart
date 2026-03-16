import 'package:caffeine_core/caffeine_core.dart';
import 'package:caffeine_tv/constants.dart';
import 'package:caffeine_tv/screens/video_loader_screen.dart';
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
  List<TvListItem>? _recommendations;
  CreditsResponse? _credits;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final show = await _api.fetchTvDetail(widget.tvId);
      List<TvListItem>? recs;
      CreditsResponse? credits;

      // Fetch recommendations and credits in parallel
      await Future.wait([
        _api.fetchTvRecommendations(widget.tvId).then((r) => recs = r.results).catchError((_) => recs = []),
        _api.fetchTvCredits(widget.tvId).then((c) => credits = c).catchError((_) => credits = CreditsResponse(id: widget.tvId, cast: [])),
      ]);

      if (mounted) {
        setState(() {
          _show = show;
          _seasons = {};
          if (show.numberOfSeasons != null && show.numberOfSeasons! > 0) {
            _selectedSeason = 1;
          }
          _recommendations = recs;
          _credits = credits;
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
              child: SingleChildScrollView(
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
                              autofocus: i == 0,
                              descendantsAreFocusable: false,
                              onKeyEvent: (node, event) {
                                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                                if (event.logicalKey == LogicalKeyboardKey.enter ||
                                    event.logicalKey == LogicalKeyboardKey.select ||
                                    event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                                    event.logicalKey == LogicalKeyboardKey.space) {
                                  setState(() {
                                    _selectedSeason = num;
                                    _loadSeason(num);
                                  });
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              },
                              child: Builder(
                                builder: (context) {
                                  final focused = Focus.of(context).hasFocus;
                                  return GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedSeason = num;
                                        _loadSeason(num);
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: selected ? const Color(0xFFDC2626) : Colors.white24,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: focused ? Colors.white : Colors.transparent,
                                          width: 2,
                                        ),
                                        boxShadow: focused
                                            ? [const BoxShadow(color: Colors.white38, blurRadius: 8)]
                                            : [],
                                      ),
                                      child: Center(
                                        child: Text(
                                          '$num',
                                          style: const TextStyle(color: Colors.white, fontSize: 16),
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  const Text('Episodes', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (episodes.isEmpty)
                    const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('Select a season', style: TextStyle(color: Colors.white54))))
                  else
                    FocusTraversalGroup(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: episodes.map((ep) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Focus(
                              descendantsAreFocusable: false,
                              onKeyEvent: (node, event) {
                                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                                if (event.logicalKey == LogicalKeyboardKey.enter ||
                                    event.logicalKey == LogicalKeyboardKey.select ||
                                    event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                                    event.logicalKey == LogicalKeyboardKey.space) {
                                  _playEpisode(ep.seasonNumber, ep.episodeNumber);
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              },
                              child: Builder(
                                builder: (context) {
                                  final focused = Focus.of(context).hasFocus;
                                  return GestureDetector(
                                    onTap: () => _playEpisode(ep.seasonNumber, ep.episodeNumber),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: focused ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: focused ? Colors.white : Colors.transparent,
                                          width: 2,
                                        ),
                                        boxShadow: focused
                                            ? [BoxShadow(color: Colors.white.withValues(alpha: 0.1), blurRadius: 8)]
                                            : [],
                                      ),
                                      child: Row(
                                        children: [
                                          if (ep.stillPath != null && ep.stillPath!.isNotEmpty)
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: CachedNetworkImage(
                                                imageUrl: '$tmdbImageBaseUrl/w300${ep.stillPath}',
                                                width: 120,
                                                height: 68,
                                                fit: BoxFit.cover,
                                              ),
                                            )
                                          else
                                            Container(
                                              width: 120,
                                              height: 68,
                                              decoration: BoxDecoration(
                                                color: Colors.white10,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: const Icon(Icons.tv, color: Colors.white38),
                                            ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'E${ep.episodeNumber} ${ep.name ?? ""}',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 18,
                                                    fontWeight: focused ? FontWeight.bold : FontWeight.normal,
                                                  ),
                                                ),
                                                if (ep.overview != null && ep.overview!.isNotEmpty)
                                                  Text(
                                                    ep.overview!,
                                                    style: TextStyle(
                                                      color: focused ? Colors.white70 : Colors.white54,
                                                      fontSize: 14,
                                                    ),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  if (_credits != null && _credits!.cast.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text('Cast', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 180,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _credits!.cast.length,
                        itemBuilder: (context, index) {
                          final actor = _credits!.cast[index];
                          return Focus(
                            descendantsAreFocusable: false,
                            onKeyEvent: (node, event) {
                              if (event is! KeyDownEvent) return KeyEventResult.ignored;
                              if (event.logicalKey == LogicalKeyboardKey.enter ||
                                  event.logicalKey == LogicalKeyboardKey.select ||
                                  event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                                  event.logicalKey == LogicalKeyboardKey.space) {
                                // Currently Cast just shows info, no click action yet, but we allow focus
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            child: Builder(
                              builder: (context) {
                                final focused = Focus.of(context).hasFocus;
                                return Container(
                                  width: 100,
                                  margin: const EdgeInsets.only(right: 16),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: focused ? Colors.white : Colors.transparent,
                                      width: 2,
                                    ),
                                    color: focused ? Colors.white12 : Colors.transparent,
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  child: Column(
                                    children: [
                                      ClipOval(
                                        child: actor.profilePath != null
                                            ? CachedNetworkImage(
                                                imageUrl: '$tmdbImageBaseUrl/w185${actor.profilePath}',
                                                width: 80,
                                                height: 80,
                                                fit: BoxFit.cover,
                                                placeholder: (context, url) => Container(color: Colors.white12),
                                                errorWidget: (context, url, error) => Container(
                                                  color: Colors.white12,
                                                  child: const Icon(Icons.person, color: Colors.white54),
                                                ),
                                              )
                                            : Container(
                                                width: 80,
                                                height: 80,
                                                color: Colors.white12,
                                                child: const Icon(Icons.person, color: Colors.white54),
                                              ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        actor.name,
                                        style: TextStyle(
                                          color: focused ? Colors.white : Colors.white70, 
                                          fontSize: 13, 
                                          fontWeight: focused ? FontWeight.bold : FontWeight.normal
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                );
                              }
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  if (_recommendations != null && _recommendations!.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text('Recommendations', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 180,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _recommendations!.length,
                        itemBuilder: (context, index) {
                          final rec = _recommendations![index];
                          return Focus(
                            descendantsAreFocusable: false,
                            onKeyEvent: (node, event) {
                              if (event is! KeyDownEvent) return KeyEventResult.ignored;
                              if (event.logicalKey == LogicalKeyboardKey.enter ||
                                  event.logicalKey == LogicalKeyboardKey.select ||
                                  event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                                  event.logicalKey == LogicalKeyboardKey.space) {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (context) => TvDetailScreen(tvId: rec.id),
                                  ),
                                );
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            child: Builder(
                              builder: (context) {
                                final focused = Focus.of(context).hasFocus;
                                return GestureDetector(
                                  onTap: () {
                                    Navigator.of(context).pushReplacement(
                                      MaterialPageRoute(
                                        builder: (context) => TvDetailScreen(tvId: rec.id),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    width: 120,
                                    margin: const EdgeInsets.only(right: 16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: focused ? Colors.white : Colors.transparent,
                                                width: 3,
                                              ),
                                              boxShadow: focused
                                                  ? [const BoxShadow(color: Colors.white38, blurRadius: 8)]
                                                  : [],
                                            ),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(5),
                                              child: rec.posterPath != null && rec.posterPath!.isNotEmpty
                                                  ? CachedNetworkImage(
                                                      imageUrl: '$tmdbImageBaseUrl/w500${rec.posterPath}',
                                                      fit: BoxFit.cover,
                                                      width: double.infinity,
                                                      placeholder: (context, url) => const ColoredBox(color: Colors.white12),
                                                      errorWidget: (context, url, error) => const ColoredBox(color: Colors.white12, child: Center(child: Icon(Icons.image, color: Colors.white54))),
                                                    )
                                                  : const ColoredBox(color: Colors.white12, child: Center(child: Icon(Icons.tv, color: Colors.white54))),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          rec.name ?? 'TV Show',
                                          style: TextStyle(
                                            color: focused ? Colors.white : Colors.white70,
                                            fontSize: 14,
                                            fontWeight: focused ? FontWeight.bold : FontWeight.normal,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _playEpisode(int season, int episode) {
    if (_show == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VideoLoaderScreen(
          tvShow: _show,
          season: season,
          episode: episode,
        ),
      ),
    );
  }
}
