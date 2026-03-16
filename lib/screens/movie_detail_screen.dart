import 'package:caffeine_core/caffeine_core.dart';
import 'package:caffeine_tv/constants.dart';
import 'package:caffeine_tv/screens/video_loader_screen.dart';
import 'package:caffeine_tv/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

class MovieDetailScreen extends StatefulWidget {
  const MovieDetailScreen({super.key, required this.movieId});

  final int movieId;

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  final ApiService _api = ApiService();
  MovieDetail? _movie;
  List<MovieListItem>? _recommendations;
  CreditsResponse? _credits;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await _api.fetchMovieDetail(widget.movieId);
      List<MovieListItem>? recs;
      CreditsResponse? credits;
      
      // Fetch recommendations and credits in parallel
      await Future.wait([
        _api.fetchMovieRecommendations(widget.movieId).then((r) => recs = r.results).catchError((_) => recs = []),
        _api.fetchMovieCredits(widget.movieId).then((c) => credits = c).catchError((_) => credits = CreditsResponse(id: widget.movieId, cast: [])),
      ]);

      if (mounted) {
        setState(() {
          _movie = m;
          _recommendations = recs;
          _credits = credits;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
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
              ElevatedButton(
                onPressed: () {
                  setState(() => _error = null);
                  _load();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_movie == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B0F14),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final m = _movie!;
    final backdropUrl = m.backdropPath != null && m.backdropPath!.isNotEmpty
        ? '$tmdbImageBaseUrl/w780${m.backdropPath}'
        : null;

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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (m.posterPath != null && m.posterPath!.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: '$tmdbImageBaseUrl/w500${m.posterPath}',
                        width: 200,
                        height: 300,
                        fit: BoxFit.cover,
                      ),
                    ),
                  const SizedBox(width: 32),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                        Text(
                          m.title ?? 'Movie',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (m.releaseDate != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            m.releaseDate!,
                            style: const TextStyle(color: Colors.white70, fontSize: 18),
                          ),
                        ],
                        if (m.overview != null && m.overview!.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            m.overview!,
                            style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.4),
                          ),
                        ],
                        const SizedBox(height: 32),
                        Builder(
                          builder: (context) {
                            final focused = Focus.of(context).hasFocus;
                            return Focus(
                              onKeyEvent: (_, event) {
                                if (event is KeyDownEvent &&
                                    (event.logicalKey == LogicalKeyboardKey.enter ||
                                        event.logicalKey == LogicalKeyboardKey.select)) {
                                  _play();
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              },
                              child: ElevatedButton.icon(
                                onPressed: _play,
                                icon: const Icon(Icons.play_arrow, size: 28),
                                label: const Text('Play', style: TextStyle(fontSize: 18)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: focused ? Colors.white : const Color(0xFFDC2626),
                                  foregroundColor: focused ? Colors.black : Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                                  side: focused ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
                                ),
                              ),
                            );
                          }
                        ),
                        if (_credits != null && _credits!.cast.isNotEmpty) ...[
                          const SizedBox(height: 32),
                          const Text(
                            'Cast',
                            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 180,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _credits!.cast.length,
                              itemBuilder: (context, index) {
                                final actor = _credits!.cast[index];
                                return Focus(
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
                                                fontWeight: focused ? FontWeight.bold : FontWeight.normal,
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
                          const SizedBox(height: 32),
                          const Text(
                            'Recommendations',
                            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 200,
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
                                          builder: (context) => MovieDetailScreen(movieId: rec.id),
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
                                                  builder: (context) => MovieDetailScreen(movieId: rec.id),
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
                                                          : const ColoredBox(color: Colors.white12, child: Center(child: Icon(Icons.movie, color: Colors.white54))),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  rec.title ?? 'Movie',
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _play() {
    if (_movie == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VideoLoaderScreen(
          movie: _movie,
        ),
      ),
    );
  }
}
