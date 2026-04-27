import 'package:caffeine_core/caffeine_core.dart';
import 'package:reelriot_tv/screens/home_screen.dart';
import 'package:reelriot_tv/screens/movie_detail_screen.dart';
import 'package:reelriot_tv/screens/tv_detail_screen.dart';
import 'package:reelriot_tv/services/api_service.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reelriot_tv/services/ad_service.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> {
  final ApiService _api = ApiService();
  final FocusNode _searchNode = FocusNode();
  final TextEditingController _queryController = TextEditingController();

  void requestFocus() {
    _searchNode.requestFocus();
  }
  List<MovieListItem>? _movies;
  List<TvListItem>? _tv;
  String? _error;
  bool _loading = false;
  Timer? _debounceTimer;
  List<String> _history = [];
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    // Load banner ad for search screen
    AdService.instance.loadBannerAd();
  }

  @override
  void dispose() {
    _queryController.dispose();
    _searchNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _history = prefs.getStringList('search_history') ?? [];
      });
    }
  }

  Future<void> _saveToHistory(String query) async {
    if (query.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('search_history') ?? [];
    
    // Remove if exists and add to front
    history.removeWhere((q) => q.toLowerCase() == query.toLowerCase());
    history.insert(0, query);
    
    // Keep last 10
    final limited = history.take(10).toList();
    await prefs.setStringList('search_history', limited);
    
    if (mounted) {
      setState(() {
        _history = limited;
      });
    }
  }

  void _onQueryChanged() {
    _debounceTimer?.cancel();
    if (_queryController.text.isEmpty) {
      setState(() {
        _movies = null;
        _tv = null;
      });
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 600), () {
      _search();
    });
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
        if (q.isNotEmpty && (movies.results.isNotEmpty || tv.results.isNotEmpty)) {
          _saveToHistory(q);
        }
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
                            _onQueryChanged();
                          },
                          onBackspace: () {
                            if (_queryController.text.isNotEmpty) {
                              setState(() {
                                _queryController.text = _queryController.text
                                    .substring(0, _queryController.text.length - 1);
                              });
                              _onQueryChanged();
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
          if (AdService.instance.isBannerLoaded)
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 16),
                child: AdService.instance.getBannerAd(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Focus(
      focusNode: _searchNode,
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
              readOnly: true,
              showCursor: true,
              cursorColor: const Color(0xFFDC2626),
              cursorWidth: 3,
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_history.isNotEmpty) ...[
            const Text(
              'Recent Searches',
              style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _history.map((q) => _HistoryPill(
                label: q,
                onTap: () {
                  _queryController.text = q;
                  _search();
                },
              )).toList(),
            ),
            const SizedBox(height: 48),
          ],
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search, size: 80, color: Colors.white10),
                SizedBox(height: 16),
                Text(
                  'Search to discover content',
                  style: TextStyle(color: Colors.white30, fontSize: 18),
                ),
              ],
            ),
          ),
        ],
      );
    }
    if (_movies!.isEmpty && _tv!.isEmpty) {
      return const Center(child: Text('No results found', style: TextStyle(color: Colors.white54, fontSize: 18)));
    }

    return ListView(
      children: [
        if (_movies!.isNotEmpty) ...[
          const Text('Movies', style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ..._movies!.map((m) => _ResultTile(
            item: m,
            onTap: () async {
              if (_isProcessing) return;
              _isProcessing = true;
              try {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => MovieDetailScreen(movieId: m.id)),
                );
                if (mounted && context.mounted) {
                  HomeScreenState.of(context)?.setIndex(1);
                }
              } finally {
                _isProcessing = false;
                if (mounted) setState(() {});
              }
            },
          )),
          const SizedBox(height: 32),
        ],
        if (_tv!.isNotEmpty) ...[
          const Text('TV Shows', style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ..._tv!.map((t) => _ResultTile(
            item: t,
            onTap: () async {
              if (_isProcessing) return;
              _isProcessing = true;
              try {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => TvDetailScreen(tvId: t.id)),
                );
                if (mounted && context.mounted) {
                  HomeScreenState.of(context)?.setIndex(1);
                }
              } finally {
                _isProcessing = false;
                if (mounted) setState(() {});
              }
            },
          )),
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
          if (event is KeyDownEvent && TvKeys.isSelect(event.logicalKey)) {
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
                      : (color ?? Colors.white.withValues(alpha: 0.05)),
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

class _ResultTile extends StatelessWidget {
  final dynamic item;
  final VoidCallback onTap;

  const _ResultTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final String? poster = (item is MovieListItem) ? item.posterPath : (item as TvListItem).posterPath;
    final String title = (item is MovieListItem) ? (item.title ?? 'Movie') : (item as TvListItem).name ?? 'TV';
    final String? overview = (item is MovieListItem) ? item.overview : (item as TvListItem).overview;
    final String? date = (item is MovieListItem) ? item.releaseDate : (item as TvListItem).firstAirDate;
    final String year = (date != null && date.length >= 4) ? date.substring(0, 4) : '';
    final double rating = (item is MovieListItem) ? (item.voteAverage ?? 0) : (item as TvListItem).voteAverage ?? 0;

    return Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent && TvKeys.isSelect(event.logicalKey)) {
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
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: focused ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: focused ? Colors.white : Colors.white10,
                width: 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Small Poster
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 70,
                    height: 105,
                    child: (poster != null && poster.isNotEmpty)
                        ? Image.network(
                            'https://image.tmdb.org/t/p/w185$poster',
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(color: Colors.grey[900]),
                          )
                        : Container(color: Colors.grey[900]),
                  ),
                ),
                const SizedBox(width: 24),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: focused ? Colors.white : Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (year.isNotEmpty) ...[
                            Text(year, style: const TextStyle(color: Colors.white54, fontSize: 14)),
                            const SizedBox(width: 16),
                          ],
                          const Icon(Icons.star, color: Color(0xFFDC2626), size: 14),
                          const SizedBox(width: 4),
                          Text(
                            rating.toStringAsFixed(1),
                            style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (overview != null && overview.isNotEmpty)
                        Text(
                          overview,
                          style: TextStyle(
                            color: focused ? Colors.white.withValues(alpha: 0.8) : Colors.white54,
                            fontSize: 14,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (focused)
                  const Center(
                    child: Icon(Icons.chevron_right, color: Colors.white54),
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _HistoryPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _HistoryPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent && TvKeys.isSelect(event.logicalKey)) {
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: focused ? Colors.white : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: focused ? Colors.white : Colors.white10,
                width: 1,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: focused ? Colors.black : Colors.white70,
                fontSize: 14,
                fontWeight: focused ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      }),
    );
  }
}
