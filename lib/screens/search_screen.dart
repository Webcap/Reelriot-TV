import 'package:caffeine_core/caffeine_core.dart';
import 'package:caffeine_tv/screens/movie_detail_screen.dart';
import 'package:caffeine_tv/screens/tv_detail_screen.dart';
import 'package:caffeine_tv/services/api_service.dart';
import 'package:caffeine_tv/widgets/poster_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _queryController = TextEditingController();
  List<MovieListItem>? _movies;
  List<TvListItem>? _tv;
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _queryController.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _error = null;
      _loading = true;
      _movies = null;
      _tv = null;
    });
    try {
      final movies = await _api.searchMovies(q);
      final tv = await _api.searchTv(q);
      if (mounted) {
        setState(() {
          _movies = movies.results;
          _tv = tv.results;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Search',
            style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Focus(
                  child: Builder(
                    builder: (context) {
                      final focused = Focus.of(context).hasFocus;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: focused ? const Color(0xFFEC1D24) : Colors.transparent,
                            width: 2,
                          ),
                          boxShadow: focused
                              ? [BoxShadow(color: const Color(0xFFEC1D24).withOpacity(0.3), blurRadius: 12, spreadRadius: 1)]
                              : [],
                        ),
                        child: TextField(
                          controller: _queryController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Movies and TV shows',
                            hintStyle: TextStyle(color: Colors.grey[600]),
                            filled: true,
                            fillColor: const Color(0xFF1a1a2e),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onSubmitted: (_) => _search(),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Focus(
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      (event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.select)) {
                    _search();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final focused = Focus.of(context).hasFocus;
                    return ElevatedButton(
                      onPressed: _loading ? null : _search,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: focused ? Colors.white : const Color(0xFFDC2626),
                        foregroundColor: focused ? Colors.black : Colors.white,
                        side: focused ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      child: Text(_loading ? 'Searching…' : 'Search'),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_movies != null && _tv != null) ...[
            if (_movies!.isEmpty && _tv!.isEmpty)
              const Expanded(
                child: Center(child: Text('No results', style: TextStyle(color: Colors.white54, fontSize: 18))),
              )
            else
              Expanded(
                child: ListView(
                  children: [
                    if (_movies!.isNotEmpty) ...[
                      const Text('Movies', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 220,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _movies!.length,
                          itemBuilder: (context, i) {
                            final m = _movies![i];
                            return PosterCard(
                              posterPath: m.posterPath,
                              title: m.title ?? 'Movie',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (context) => MovieDetailScreen(movieId: m.id)),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    if (_tv!.isNotEmpty) ...[
                      const Text('TV Shows', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 220,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _tv!.length,
                          itemBuilder: (context, i) {
                            final t = _tv![i];
                            return PosterCard(
                              posterPath: t.posterPath,
                              title: t.name ?? 'TV',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (context) => TvDetailScreen(tvId: t.id)),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
