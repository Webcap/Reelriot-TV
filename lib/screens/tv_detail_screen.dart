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
                  episodes.isEmpty
                      ? const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('Select a season', style: TextStyle(color: Colors.white54))))
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
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
                          return Container(
                            width: 100,
                            margin: const EdgeInsets.only(right: 16),
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
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (actor.character != null)
                                  Text(
                                    actor.character!,
                                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
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
                            onKeyEvent: (_, event) {
                              if (event is KeyDownEvent &&
                                  (event.logicalKey == LogicalKeyboardKey.enter ||
                                   event.logicalKey == LogicalKeyboardKey.select)) {
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
                                return Container(
                                  width: 120,
                                  margin: const EdgeInsets.only(right: 16),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        Navigator.of(context).pushReplacement(
                                          MaterialPageRoute(
                                            builder: (context) => TvDetailScreen(tvId: rec.id),
                                          ),
                                        );
                                      },
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
