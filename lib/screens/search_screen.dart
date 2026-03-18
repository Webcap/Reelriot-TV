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
  void initState() {
    super.initState();
  }

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
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Search',
            style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Column: Keyboard + Search Bar
                SizedBox(
                  width: 480,
                  child: Column(
                    children: [
                      _buildSearchBar(),
                      const SizedBox(height: 16),
                      Expanded(
                        child: _VirtualKeyboard(
                          onKeyPress: (key) {
                            setState(() {
                              _queryController.text += key;
                            });
                          },
                          onBackspace: () {
                            if (_queryController.text.isNotEmpty) {
                              setState(() {
                                _queryController.text = _queryController.text
                                    .substring(0, _queryController.text.length - 1);
                              });
                            }
                          },
                          onClear: () {
                            setState(() {
                              _queryController.clear();
                              _movies = null;
                              _tv = null;
                            });
                          },
                          onSearch: _search,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 64),
                // Right Column: Results
                Expanded(
                  child: _buildResultsSection(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Focus(
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: focused ? const Color(0xFFEC1D24) : Colors.white10,
                width: 2,
              ),
              color: const Color(0xFF111111),
            ),
            child: TextField(
              controller: _queryController,
              readOnly: true, // Use Virtual Keyboard or Speech
              style: const TextStyle(color: Colors.white, fontSize: 20),
              decoration: InputDecoration(
                hintText: 'Search for movies or shows',
                hintStyle: TextStyle(color: Colors.grey[600]),
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                border: InputBorder.none,
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildResultsSection() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFDC2626)));
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.red)));
    }
    if (_movies == null && _tv == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 80, color: Colors.white10),
            SizedBox(height: 16),
            Text(
              'Type or use voice to discover content',
              style: TextStyle(color: Colors.white30, fontSize: 18),
            ),
          ],
        ),
      );
    }
    if (_movies!.isEmpty && _tv!.isEmpty) {
      return const Center(child: Text('No results found', style: TextStyle(color: Colors.white54, fontSize: 18)));
    }

    return ListView(
      children: [
        if (_movies!.isNotEmpty) ...[
          const Text('Movies', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _HorizontalResults(
            items: _movies!,
            onTap: (m) => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => MovieDetailScreen(movieId: m.id)),
            ),
          ),
          const SizedBox(height: 48),
        ],
        if (_tv!.isNotEmpty) ...[
          const Text('TV Shows', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _HorizontalResults(
            items: _tv!,
            onTap: (t) => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => TvDetailScreen(tvId: t.id)),
            ),
          ),
        ],
      ],
    );
  }
}


class _VirtualKeyboard extends StatelessWidget {
  final Function(String) onKeyPress;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onSearch;

  const _VirtualKeyboard({
    required this.onKeyPress,
    required this.onBackspace,
    required this.onClear,
    required this.onSearch,
  });

  static const _layout = [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          ..._layout.map((row) => Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: row.map((key) => _Key(
                label: key,
                onTap: () => onKeyPress(key),
              )).toList(),
            ),
          )),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Key(
                label: 'SPACE',
                flex: 4,
                onTap: () => onKeyPress(' '),
              ),
              _Key(
                label: '⌫',
                flex: 2,
                onTap: onBackspace,
                color: Colors.white24,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Key(
                label: 'CLEAR',
                flex: 3,
                onTap: onClear,
                color: Colors.white10,
              ),
              _Key(
                label: 'SEARCH',
                flex: 3,
                onTap: onSearch,
                color: const Color(0xFFDC2626),
                isPrimary: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final int flex;
  final Color? color;
  final bool isPrimary;

  const _Key({
    required this.label,
    required this.onTap,
    this.flex = 1,
    this.color,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.select)) {
              onTap();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Builder(builder: (context) {
            final focused = Focus.of(context).hasFocus;
            return GestureDetector(
              onTap: onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 48,
                decoration: BoxDecoration(
                  color: focused 
                      ? (isPrimary ? Colors.white : Colors.white24)
                      : (color ?? Colors.white.withOpacity(0.05)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: focused ? Colors.white : Colors.white10,
                    width: focused ? 2 : 1,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: focused && !isPrimary ? Colors.white : (focused && isPrimary ? Colors.black : Colors.white70),
                    fontSize: 16,
                    fontWeight: focused ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _HorizontalResults extends StatelessWidget {
  final List items;
  final Function(dynamic) onTap;

  const _HorizontalResults({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 450,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
          final String? poster = (item is MovieListItem) ? item.posterPath : (item as TvListItem).posterPath;
          final String title = (item is MovieListItem) ? (item.title ?? 'Movie') : (item as TvListItem).name ?? 'TV';
          
          return PosterCard(
            posterPath: poster,
            title: title,
            onTap: () => onTap(item),
          );
        },
      ),
    );
  }
}
