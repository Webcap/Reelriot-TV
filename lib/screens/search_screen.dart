import 'package:caffeine_core/caffeine_core.dart';
import 'package:reelriot_tv/screens/home_screen.dart';
import 'package:reelriot_tv/screens/movie_detail_screen.dart';
import 'package:reelriot_tv/screens/tv_detail_screen.dart';
import 'package:reelriot_tv/services/api_service.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reelriot_tv/services/ad_service.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/utils/quality_utils.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/utils/tv_colors.dart';
import 'package:reelriot_tv/widgets/long_press_focus.dart';
import 'package:reelriot_tv/widgets/poster_card.dart';
import 'package:reelriot_tv/widgets/section_header.dart';
import 'package:reelriot_tv/widgets/tv_skeleton_loader.dart';

// Search — canon direction (see dashboard_theme.dart).
//
// Previous version was two unstyled columns floating on bare black: a
// keyboard with no visual container, and results as a description-heavy
// vertical list unique to this screen. This redesign panelizes the input
// side (search bar + keyboard live inside one bordered surface, matching
// the rest of the app's card language) and replaces the list with the
// same PosterCard grid every other browse screen (Favorites, Genre, Home
// rows) already uses — search results should look like the app, not like
// a bespoke results page.

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
    double s(double v) => ResponsiveUtils.scale(context, v);
    return Padding(
      padding: EdgeInsets.fromLTRB(s(48), s(32), s(48), s(32)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Search',
            style: TextStyle(
              color: Colors.white,
              fontSize: s(32),
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: s(24)),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: s(560),
                  child: _SearchPanel(
                    s: s,
                    searchNode: _searchNode,
                    controller: _queryController,
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
                SizedBox(width: s(56)),
                Expanded(child: _buildResultsSection(s)),
              ],
            ),
          ),
          if (AdService.instance.isBannerLoaded)
            Center(
              child: Container(
                margin: EdgeInsets.only(top: s(16)),
                child: AdService.instance.getBannerAd(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResultsSection(double Function(double) s) {
    if (_loading) {
      return _SearchGridSkeleton(s: s);
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: TvSemanticColors.dangerDefault)));
    }
    if (_movies == null && _tv == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_history.isNotEmpty) ...[
            SectionHeader(title: 'RECENT SEARCHES', s: s),
            SizedBox(height: s(20)),
            Wrap(
              spacing: s(12),
              runSpacing: s(12),
              children: _history.map((q) => _HistoryPill(
                label: q,
                s: s,
                onTap: () {
                  _queryController.text = q;
                  _search();
                },
              )).toList(),
            ),
          ],
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_rounded, size: s(88), color: Colors.white10),
                  SizedBox(height: s(20)),
                  Text(
                    'Search to discover movies and shows',
                    style: TextStyle(color: Colors.white30, fontSize: s(22)),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    if (_movies!.isEmpty && _tv!.isEmpty) {
      return Center(
        child: Text(
          'No results found',
          style: TextStyle(color: Colors.white54, fontSize: s(22)),
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_movies!.isNotEmpty) ...[
            SectionHeader(title: 'MOVIES', s: s),
            SizedBox(height: s(20)),
            _buildResultsGrid(_movies!, isMovie: true, s: s),
            SizedBox(height: s(40)),
          ],
          if (_tv!.isNotEmpty) ...[
            SectionHeader(title: 'TV SHOWS', s: s),
            SizedBox(height: s(20)),
            _buildResultsGrid(_tv!, isMovie: false, s: s),
          ],
        ],
      ),
    );
  }

  Widget _buildResultsGrid(List<dynamic> items, {required bool isMovie, required double Function(double) s}) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: s(240),
        childAspectRatio: 0.6,
        crossAxisSpacing: s(28),
        mainAxisSpacing: s(36),
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final String? poster = isMovie ? (item as MovieListItem).posterPath : (item as TvListItem).posterPath;
        final String title = isMovie ? ((item as MovieListItem).title ?? 'Movie') : ((item as TvListItem).name ?? 'TV');
        final String? date = isMovie ? (item as MovieListItem).releaseDate : (item as TvListItem).firstAirDate;

        return PosterCard(
          posterPath: poster,
          title: title,
          showTitle: true,
          quality: QualityUtils.getQualityBadgeSync(
            mediaId: item.id,
            releaseDate: date,
            isMovie: isMovie,
          ),
          mediaId: item.id,
          isMovie: isMovie,
          releaseDate: date,
          onTap: () async {
            if (_isProcessing) return;
            _isProcessing = true;
            try {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => isMovie
                      ? MovieDetailScreen(movieId: item.id)
                      : TvDetailScreen(tvId: item.id),
                ),
              );
              if (mounted && context.mounted) {
                HomeScreenState.of(context)?.setIndex(1);
              }
            } finally {
              _isProcessing = false;
              if (mounted) setState(() {});
            }
          },
        );
      },
    );
  }
}

/// The bordered input surface — search bar + on-screen keyboard live inside
/// one panel instead of floating unstyled on the black canvas.
class _SearchPanel extends StatelessWidget {
  final double Function(double) s;
  final FocusNode searchNode;
  final TextEditingController controller;
  final void Function(String) onKeyPress;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onSearch;

