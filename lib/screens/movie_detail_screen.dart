import 'package:caffeine_core/caffeine_core.dart';
import 'package:caffeine_tv/constants.dart';
import 'package:caffeine_tv/screens/player_screen.dart';
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await _api.fetchMovieDetail(widget.movieId);
      if (mounted) setState(() => _movie = m);
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
                            maxLines: 6,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 32),
                        Focus(
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
                              backgroundColor: const Color(0xFFDC2626),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                            ),
                          ),
                        ),
                      ],
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

  void _play() async {
    if (_movie == null) return;
    try {
      final response = await _api.fetchMovieStream(_movie!.id);
      if (!response.success || response.links == null || response.links!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No stream available')),
          );
        }
        return;
      }
      final link = response.links!.first;
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PlayerScreen(
              url: link.url,
              title: _movie!.title ?? 'Movie',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playback error: $e')),
        );
      }
    }
  }
}
