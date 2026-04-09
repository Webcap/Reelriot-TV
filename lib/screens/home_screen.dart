import 'package:caffeine_core/caffeine_core.dart';
import 'package:caffeine_tv/screens/tv_detail_screen.dart';
import 'package:caffeine_tv/screens/movie_detail_screen.dart';
import 'package:caffeine_tv/screens/search_screen.dart';
import 'package:caffeine_tv/screens/provider_screen.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:caffeine_tv/screens/favorites_screen.dart';
import 'package:caffeine_tv/screens/settings_screen.dart';
import 'package:caffeine_tv/screens/sports_screen.dart';
import 'package:caffeine_tv/services/api_service.dart';
import 'package:caffeine_tv/services/watch_history_service.dart';
import 'package:caffeine_tv/services/recommendation_service.dart';
import 'package:caffeine_tv/screens/video_loader_screen.dart';
import 'package:caffeine_tv/screens/player_screen.dart';
import 'package:caffeine_tv/env.dart';
import 'package:caffeine_tv/widgets/poster_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:caffeine_tv/widgets/exit_dialog.dart';
import 'package:caffeine_tv/services/settings_service.dart';
import 'package:caffeine_tv/services/update_service.dart';
import 'package:caffeine_tv/screens/update_screen.dart';
import 'dart:async';
import 'dart:ui';
import 'package:caffeine_tv/widgets/context_menu_dialog.dart';
import 'package:caffeine_tv/screens/genre_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  static HomeScreenState? of(BuildContext context) => context.findAncestorStateOfType<HomeScreenState>();

  int _selectedIndex = 1;
  final GlobalKey<FavoritesScreenState> _favoritesKey = GlobalKey<FavoritesScreenState>();
  final GlobalKey<SportsScreenState> _sportsKey = GlobalKey<SportsScreenState>();
  final GlobalKey<_MainHomeViewState> _homeKey = GlobalKey<_MainHomeViewState>();
  late List<FocusNode> _navNodes;

  void setIndex(int index) {
    if (mounted) {
      setState(() => _selectedIndex = index);
    }
  }

  List<_Tab> get _visibleTabs {
    final List<_Tab> tabs = [
      const _Tab(label: 'Search', icon: Icons.search),
      const _Tab(label: 'Home', icon: Icons.home_filled),
    ];
    
    if (SettingsService().sportsEnabled) {
      tabs.add(const _Tab(label: 'Sports', icon: Icons.sports_soccer));
    }
    
    tabs.add(const _Tab(label: 'Profile', icon: Icons.person_outline));
    tabs.add(const _Tab(label: 'Favorites', icon: Icons.favorite_border));
    return tabs;
  }

  @override
  void initState() {
    super.initState();
    _navNodes = List.generate(5, (_) => FocusNode());
    SettingsService().addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SettingsService().removeListener(_onSettingsChanged);
    for (var node in _navNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _onBackInvoke(bool didPop) async {
    if (didPop) return;

    // Check if any navigation item has focus
    bool navHasFocus = false;
    for (var node in _navNodes) {
      if (node.hasFocus) {
        navHasFocus = true;
        break;
      }
    }

    if (!navHasFocus) {
      // If navigation doesn't have focus, reset focus to the current tab
      _navNodes[_selectedIndex].requestFocus();
      return;
    }

    // If navigation already has focus, show the exit dialog
    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const ExitDialog(),
    );

    if (shouldExit == true) {
      // Exit the application
      SystemNavigator.pop();
    }
  }


  @override
  Widget build(BuildContext context) {
    final tabs = _visibleTabs;
    // Ensure selected index is within bounds if tabs change
    if (_selectedIndex >= tabs.length) {
      _selectedIndex = 1; // Default to Home
    }

    // Ensure we have enough focus nodes
    if (_navNodes.length < tabs.length) {
      _navNodes.addAll(List.generate(tabs.length - _navNodes.length, (_) => FocusNode()));
    }

    return PopScope(
      canPop: false,
      onPopInvoked: _onBackInvoke,
      child: Scaffold(
        backgroundColor: const Color(0xFF000000), // Pure black per design.json
        body: Row(
          children: [
            _buildNavRail(context, tabs),
            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                children: [
                  const SearchScreen(),
                  RepaintBoundary(child: _MainHomeView(key: _homeKey)),
                  if (SettingsService().sportsEnabled) RepaintBoundary(child: SportsScreen(key: _sportsKey)),
                  const SettingsScreen(),
                  FavoritesScreen(key: _favoritesKey),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _scale(BuildContext context, double value) {
    final width = MediaQuery.of(context).size.width;
    // Base scale on 1080p width (1920)
    return (value * width) / 1920;
  }

  Widget _buildNavRail(BuildContext context, List<_Tab> tabs) {
    final s = (double v) => _scale(context, v);
    // Updated per design.json: width 8rem (128px), background #111111
    return Container(
      width: s(128), 
      color: const Color(0xFF111111), 
      child: Column(
        children: [
          SizedBox(height: s(40)),
          // Logo placeholder
          Container(
            width: s(90),
            height: s(45),
            decoration: BoxDecoration(
              color: const Color(0xFFEC1D24), // Exact Marvel Brand Red
              borderRadius: BorderRadius.circular(s(4)),
            ),
            alignment: Alignment.center,
            child: Text(
              'CAFFEINE',
              style: TextStyle(
                color: Colors.white,
                fontSize: s(16),
                fontWeight: FontWeight.w900,
                letterSpacing: s(1),
              ),
            ),
          ),
          SizedBox(height: s(60)),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: List.generate(tabs.length, (i) {
                  final tab = tabs[i];
                  final selected = _selectedIndex == i;
                  return Focus(
                    autofocus: i == _selectedIndex,
                    focusNode: _navNodes[i],
                    onKeyEvent: (node, event) {
                      if (event is! KeyDownEvent) return KeyEventResult.ignored;
                      if (event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.select) {
                        if (_selectedIndex == i) {
                          // Already on this tab, trigger reset/refresh
                          if (tab.label == 'Home') {
                            _homeKey.currentState?.resetToTop();
                          } else if (tab.label == 'Sports') {
                            _sportsKey.currentState?.load();
                          }
                        } else {
                          setState(() => _selectedIndex = i);
                          // Also trigger load if switching TO sports
                          if (tab.label == 'Sports') {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _sportsKey.currentState?.load();
                            });
                          }
                        }

                        // Check if selected tab is favorites
                        if (tab.label == 'Favorites') {
                          _favoritesKey.currentState?.refresh();
                        }
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Builder(
                      builder: (context) {
                        final focused = Focus.of(context).hasFocus;
                        return Padding(
                          padding: EdgeInsets.symmetric(vertical: s(24)),
                          child: AnimatedScale(
                            scale: selected || focused ? 1.08 : 1.0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: s(85),
                              height: s(85),
                              decoration: BoxDecoration(
                                // gray.800 (#1f2937) for active sidebar item
                                color: selected ? const Color(0xFF1F2937) : (focused ? Colors.white.withOpacity(0.05) : Colors.transparent),
                                borderRadius: BorderRadius.circular(s(18)),
                                border: Border.all(
                                  color: focused ? Colors.white24 : Colors.transparent,
                                  width: s(2),
                                ),
                              ),
                              child: Icon(
                                tab.icon, 
                                color: Colors.white, 
                                size: s(42)
                              ),
                            ),
                          ),
                        );
                      }
                    ),
                  );
                }),
              ),
            ),
          ),
          if (SettingsService().isOffline)
            Padding(
              padding: EdgeInsets.only(bottom: s(24)),
              child: Tooltip(
                message: 'Offline Mode',
                child: Container(
                  width: s(54),
                  height: s(54),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEC1D24).withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFEC1D24).withOpacity(0.3), width: s(1)),
                  ),
                  child: Icon(
                    Icons.cloud_off_rounded,
                    color: const Color(0xFFEC1D24),
                    size: s(24),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tab {
  final String label;
  final IconData icon;
  const _Tab({required this.label, required this.icon});
}

class _MainHomeView extends StatefulWidget {
  const _MainHomeView({super.key});

  @override
  State<_MainHomeView> createState() => _MainHomeViewState();
}

class _MainHomeViewState extends State<_MainHomeView> {
  final ApiService _api = ApiService();
  final WatchHistoryService _historyService = WatchHistoryService();

  void _showItemContextMenu({
    required dynamic item,
    required bool isMovie,
    int? season,
    int? episode,
    int? episodeId,
    String? episodeName,
    int? showId,
  }) {
    double s(double v) => _scale(context, v);
    final title = isMovie 
        ? (item is MovieDetail ? item.title : (item is MovieListItem ? item.title : item['title'] ?? 'Movie'))
        : (item is TvShowDetail ? item.name : (item is MovieListItem ? item.title : item['name'] ?? item['title'] ?? 'TV Show'));

    // Resolve the show/movie ID for navigation
    final resolvedId = showId ??
        (item is MovieDetail ? item.id
          : item is MovieListItem ? item.id
          : item is TvShowDetail ? item.id
          : ((item as Map)['media_id'] ?? item['id']));

    // Capture the navigator before the dialog opens — the dialog's own
    // Navigator.pop() would otherwise undo a push made from onTap().
    final nav = Navigator.of(context);

    ContextMenuDialog.show(
      context: context,
      title: title,
      s: s,
      items: [
        if (!isMovie && resolvedId != null)
          ContextMenuItem(
            label: 'Go to Show',
            icon: Icons.tv,
            onTap: () {
              // Use microtask so the dialog's own pop() fires first,
              // then we push — otherwise pop() would remove our pushed route.
              Future.microtask(() {
                nav.push(
                  MaterialPageRoute(
                    builder: (context) => TvDetailScreen(tvId: resolvedId),
                  ),
                );
              });
            },
          ),
        ContextMenuItem(
          label: 'Mark as Completed',
          icon: Icons.check_circle_outline,
          onTap: () async {
            await _historyService.markAsComplete(
              item: item,
              isMovie: isMovie,
              season: season,
              episode: episode,
              episodeId: episodeId,
              episodeName: episodeName,
            );
            await _reloadHistory(forceRefresh: true);
          },
        ),
        ContextMenuItem(
          label: 'Remove from History',
          icon: Icons.delete_outline,
          color: Colors.redAccent,
          onTap: () async {
            final id = item is MovieDetail ? item.id : (item is MovieListItem ? item.id : (item is TvShowDetail ? item.id : (item as Map)['media_id'] ?? item['id'] ?? item['mediaId']));
            await _historyService.removeFromHistory(
              id: id,
              isMovie: isMovie,
              season: season,
              episode: episode,
            );
            await _reloadHistory(forceRefresh: true);
          },
        ),
      ],
    );
  }
  String _selectedCategory = 'Movies';
  MovieDetail? _focusedMovie;
  List<MovieListItem>? _trending;
  List<MovieListItem>? _weeklyTrending;
  List<MovieListItem>? _popular;
  List<MovieListItem>? _topRated;
  List<MovieListItem>? _upcoming;
  List<MovieListItem>? _nowPlaying;
  List<MovieListItem>? _airingToday;
  List<MovieListItem>? _aiRecommendations;
  String? _aiAnchorTitle;
  List<MovieListItem>? _tvRecommendations;
  String? _tvRecommendationsTitle;
  final RecommendationService _recService = RecommendationService();
  List<Map<String, dynamic>>? _history;
  List<Map<String, dynamic>>? _watchingShows;
  bool _loading = true;
  bool _isProcessing = false;
  Timer? _autoSlideTimer;
  int _trendingIndex = 0;
  late ScrollController _scrollController;
  bool _isHeroInView = true;
  StreamSubscription<AuthState>? _authSubscription;
  final Map<int, String> _liveStreamUrls = {};
  UpdateInfo? _updateInfo;
  Timer? _debounceTimer;

  final List<Map<String, dynamic>> _movieGenres = [
    {'id': 28, 'name': 'Action', 'color': const Color(0xFFDC2626)},
    {'id': 12, 'name': 'Adventure', 'color': const Color(0xFFEA580C)},
    {'id': 16, 'name': 'Animation', 'color': const Color(0xFFD97706)},
    {'id': 35, 'name': 'Comedy', 'color': const Color(0xFFCA8A04)},
    {'id': 80, 'name': 'Crime', 'color': const Color(0xFF65A30D)},
    {'id': 99, 'name': 'Doc', 'color': const Color(0xFF16A34A)},
    {'id': 18, 'name': 'Drama', 'color': const Color(0xFF0D9488)},
    {'id': 10751, 'name': 'Family', 'color': const Color(0xFF0891B2)},
    {'id': 14, 'name': 'Fantasy', 'color': const Color(0xFF0284C7)},
    {'id': 36, 'name': 'History', 'color': const Color(0xFF2563EB)},
    {'id': 27, 'name': 'Horror', 'color': const Color(0xFF4F46E5)},
    {'id': 10402, 'name': 'Music', 'color': const Color(0xFF7C3AED)},
    {'id': 9648, 'name': 'Mystery', 'color': const Color(0xFF9333EA)},
    {'id': 10749, 'name': 'Romance', 'color': const Color(0xFFC026D3)},
    {'id': 878, 'name': 'Sci-Fi', 'color': const Color(0xFFDB2777)},
    {'id': 53, 'name': 'Thriller', 'color': const Color(0xFFE11D48)},
  ];

  final List<Map<String, dynamic>> _tvGenres = [
    {'id': 10759, 'name': 'Action', 'color': const Color(0xFFDC2626)},
    {'id': 16, 'name': 'Animation', 'color': const Color(0xFFD97706)},
    {'id': 35, 'name': 'Comedy', 'color': const Color(0xFFCA8A04)},
    {'id': 80, 'name': 'Crime', 'color': const Color(0xFF65A30D)},
    {'id': 99, 'name': 'Doc', 'color': const Color(0xFF16A34A)},
    {'id': 18, 'name': 'Drama', 'color': const Color(0xFF0D9488)},
    {'id': 10751, 'name': 'Family', 'color': const Color(0xFF0891B2)},
    {'id': 10765, 'name': 'Sci-Fi', 'color': const Color(0xFFDB2777)},
    {'id': 9648, 'name': 'Mystery', 'color': const Color(0xFF9333EA)},
    {'id': 10764, 'name': 'Reality', 'color': const Color(0xFFF59E0B)},
  ];

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _loadContent();
    _listenToAuthChanges();
  }

  Future<void> _checkForUpdate() async {
    if (SettingsService().isOffline) return;
    try {
      final config = await _api.loadConfig();
      SettingsService().updateFromConfig(config);
      
      // Use new structured update check
      final info = await UpdateService().checkForUpdate(
        caffeineApiUrl,
        env: environment,
      );
      
      debugPrint('[HomeScreen] 🏁 Structured Update check result: available=${info.isUpdateAvailable}, version=${info.latestVersion}, forced=${info.isForced}');
      if (mounted) {
        setState(() => _updateInfo = info);
        // If forced, jump to update screen immediately
        if (info.isUpdateAvailable && info.isForced) {
           Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => UpdateScreen(updateInfo: info)),
          );
        }
      }
    } catch (e) {
      debugPrint('[HomeScreen] ⚠️ Error checking for update: $e');
    }
  }

  void _listenToAuthChanges() {
    _authSubscription?.cancel();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.signedIn || event == AuthChangeEvent.signedOut || event == AuthChangeEvent.tokenRefreshed) {
        debugPrint('[HomeScreen] 👤 Auth state changed: $event. Refreshing content.');
        _loadContent();
      }
    });
  }

  void _onScroll() {
    if (!mounted) return;
    final offset = _scrollController.offset;
    final inView = offset < 400; // Threshold for hero visibility
    if (inView != _isHeroInView) {
      if (inView) {
        _isHeroInView = true;
        _startAutoSlide();
      } else {
        _isHeroInView = false;
        _autoSlideTimer?.cancel();
        debugPrint('[HomeScreen] ⏸️ Hero out of view, pausing auto-slide');
      }
    }
  }

  Future<void> _loadContent({bool quiet = false, bool forceRefresh = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _history = null;
        _trending = null;
        _weeklyTrending = null;
        _popular = null;
        _topRated = null;
        _upcoming = null;
        _nowPlaying = null;
        _airingToday = null;
        _aiRecommendations = null;
        _tvRecommendations = null;
        _tvRecommendationsTitle = null;
        _watchingShows = null;
      });
    }
    
    try {
      if (forceRefresh) {
        _checkForUpdate();
      } else {
         _checkForUpdate();
      }
      final isTv = _selectedCategory == 'TV Shows';
      
      if (isTv) {
        final results = await Future.wait([
          _historyService.getHistory(mediaType: 'tv', forceRefresh: forceRefresh),
          _api.fetchTrendingTv(),
          _api.fetchPopularTv(),
          _api.fetchTopRatedTv(),
          _api.fetchAiringToday(),
          _recService.getRecommendations(mediaType: 'tv'),
          _historyService.getRecentlyWatchedShows(forceRefresh: forceRefresh),
        ]);

        final history = results[0] as List<Map<String, dynamic>>;
        final trending = results[1] as TvListResponse;
        final popular = results[2] as TvListResponse;
        final topRated = results[3] as TvListResponse;
        final airingToday = results[4] as TvListResponse;
        final aiResult = results[5] as RecommendationResult;
        final watchingShows = results[6] as List<Map<String, dynamic>>;
        debugPrint('[HomeScreen] 📺 Found ${watchingShows.length} watching shows');

        // --- Process "Up Next" Logic (Next Episode) ---
        final List<Map<String, dynamic>> upNextItems = [];
        final now = DateTime.now();
        
        bool isEpReleased(String? airDate) {
          if (airDate == null || airDate.isEmpty) return false;
          try {
            return DateTime.parse(airDate).isBefore(now.add(const Duration(days: 1)));
          } catch (_) {
            return false;
          }
        }

        for (var originalShow in watchingShows) {
          // Rule: Only show episodes in Up Next if the previous episode was completed
          if (originalShow['is_completed'] == true) {
            try {
              final show = Map<String, dynamic>.from(originalShow);
              final showId = show['id'];
              final seasonNum = show['season_num'] as int? ?? 1;
              final episodeNum = show['episode_num'] as int? ?? 1;

              // Check if there's a next episode in the same season
              final seasonDetail = await _api.fetchSeasonDetail(showId, seasonNum);
              TvEpisode? nextEp;
              for (var e in seasonDetail.episodes) {
                if (e.episodeNumber == episodeNum + 1) {
                  nextEp = e;
                  break;
                }
              }

              if (nextEp != null && isEpReleased(nextEp.airDate)) {
                show['episode_num'] = nextEp.episodeNumber;
                show['episode_name'] = nextEp.name;
                show['is_completed'] = false;
                upNextItems.add(show);
              } else if (nextEp == null) {
                // Check if there's a next season
                final tvDetail = await _api.fetchTvDetail(showId);
                if (seasonNum < (tvDetail.numberOfSeasons ?? 0)) {
                  final nextSeasonDetail = await _api.fetchSeasonDetail(showId, seasonNum + 1);
                  if (nextSeasonDetail.episodes.isNotEmpty) {
                    final firstEp = nextSeasonDetail.episodes.first;
                    if (isEpReleased(firstEp.airDate)) {
                      show['season_num'] = seasonNum + 1;
                      show['episode_num'] = firstEp.episodeNumber;
                      show['episode_name'] = firstEp.name;
                      show['is_completed'] = false;
                      upNextItems.add(show);
                    }
                  }
                }
              }
              // If we didn't find a next episode/season, we don't add it to upNextItems (user is caught up)
            } catch (e) {
              debugPrint('[HomeScreen] ❌ Error calculating next episode: $e');
            }
          }
          if (upNextItems.length >= 10) break;
        }

         List<MovieListItem>? tvRecommendations;
        String? tvRecommendationsTitle;

        if (history.isNotEmpty) {
          final lastTv = history.firstWhere((h) => h['media_id'] != null, orElse: () => {});
          if (lastTv.isNotEmpty) {
            try {
              final recs = await _api.fetchTvRecommendations(lastTv['media_id']);
              tvRecommendations = recs.results.map((t) => MovieListItem(
                id: t.id,
                title: t.name,
                posterPath: t.posterPath,
                backdropPath: t.backdropPath,
                overview: t.overview,
              )).toList();
              tvRecommendationsTitle = 'Because you watched ${lastTv['title']}';
            } catch (e) {
              debugPrint('[HomeScreen] ❌ Error loading TV recommendations: $e');
            }
          }
        }

        final trendingList = trending.results.take(5).map((t) => MovieListItem(
          id: t.id,
          title: t.name,
          posterPath: t.posterPath,
          backdropPath: t.backdropPath,
          overview: t.overview,
        )).toList();

        _precacheImages(trendingList);

        if (mounted) {
          setState(() {
            _history = history;
            _aiRecommendations = aiResult.items;
            _aiAnchorTitle = aiResult.anchorTitle;
            _tvRecommendations = tvRecommendations;
            _tvRecommendationsTitle = tvRecommendationsTitle;
            _watchingShows = upNextItems;
            
            if (trendingList.isNotEmpty) {
              final first = trendingList.first;
              _focusedMovie = MovieDetail(
                id: first.id,
                title: first.title,
                overview: first.overview,
                posterPath: first.posterPath,
                backdropPath: first.backdropPath,
                voteAverage: first.voteAverage,
              );
              
              _trending = trendingList;

              _weeklyTrending = trending.results.map((t) => MovieListItem(
                id: t.id,
                title: t.name,
                posterPath: t.posterPath,
                backdropPath: t.backdropPath,
                overview: t.overview,
              )).toList();
            }
            
            _popular = popular.results.map((t) => MovieListItem(
              id: t.id,
              title: t.name,
              posterPath: t.posterPath,
              backdropPath: t.backdropPath,
              overview: t.overview,
            )).toList();

            _topRated = topRated.results.map((t) => MovieListItem(
              id: t.id,
              title: t.name,
              posterPath: t.posterPath,
              backdropPath: t.backdropPath,
              overview: t.overview,
            )).toList();

            _airingToday = airingToday.results.map((t) => MovieListItem(
              id: t.id,
              title: t.name,
              posterPath: t.posterPath,
              backdropPath: t.backdropPath,
              overview: t.overview,
            )).toList();
          });
          _startAutoSlide();
        }
      } else {
        final results = await Future.wait([
          _historyService.getHistory(mediaType: 'movie', forceRefresh: forceRefresh),
          _api.fetchTrendingMovies(),
          _api.fetchPopularMovies(),
          _api.fetchTopRatedMovies(),
          _api.fetchUpcomingMovies(),
          _api.fetchNowPlayingMovies(),
          _recService.getRecommendations(mediaType: 'movie'),
        ]);

        final history = results[0] as List<Map<String, dynamic>>;
        final trending = results[1] as MovieListResponse;
        final popular = results[2] as MovieListResponse;
        final topRated = results[3] as MovieListResponse;
        final upcoming = results[4] as MovieListResponse;
        final nowPlaying = results[5] as MovieListResponse;
        final aiResult = results[6] as RecommendationResult;

        final today = DateTime.now();
        bool isReleased(MovieListItem m) {
          if (m.releaseDate == null || m.releaseDate!.isEmpty) return false;
          try {
            return DateTime.parse(m.releaseDate!).isBefore(today.add(const Duration(days: 1)));
          } catch (_) {
            return false;
          }
        }

        final releasedTrending = trending.results.where(isReleased).toList();
        final releasedPopular = popular.results.where(isReleased).toList();
        final trendingList = releasedTrending.take(5).toList();

        _precacheImages(trendingList);
        
        if (mounted) {
          setState(() {
            _history = history;
            _aiRecommendations = aiResult.items;
            _aiAnchorTitle = aiResult.anchorTitle;
            if (trendingList.isNotEmpty) {
              final first = trendingList.first;
              _focusedMovie = MovieDetail(
                id: first.id,
                title: first.title,
                overview: first.overview,
                posterPath: first.posterPath,
                backdropPath: first.backdropPath,
                voteAverage: first.voteAverage,
              );
              _trending = trendingList;
              _weeklyTrending = releasedTrending;
            }
            _popular = releasedPopular;
            _topRated = topRated.results;
            _upcoming = upcoming.results;
            _nowPlaying = nowPlaying.results;
          });
          _startAutoSlide();
        }
      }

      // --- Featured Live Event ---
      MovieListItem? featuredItem;
      if (SettingsService().sportsEnabled) {
        try {
          final featured = await Supabase.instance.client
              .from('live_streams')
              .select('*')
              .eq('is_featured', true)
              .maybeSingle();

          if (featured != null) {
            final streamUrl = featured['video_url'] ?? '';
            final sport = featured['sport'] ?? 'Sports';
            _liveStreamUrls[-100] = streamUrl;

            featuredItem = MovieListItem(
              id: -100, // Special ID for live events
              title: featured['title'],
              overview: "Experience the excitement of $sport live on Caffeine TV. Watch ${featured['title']} now!",
              posterPath: featured['poster_url'] ?? featured['thumbnail_url'],
              backdropPath: featured['poster_url'] ?? featured['thumbnail_url'],
              mediaType: 'live',
            );
          }
        } catch (e) {
          debugPrint('[HomeScreen] ❌ Error fetching featured event: $e');
        }
      }

      if (mounted) {
        if (featuredItem != null && _trending != null) {
          _trending!.insert(0, featuredItem);
          // If the slider was just loaded, refocus on the featured item
          if (_trendingIndex == 0) {
            _focusedMovie = MovieDetail(
              id: featuredItem.id,
              title: featuredItem.title,
              overview: featuredItem.overview,
              posterPath: featuredItem.posterPath,
              backdropPath: featuredItem.backdropPath,
              mediaType: featuredItem.mediaType,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[HomeScreen] ❌ Error loading content: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reloadHistory({bool forceRefresh = false}) async {
    final mediaType = _selectedCategory == 'TV Shows' ? 'tv' : 'movie';
    final h = await _historyService.getHistory(mediaType: mediaType, forceRefresh: forceRefresh);
    List<Map<String, dynamic>>? ws;
    if (mediaType == 'tv') {
      ws = await _historyService.getRecentlyWatchedShows(forceRefresh: forceRefresh);
    }
    if (mounted) {
      setState(() {
        _history = h;
        _watchingShows = ws;
      });
    }
  }

  void _precacheImages([List<MovieListItem>? items]) {
    final list = items ?? _trending;
    if (list == null) return;
    for (var item in list) {
      if (item.backdropPath != null) {
        precacheImage(
          NetworkImage('https://image.tmdb.org/t/p/w1280${item.backdropPath}'),
          context,
        );
      }
    }
  }

  void _startAutoSlide() {
    _autoSlideTimer?.cancel();
    if (!_isHeroInView) return; // Don't start if not in view
    
    _autoSlideTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
      if (!mounted || _trending == null || _trending!.isEmpty || _loading || !_isHeroInView) {
        if (!_isHeroInView) timer.cancel();
        return;
      }
      
      setState(() {
        _trendingIndex = (_trendingIndex + 1) % _trending!.length;
        final item = _trending![_trendingIndex];
        _focusedMovie = MovieDetail(
          id: item.id,
          title: item.title,
          overview: item.overview,
          posterPath: item.posterPath,
          backdropPath: item.backdropPath,
          voteAverage: item.voteAverage,
        );
      });
    });
  }

  void _resetAutoSlide() {
    _startAutoSlide();
  }

  void resetToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
      );
    }
    setState(() {
      _trendingIndex = 0;
      if (_trending != null && _trending!.isNotEmpty) {
        final item = _trending![0];
        _focusedMovie = MovieDetail(
          id: item.id,
          title: item.title,
          overview: item.overview,
          posterPath: item.posterPath,
          backdropPath: item.backdropPath,
          voteAverage: item.voteAverage,
          mediaType: item.mediaType,
        );
      }
    });
    _resetAutoSlide();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _autoSlideTimer?.cancel();
    _authSubscription?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _updateFocusedMovie(int id, {bool isAuto = false, bool? isMovie}) async {
    final effectiveIsMovie = isMovie ?? (_selectedCategory != 'TV Shows');
    // If user interacts manually, reset the timer to avoid jumping
    if (!isAuto) {
      _resetAutoSlide();
      // Also update _trendingIndex to match manual selection if possible
      final idx = _trending?.indexWhere((m) => m.id == id) ?? -1;
      if (idx != -1) _trendingIndex = idx;
    }
    
    // Debounce the backdrop update to prevent jank during fast scrolling
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () async {
      try {
        if (!effectiveIsMovie) {
          final detail = await _api.fetchTvDetail(id);
          if (mounted) {
            setState(() {
              _focusedMovie = MovieDetail(
                id: detail.id,
                title: detail.name,
                overview: detail.overview,
                posterPath: detail.posterPath,
                backdropPath: detail.backdropPath,
                voteAverage: detail.voteAverage,
              );
            });
          }
        } else {
          final detail = await _api.fetchMovieDetail(id);
          if (mounted) {
            setState(() {
              _focusedMovie = detail;
            });
          }
        }
      } catch (_) {}
    });
  }

  double _scale(BuildContext context, double value) {
    final width = MediaQuery.of(context).size.width;
    return (value * width) / 1920;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFFE60000)));

    final s = (double v) => _scale(context, v);

    return Stack(
      children: [
        // Hero Background
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: _focusedMovie?.backdropPath != null
            ? Container(
                key: ValueKey(_focusedMovie!.id),
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: NetworkImage(
                      _focusedMovie!.backdropPath != null && _focusedMovie!.backdropPath!.startsWith('http')
                          ? _focusedMovie!.backdropPath!
                          : 'https://image.tmdb.org/t/p/w1280${_focusedMovie!.backdropPath}'
                    ),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                      const Color(0xFFEC1D24).withOpacity(0.35), // slightly more contrast
                      BlendMode.multiply,
                    ),
                  ),
                ),
              )
            : const SizedBox.expand(),
        ),
        // Red Cinematic Gradient
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.black.withOpacity(0.95),
                const Color(0xFF7F1D1D).withOpacity(0.6), // primary.900
                Colors.transparent,
              ],
              stops: const [0.0, 0.45, 0.8],
            ),
          ),
        ),
        // Horizontal Shadow Mask
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black54, Colors.transparent, Colors.black],
              stops: [0.0, 0.3, 1.0],
            ),
          ),
        ),
        // Content
        SingleChildScrollView(
          controller: _scrollController,
          primary: false, // Must be false if controller is provided
          padding: EdgeInsets.symmetric(horizontal: s(96), vertical: s(60)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopNav(context),
              _buildUpdateCard(context, s),
              SizedBox(height: s(150)),
              SizedBox(
                height: s(620), // Fixed height to prevent layout shifts
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.0, 0.05),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        )),
                        child: child,
                      ),
                    );
                  },
                  child: _focusedMovie == null 
                    ? const SizedBox.shrink()
                    : Column(
                        key: ValueKey('hero_content_${_focusedMovie!.id}'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Brand Label
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: s(12), vertical: s(4)),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEC1D24), // brand red
                              borderRadius: BorderRadius.circular(s(4)),
                            ),
                            child: Text(
                              _focusedMovie?.mediaType == 'live' ? 'LIVE NOW' : 'TRENDING', 
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: s(15),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          SizedBox(height: s(18)),
                          Text(
                            _focusedMovie?.title?.toUpperCase() ?? '',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: s(130),
                              fontWeight: FontWeight.w900,
                              letterSpacing: s(-4),
                              height: 0.9,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: s(24)),
                          SizedBox(
                            width: s(780),
                            child: Text(
                              _focusedMovie?.overview ?? '',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: s(22),
                                fontWeight: FontWeight.w400,
                                height: 1.4,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(height: s(72)),
                          Row(
                            children: [
                              _HeroButton(
                                label: 'Watch Now',
                                icon: Icons.play_arrow_outlined,
                                style: HeroButtonStyle.primary,
                                 onTap: () async {
                                  if (_isProcessing) return;
                                  _isProcessing = true;
                                  try {
                                    if (_focusedMovie!.mediaType == 'live') {
                                    final url = _liveStreamUrls[_focusedMovie!.id];
                                    if (url == null || url.isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Stream link not found yet. Try again later!'))
                                      );
                                      return;
                                    }
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) => PlayerScreen(
                                          url: url,
                                          title: _focusedMovie!.title ?? 'Live Event',
                                          item: null,
                                          isMovie: false,
                                        ),
                                      ),
                                    );
                                    return;
                                  }

                                  // Handle both Movies and TV Shows
                                  final Future<void>? push;
                                  if (_selectedCategory == 'TV Shows') {
                                     push = Navigator.of(context).push(
                                      MaterialPageRoute(builder: (context) => TvDetailScreen(tvId: _focusedMovie!.id)),
                                    );
                                  } else {
                                    push = Navigator.of(context).push(
                                      MaterialPageRoute(builder: (context) => MovieDetailScreen(movieId: _focusedMovie!.id)),
                                    );
                                  }
                                   push.then((_) async {
                                    // Give the player/service 2 seconds to finish any background saving 
                                    // before we force a refresh of the UI data.
                                    await Future.delayed(const Duration(seconds: 2));
                                    _reloadHistory(forceRefresh: true);
                                  });
                                  } finally {
                                    _isProcessing = false;
                                    if (mounted) setState(() {});
                                  }
                                },
                              ),
                              SizedBox(width: s(36)),
                              _HeroButton(
                                label: 'Favourite',
                                icon: Icons.favorite_border,
                                style: HeroButtonStyle.secondaryRed,
                                onTap: () {},
                              ),
                            ],
                          ),
                          SizedBox(height: s(48)),
                          _buildSliderIndicators(context),
                        ],
                      ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return SizeTransition(
                    sizeFactor: animation,
                    axisAlignment: -1.0,
                    child: FadeTransition(opacity: animation, child: child),
                  );
                },
                child: (_history == null || _history!.isEmpty)
                  ? const SizedBox.shrink()
                  : Column(
                      key: const ValueKey('continue_watching_section'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildContinueWatchingRow(context, s),
                        SizedBox(height: s(96)),
                      ],
                    ),
              ),
              _buildAiRecommendationsRow(context, s),
              if (_selectedCategory == 'TV Shows') ...[
                if (_tvRecommendations != null && _tvRecommendations!.isNotEmpty) ...[
                  SizedBox(height: s(96)),
                  _buildRow(context, _tvRecommendationsTitle ?? 'Recommended for You', _tvRecommendations),
                ],
                if (_watchingShows != null && _watchingShows!.isNotEmpty) ...[
                  SizedBox(height: s(96)),
                  RepaintBoundary(child: _buildUpNextRow(context, s)),
                ],
                SizedBox(height: s(96)),
                _buildGenreRow(context, s),
                SizedBox(height: s(96)),
                _buildRow(context, 'Popular shows this week', _weeklyTrending),
                SizedBox(height: s(96)),
                _buildProviderCards(context, s),
                SizedBox(height: s(96)),
                _buildAiringTodayRow(context, s),
                SizedBox(height: s(96)),
                _buildRow(context, 'Top Rated TV Shows', _topRated),
                SizedBox(height: s(96)),
                _buildRow(context, 'Popular TV Shows', _popular),
              ] else ...[
                SizedBox(height: s(96)),
                _buildRow(context, 'Popular movies this week', _weeklyTrending),
                SizedBox(height: s(96)),
                RepaintBoundary(child: _buildGenreRow(context, s)),
                SizedBox(height: s(96)),
                RepaintBoundary(child: _buildRow(context, 'Now Playing', _nowPlaying)),
                SizedBox(height: s(96)),
                RepaintBoundary(child: _buildProviderCards(context, s)),
                SizedBox(height: s(96)),
                RepaintBoundary(child: _buildRow(context, 'Top Rated Movies', _topRated)),
                SizedBox(height: s(96)),
                RepaintBoundary(child: _buildRow(context, 'Upcoming Movies', _upcoming)),
                SizedBox(height: s(96)),
                RepaintBoundary(child: _buildRow(context, 'Popular Movies', _popular)),
              ],
              SizedBox(height: s(150)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSliderIndicators(BuildContext context) {
    if (_trending == null || _trending!.isEmpty) return const SizedBox.shrink();
    final s = (double v) => _scale(context, v);
    
    // Limits the number of dots to show if trending list is long
    final displayCount = _trending!.length > 10 ? 10 : _trending!.length;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(displayCount, (i) {
        final isActive = i == _trendingIndex;
        return Padding(
          padding: EdgeInsets.only(right: s(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: isActive ? s(80) : s(40),
                height: s(4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(isActive ? 0.3 : 0.1),
                  borderRadius: BorderRadius.circular(s(2)),
                ),
                clipBehavior: Clip.antiAlias,
                child: isActive 
                  ? TweenAnimationBuilder<double>(
                      key: ValueKey('indicator_${_focusedMovie?.id}'),
                      tween: Tween<double>(begin: 0.0, end: 1.0),
                      duration: const Duration(seconds: 8),
                      builder: (context, value, _) {
                        return FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: value,
                          child: Container(
                            color: const Color(0xFFEC1D24), // brand red
                          ),
                        );
                      },
                    )
                  : null,
              ),
              const SizedBox(height: 4),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildTopNav(BuildContext context) {
    final s = (double v) => _scale(context, v);
    final categories = ['Movies', 'TV Shows'];
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(s(40)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: s(32), vertical: s(8)),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(s(40)),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: s(20),
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: categories.map((cat) {
                final isSelected = cat == _selectedCategory;
                return Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent && (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.select)) {
                      if (_selectedCategory != cat) {
                        setState(() {
                          _selectedCategory = cat;
                        });
                        _loadContent();
                      }
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Builder(
                    builder: (context) {
                      final focused = Focus.of(context).hasFocus;
                      return GestureDetector(
                        onTap: () {
                          if (_selectedCategory != cat) {
                            setState(() => _selectedCategory = cat);
                            _loadContent();
                          }
                        },
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: s(48), vertical: s(8)),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                cat,
                                style: TextStyle(
                                  color: focused ? Colors.white : (isSelected ? Colors.white : Colors.white38),
                                  fontSize: s(42),
                                  fontWeight: isSelected || focused ? FontWeight.w600 : FontWeight.w400,
                                ),
                              ),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: EdgeInsets.only(top: s(4)),
                                height: s(4),
                                width: focused ? s(64) : (isSelected ? s(42) : 0),
                                color: focused || isSelected ? const Color(0xFFEC1D24) : Colors.transparent,
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  /// Shows a dialog asking the user to resume from their saved position or start over.
  /// Returns the Duration to start at, or null if the dialog was dismissed.
  Future<Duration?> _showResumeDialog(BuildContext context, Duration saved, int durationMs) {
    final pos = _formatDuration(saved);
    final total = durationMs > 0 ? ' / ${_formatDuration(Duration(milliseconds: durationMs))}' : '';

    return showDialog<Duration>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Resume Playback',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'You watched up to $pos$total.',
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
        actions: [
          Focus(
            autofocus: true,
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  (event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.select)) {
                Navigator.of(ctx).pop(saved);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(saved),
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Continue from $pos'),
            ),
          ),
          const SizedBox(width: 8),
          Focus(
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  (event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.select)) {
                Navigator.of(ctx).pop(Duration.zero);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(Duration.zero),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white54,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Start Over'),
            ),
          ),
        ],
      ),
    ).then((v) => v); // returns null if dismissed via back button
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildContinueWatchingRow(BuildContext context, double Function(double) s) {
    if (_history == null) return const SizedBox.shrink();
    final validHistory = _history!.where((h) => h['media_id'] != null && h['title'] != null).toList();
    if (validHistory.isEmpty) return const SizedBox.shrink();

    // Deduplicate by media_id — keep only the most recent entry per title.
    // (Results are already sorted newest-first from getHistory().)
    final seenIds = <int>{};
    final dedupedHistory = validHistory.where((h) {
      final id = h['media_id'] as int;
      return seenIds.add(id); // add returns false if already present
    }).toList();
    if (dedupedHistory.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: s(72)),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Continue Watching',
              style: TextStyle(
                color: Colors.white,
                fontSize: s(48),
                fontWeight: FontWeight.w800,
              ),
            ),
            _HeroButton(
              label: 'Clear All',
              icon: Icons.delete_outline,
              style: HeroButtonStyle.secondaryWhite,
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF1A1A1A),
                    title: const Text('Clear History?', style: TextStyle(color: Colors.white)),
                    content: const Text('Do you want to clear all "Continue Watching" items for this category?', style: TextStyle(color: Colors.white70)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true), 
                        child: const Text('Clear', style: TextStyle(color: Color(0xFFE60000)))
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await _historyService.clearHistory(mediaType: _selectedCategory == 'TV Shows' ? 'tv' : 'movie');
                  if (_scrollController.hasClients) {
                    await _scrollController.animateTo(0, duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic);
                  }
                  setState(() {
                    _trendingIndex = 0;
                  });
                  _loadContent(); // Full refresh (non-quiet) to reset the UI feel
                }
              },
            ),
          ],
        ),
        SizedBox(height: s(42)),
        SizedBox(
          height: s(480),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            primary: false,
            itemCount: dedupedHistory.length,
            itemBuilder: (context, index) {
              final h = dedupedHistory[index];
              final isMovie = h['type'] == 'movie';
              final mediaId = h['media_id'] as int;
              
              String? subtitle;
              if (!isMovie) {
                final season = h['season_num'] as int?;
                final episode = h['episode_num'] as int?;
                final epName = h['episode_name'] as String?;
                if (season != null && episode != null) {
                  subtitle = 'S${season.toString().padLeft(2, '0')} E${episode.toString().padLeft(2, '0')}${epName != null ? ' • $epName' : ''}';
                }
              }

              return Padding(
                padding: EdgeInsets.only(right: s(36)),
                child: PosterCard(
                  posterPath: h['poster_path'],
                  title: h['title'] ?? '',
                  subtitle: subtitle,
                  onFocus: () => _updateFocusedMovie(mediaId, isMovie: isMovie),
                  onLongPress: () => _showItemContextMenu(
                    item: h,
                    isMovie: isMovie,
                    season: h['season_num'] as int?,
                    episode: h['episode_num'] as int?,
                    episodeId: h['id'],
                    episodeName: h['episode_name'],
                    showId: mediaId,
                  ),
                  onTap: () async {
                    if (_isProcessing) return;
                    _isProcessing = true;
                    try {
                      final positionMs = h['position_ms'] as int? ?? 0;
                    final durationMs = h['duration_ms'] as int? ?? 0;
                    final savedPosition = Duration(milliseconds: positionMs);

                    // Show resume dialog if there's a saved position
                    Duration? startAt;
                    if (positionMs > 0) {
                      startAt = await _showResumeDialog(context, savedPosition, durationMs);
                      if (startAt == null) return; // user dismissed
                    }

                    if (isMovie) {
                      final detail = await _api.fetchMovieDetail(mediaId);
                      if (!mounted) return;
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => VideoLoaderScreen(
                            movie: detail,
                            startPosition: startAt,
                          ),
                        ),
                      );
                    } else {
                      final detail = await _api.fetchTvDetail(h['media_id']);
                      if (!mounted) return;
                      
                      // If somehow season/episode are missing, go to detail screen instead of loader
                      if (h['season_num'] == null || h['episode_num'] == null) {
                        debugPrint('[HomeScreen] ⚠️ History for TV show ${h['title']} is missing season/episode. Going to detail screen.');
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => TvDetailScreen(tvId: h['media_id'])),
                        );
                      } else {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => VideoLoaderScreen(
                              tvShow: detail,
                              season: h['season_num'],
                              episode: h['episode_num'],
                              episodeId: h['id'],
                              episodeName: h['episode_name'],
                              startPosition: startAt,
                            ),
                          ),
                        );
                      }
                    }

                    // Refresh history so completed items disappear immediately
                    if (mounted) _loadContent(quiet: true, forceRefresh: true);
                    } finally {
                      _isProcessing = false;
                      if (mounted) setState(() {});
                    }
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGenreRow(BuildContext context, double Function(double) s) {
    final genres = _selectedCategory == 'TV Shows' ? _tvGenres : _movieGenres;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Browse by Genre',
          style: TextStyle(
            color: Colors.white,
            fontSize: s(48),
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: s(42)),
        SizedBox(
          height: s(120),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: genres.length,
            itemBuilder: (context, index) {
              final g = genres[index];
              final color = g['color'] as Color;
              return Padding(
                padding: EdgeInsets.only(right: s(24)),
                child: Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent && (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.select)) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GenreScreen(
                            genreId: g['id'],
                            genreName: g['name'],
                            isMovie: _selectedCategory != 'TV Shows',
                          ),
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
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => GenreScreen(
                                genreId: g['id'],
                                genreName: g['name'],
                                isMovie: _selectedCategory != 'TV Shows',
                              ),
                            ),
                          );
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: s(220),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                color.withValues(alpha: focused ? 1.0 : 0.6),
                                color.withValues(alpha: focused ? 0.8 : 0.3),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(s(16)),
                            border: Border.all(
                              color: focused ? Colors.white : Colors.white12,
                              width: s(focused ? 4 : 2),
                            ),
                            boxShadow: focused ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.5),
                                blurRadius: s(15),
                                spreadRadius: s(2),
                              )
                            ] : null,
                          ),
                          child: Text(
                            g['name'],
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: s(28),
                              fontWeight: focused ? FontWeight.w900 : FontWeight.w600,
                              letterSpacing: s(1),
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
      ],
    );
  }

  Widget _buildAiringTodayRow(BuildContext context, double Function(double) s) {

    if (_airingToday == null || _airingToday!.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    final dateLabel = '${_monthName(now.month)} ${now.day}, ${now.year}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Airing Today',
              style: TextStyle(
                color: Colors.white,
                fontSize: s(48),
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(width: s(24)),
            Padding(
              padding: EdgeInsets.only(bottom: s(6)),
              child: Text(
                dateLabel,
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: s(22),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: s(42)),
        SizedBox(
          height: s(480),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            primary: false,
            itemCount: _airingToday!.length,
            itemBuilder: (context, index) {
              final m = _airingToday![index];
              return Padding(
                padding: EdgeInsets.only(right: s(36)),
                child: PosterCard(
                  posterPath: m.posterPath,
                  title: m.title ?? '',
                  onFocus: () => _updateFocusedMovie(m.id),
                  onLongPress: () => _showItemContextMenu(item: m, isMovie: false),
                  onTap: () async {
                    if (_isProcessing) return;
                    _isProcessing = true;
                    try {
                      await Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => TvDetailScreen(tvId: m.id)),
                    );
                    if (mounted) _loadContent(quiet: true, forceRefresh: true);
                    } finally {
                      _isProcessing = false;
                      if (mounted) setState(() {});
                    }
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _monthName(int month) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return months[month - 1];
  }

  Widget _buildAiRecommendationsRow(BuildContext context, double Function(double) s) {
    if (_aiRecommendations == null || _aiRecommendations!.isEmpty) {
      return const SizedBox.shrink();
    }
    
    final String title;
    if (_aiAnchorTitle != null && _aiAnchorTitle!.isNotEmpty) {
      title = 'Because you watched $_aiAnchorTitle, we think you might like';
    } else {
      title = 'We think you might like';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: s(48),
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: s(24)),
            _HeroButton(
              label: 'Surprise Me',
              icon: Icons.auto_awesome,
              style: HeroButtonStyle.secondaryRed,
              onTap: () async {
                final situation = await _showSituationDialog(context);
                if (situation != null) {
                  setState(() => _loading = true);
                  final result = await _recService.getRecommendations(situation: situation);
                  if (mounted) {
                    setState(() {
                      _aiRecommendations = result.items;
                      _aiAnchorTitle = result.anchorTitle;
                      _loading = false;
                    });
                  }
                }
              },
            ),
          ],
        ),
        SizedBox(height: s(42)),
        SizedBox(
          height: s(480),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            primary: false,
            itemCount: _aiRecommendations!.length,
            itemBuilder: (context, index) {
              final m = _aiRecommendations![index];
              return Padding(
                padding: EdgeInsets.only(right: s(36)),
                child: PosterCard(
                  posterPath: m.posterPath,
                  title: m.title ?? '',
                  onFocus: () => _updateFocusedMovie(m.id),
                  onLongPress: () => _showItemContextMenu(
                    item: m, 
                    isMovie: _selectedCategory != 'TV Shows',
                  ),
                  onTap: () async {
                    if (_selectedCategory == 'TV Shows') {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => TvDetailScreen(tvId: m.id)),
                      );
                    } else {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => MovieDetailScreen(movieId: m.id)),
                      );
                    }
                    if (mounted) _loadContent(quiet: true);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildUpNextRow(BuildContext context, double Function(double) s) {
    if (_watchingShows == null || _watchingShows!.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Up Next',
          style: TextStyle(
            color: Colors.white,
            fontSize: s(48),
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: s(42)),
        SizedBox(
          height: s(520), // Increased height for subtitle
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            primary: false,
            itemCount: _watchingShows!.length,
            itemBuilder: (context, index) {
              final show = _watchingShows![index];
              final season = show['season_num'] as int?;
              final episode = show['episode_num'] as int?;
              final epName = show['episode_name'] as String?;
              
              String? subtitle;
              if (season != null && episode != null) {
                subtitle = 'S${season.toString().padLeft(2, '0')} E${episode.toString().padLeft(2, '0')}${epName != null ? ' • $epName' : ''}';
              }

              return Padding(
                padding: EdgeInsets.only(right: s(36)),
                child: PosterCard(
                  posterPath: show['poster_path'],
                  title: show['name'] ?? '',
                  subtitle: subtitle,
                  onFocus: () => _updateFocusedMovie(show['id'], isMovie: false),
                  onLongPress: () => _showItemContextMenu(
                    item: show,
                    isMovie: false,
                    season: season,
                    episode: episode,
                    showId: show['id'] as int?,
                  ),
                  onTap: () async {
                    if (season != null && episode != null) {
                      // Get show detail for VideoLoaderScreen
                      final detail = await _api.fetchTvDetail(show['id']);
                      if (!mounted) return;
                      
                      // Check if we have history for this specific episode to resume
                      final history = await _historyService.getHistory(mediaType: 'tv');
                      final itemHistory = history.firstWhere(
                        (h) => h['media_id'] == show['id'] && h['season_num'] == season && h['episode_num'] == episode,
                        orElse: () => {},
                      );

                      Duration? startAt;
                      if (itemHistory.isNotEmpty && (itemHistory['position_ms'] ?? 0) > 0) {
                        if (!mounted) return;
                        startAt = await _showResumeDialog(
                          context, 
                          Duration(milliseconds: itemHistory['position_ms']), 
                          itemHistory['duration_ms'] ?? 0
                        );
                        if (startAt == null) return;
                      }

                      if (!mounted) return;
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => VideoLoaderScreen(
                            tvShow: detail,
                            season: season,
                            episode: episode,
                            startPosition: startAt,
                          ),
                        ),
                      );
                    } else {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => TvDetailScreen(tvId: show['id'])),
                      );
                    }
                    if (mounted) _loadContent(quiet: true);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<String?> _showSituationDialog(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('What\'s the occasion?', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('e.g. "date night", "horror fans", "relaxing Sunday"', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Enter a situation...',
                hintStyle: TextStyle(color: Colors.white24),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE60000))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Get Recommendations', style: TextStyle(color: Color(0xFFE60000))),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateCard(BuildContext context, double Function(double) s) {
    if (_updateInfo == null || !_updateInfo!.isUpdateAvailable) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        SizedBox(height: s(48)),
        Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.select)) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => UpdateScreen(updateInfo: _updateInfo!)),
              );
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Builder(builder: (context) {
            final focused = Focus.of(context).hasFocus;
            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => UpdateScreen(updateInfo: _updateInfo!)),
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding: EdgeInsets.all(s(24)),
                decoration: BoxDecoration(
                  color: focused ? Colors.white : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(s(16)),
                  border: Border.all(
                    color: focused ? Colors.white : Colors.white12,
                    width: s(2),
                  ),
                  boxShadow: focused
                      ? [
                          BoxShadow(
                            color: Colors.amber.withValues(alpha: 0.3),
                            blurRadius: s(30),
                            spreadRadius: s(5),
                          )
                        ]
                      : [],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(s(12)),
                      decoration: BoxDecoration(
                        color: focused ? Colors.amber.withValues(alpha: 0.2) : Colors.amber.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.system_update_alt,
                        color: focused ? Colors.amber : Colors.amberAccent,
                        size: s(32),
                      ),
                    ),
                    SizedBox(width: s(24)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _updateInfo!.isForced ? 'Mandatory Update Required' : 'New Update Available',
                            style: TextStyle(
                              color: focused ? Colors.black : Colors.white,
                              fontSize: s(26),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Version ${_updateInfo!.latestVersion} is now available with new features and improvements.',
                            style: TextStyle(
                              color: focused ? Colors.black87 : Colors.white60,
                              fontSize: s(18),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: s(24)),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: s(20), vertical: s(10)),
                      decoration: BoxDecoration(
                        color: focused ? Colors.black : Colors.white10,
                        borderRadius: BorderRadius.circular(s(8)),
                      ),
                      child: Text(
                        'Update Now',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: s(18),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildRow(BuildContext context, String title, List<MovieListItem>? items) {
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    final s = (double v) => _scale(context, v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontSize: s(48),
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: s(42)),
        SizedBox(
          height: s(480),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            primary: false, 
            itemCount: items.length,
            itemBuilder: (context, index) {
              final m = items[index];
              return Padding(
                padding: EdgeInsets.only(right: s(36)),
                child: PosterCard(
                  posterPath: m.posterPath,
                  title: m.title ?? '',
                  onFocus: () => _updateFocusedMovie(m.id),
                  onLongPress: () => _showItemContextMenu(
                    item: m, 
                    isMovie: _selectedCategory != 'TV Shows',
                  ),
                  onTap: () async {
                    if (_selectedCategory == 'TV Shows') {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => TvDetailScreen(tvId: m.id)),
                      );
                    } else {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => MovieDetailScreen(movieId: m.id)),
                      );
                    }
                    if (mounted) _loadContent(quiet: true, forceRefresh: true);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
  Widget _buildProviderCards(BuildContext context, double Function(double) s) {
    final providers = [
      {'name': 'Netflix', 'id': 8, 'logo': 'assets/svg/Netflix.svg', 'isSvg': true, 'color': const Color(0xFFE50914)},
      {'name': 'Disney+', 'id': 337, 'logo': 'assets/svg/Disney.svg', 'isSvg': true, 'color': const Color(0xFF0063E5)},
      {'name': 'Prime Video', 'id': 9, 'logo': 'assets/svg/Amazon_Prime_Video_logo.svg', 'isSvg': true, 'color': const Color(0xFF00A8E1)},
      {'name': 'Max', 'id': 1899, 'logo': 'assets/svg/Max_logo.svg', 'isSvg': true, 'color': const Color(0xFF0047FF)},
    ];

    return SizedBox(
      height: s(220),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: providers.length,
        separatorBuilder: (_, __) => SizedBox(width: s(40)),
        itemBuilder: (context, index) {
          final p = providers[index];
          return Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent && (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.select)) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => ProviderScreen(
                  providerId: p['id'] as int,
                  providerName: p['name'] as String,
                )));
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Builder(
              builder: (context) {
                final focused = Focus.of(context).hasFocus;
                return GestureDetector(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => ProviderScreen(
                      providerId: p['id'] as int,
                      providerName: p['name'] as String,
                    )));
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(s(24)),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: s(360),
                        decoration: BoxDecoration(
                          color: focused 
                              ? Colors.white.withOpacity(0.15) 
                              : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(s(24)),
                          border: Border.all(
                            color: focused ? Colors.white : Colors.white10,
                            width: focused ? s(4) : s(2),
                          ),
                          boxShadow: focused ? [
                            BoxShadow(
                              color: (p['color'] as Color).withOpacity(0.3),
                              blurRadius: s(30),
                              spreadRadius: s(5),
                            )
                          ] : [],
                        ),
                    padding: EdgeInsets.all(s(20)),
                    child: Center(
                      child: p['isSvg'] == true
                          ? SvgPicture.asset(
                              p['logo'] as String,
                              height: s(100),
                              fit: BoxFit.contain,
                              placeholderBuilder: (BuildContext context) => Container(
                                padding: EdgeInsets.all(s(30)),
                                child: const CircularProgressIndicator(),
                              ),
                            )
                          : Image.network(
                              'https://image.tmdb.org/t/p/original${p['logo']}',
                              height: s(100),
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Text(
                                p['name'] as String,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: s(36),
                               fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}


enum HeroButtonStyle { primary, secondaryRed, secondaryWhite }

class _HeroButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final HeroButtonStyle style;
  final VoidCallback onTap;

  const _HeroButton({
    required this.label,
    required this.icon,
    required this.style,
    required this.onTap,
  });

  double _scale(BuildContext context, double value) {
    final width = MediaQuery.of(context).size.width;
    return (value * width) / 1920;
  }

  @override
  Widget build(BuildContext context) {
    final s = (double v) => _scale(context, v);

    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.select)) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          
          Color bgColor = Colors.transparent;
          Color borderColor = Colors.white24;
          Color textColor = Colors.white;

          if (style == HeroButtonStyle.primary) {
            bgColor = Colors.white;
            textColor = Colors.black;
            borderColor = Colors.transparent;
          } else if (style == HeroButtonStyle.secondaryRed) {
            borderColor = const Color(0xFFE60000);
          } else {
            borderColor = Colors.white;
          }

          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(horizontal: s(42), vertical: s(18)),
            decoration: BoxDecoration(
              color: bgColor.withOpacity(focused ? 0.8 : 1.0),
              borderRadius: BorderRadius.circular(s(12)),
              border: Border.all(
                color: focused ? Colors.white : borderColor,
                width: s(3.5),
              ),
              boxShadow: focused ? [
                BoxShadow(
                  color: Colors.white.withOpacity(0.3),
                  blurRadius: s(20),
                  spreadRadius: s(2),
                )
              ] : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: textColor, size: s(42)),
                SizedBox(width: s(18)),
                Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                    fontSize: s(30),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