  const _SearchPanel({
    required this.s,
    required this.searchNode,
    required this.controller,
    required this.onKeyPress,
    required this.onBackspace,
    required this.onClear,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(s(28)),
      decoration: BoxDecoration(
        color: DashboardTheme.surface,
        borderRadius: BorderRadius.circular(s(20)),
        border: Border.all(color: DashboardTheme.divider, width: s(1.5)),
      ),
      child: Column(
        children: [
          _buildSearchBar(context),
          SizedBox(height: s(28)),
          Expanded(
            child: _VirtualKeyboard(
              s: s,
              onKeyPress: onKeyPress,
              onBackspace: onBackspace,
              onClear: onClear,
              onSearch: onSearch,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Focus(
      focusNode: searchNode,
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(s(12)),
              border: Border.all(
                color: focused ? DashboardTheme.signalRed : DashboardTheme.divider,
                width: s(2),
              ),
              color: DashboardTheme.surfaceRaised,
              boxShadow: focused
                  ? DashboardDecorations.focusGlow(
                      context,
                      strength: 0.7,
                      color: DashboardTheme.signalRed,
                    )
                  : null,
            ),
            child: TextField(
              controller: controller,
              readOnly: true,
              showCursor: true,
              cursorColor: DashboardTheme.signalRed,
              cursorWidth: s(4),
              style: TextStyle(color: Colors.white, fontSize: s(26)),
              decoration: InputDecoration(
                hintText: 'Search',
                hintStyle: TextStyle(color: Colors.white38, fontSize: s(26)),
                contentPadding: EdgeInsets.symmetric(horizontal: s(22), vertical: s(22)),
                border: InputBorder.none,
                prefixIcon: Icon(Icons.search_rounded, color: Colors.white54, size: s(30)),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VirtualKeyboard extends StatelessWidget {
  final double Function(double) s;
  final Function(String) onKeyPress;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onSearch;

  const _VirtualKeyboard({
    required this.s,
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
            padding: EdgeInsets.only(bottom: s(6)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: row.map((key) => _Key(
                s: s,
                label: key,
                onTap: () => onKeyPress(key),
              )).toList(),
            ),
          )),
          SizedBox(height: s(12)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Key(
                s: s,
                label: 'SPACE',
                flex: 4,
                onTap: () => onKeyPress(' '),
              ),
              _Key(
                s: s,
                label: '⌫',
                flex: 2,
                onTap: onBackspace,
              ),
            ],
          ),
          SizedBox(height: s(6)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Key(
                s: s,
                label: 'CLEAR',
                flex: 3,
                onTap: onClear,
              ),
              _Key(
                s: s,
                label: 'SEARCH',
                flex: 3,
                onTap: onSearch,
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
  final double Function(double) s;
  final String label;
  final VoidCallback onTap;
  final int flex;
  final bool isPrimary;

  const _Key({
    required this.s,
    required this.label,
    required this.onTap,
    this.flex = 1,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: EdgeInsets.all(s(4)),
        child: LongPressFocus(
          onTap: onTap,
          child: Builder(builder: (context) {
            final focused = Focus.of(context).hasFocus;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: s(68),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: isPrimary && !focused ? DashboardTheme.accentGradient : null,
                color: isPrimary
                    ? (focused ? Colors.white : null)
                    : (focused ? Colors.white : Colors.white.withValues(alpha: 0.06)),
                borderRadius: BorderRadius.circular(s(10)),
                border: Border.all(
                  color: focused ? Colors.white : Colors.white12,
                  width: s(1.5),
                ),
                boxShadow: focused
                    ? DashboardDecorations.focusGlow(
                        context,
                        strength: isPrimary ? 0.8 : 0.5,
                        color: isPrimary ? DashboardTheme.signalRed : null,
                      )
                    : null,
              ),
              child: Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: focused
                      ? Colors.black
                      : (isPrimary ? Colors.white : Colors.white70),
                  fontSize: s(24),
                  fontWeight: focused || isPrimary ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _HistoryPill extends StatelessWidget {
  final String label;
  final double Function(double) s;
  final VoidCallback onTap;

  const _HistoryPill({required this.label, required this.s, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return LongPressFocus(
      onTap: onTap,
      child: Builder(builder: (context) {
        final focused = Focus.of(context).hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(horizontal: s(22), vertical: s(14)),
          decoration: BoxDecoration(
            color: focused ? Colors.white : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(s(24)),
            border: Border.all(
              color: focused ? Colors.white : Colors.white12,
              width: s(1.5),
            ),
            boxShadow: focused ? DashboardDecorations.focusGlow(context, strength: 0.5) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_rounded, size: s(19), color: focused ? Colors.black : Colors.white38),
              SizedBox(width: s(10)),
              Text(
                label,
                style: TextStyle(
                  color: focused ? Colors.black : Colors.white70,
                  fontSize: s(19),
                  fontWeight: focused ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _SearchGridSkeleton extends StatelessWidget {
  final double Function(double) s;
  const _SearchGridSkeleton({required this.s});

  @override
  Widget build(BuildContext context) {
    return TvShimmer(
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: s(240),
          childAspectRatio: 0.6,
          crossAxisSpacing: s(28),
          mainAxisSpacing: s(36),
        ),
        itemCount: 10,
        itemBuilder: (context, index) {
          return Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(s(8)),
            ),
          );
        },
      ),
    );
  }
}
