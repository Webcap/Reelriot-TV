import 'package:caffeine_core/caffeine_core.dart';
import 'package:reelriot_tv/screens/tv_detail_screen.dart';
import 'package:reelriot_tv/screens/movie_detail_screen.dart';
import 'package:reelriot_tv/screens/search_screen.dart';
import 'package:reelriot_tv/screens/provider_screen.dart';
import 'package:reelriot_tv/screens/favorites_screen.dart';
import 'package:reelriot_tv/screens/settings_screen.dart';
import 'package:reelriot_tv/screens/sports_screen.dart';
import 'package:reelriot_tv/services/api_service.dart';
import 'package:reelriot_tv/services/watch_history_service.dart';
import 'package:reelriot_tv/services/recommendation_service.dart';
import 'package:reelriot_tv/screens/video_loader_screen.dart';
import 'package:reelriot_tv/screens/player_screen.dart';
import 'package:reelriot_tv/env.dart';
import 'package:reelriot_tv/widgets/poster_card.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:reelriot_tv/widgets/exit_dialog.dart';
import 'package:reelriot_tv/services/settings_service.dart';
import 'package:reelriot_tv/services/update_service.dart';
import 'package:reelriot_tv/screens/update_screen.dart';
import 'dart:async';
import 'package:reelriot_tv/widgets/context_menu_dialog.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/widgets/home/home_nav_rail.dart';
import 'package:reelriot_tv/widgets/home/home_top_nav.dart';
import 'package:reelriot_tv/widgets/home/home_media_row.dart';
import 'package:reelriot_tv/widgets/home/home_continue_watching.dart';
import 'package:reelriot_tv/widgets/home/home_genres.dart';
import 'package:reelriot_tv/widgets/home/home_providers.dart';
import 'package:reelriot_tv/widgets/home/home_up_next.dart';
import 'package:reelriot_tv/widgets/home/home_hero_section.dart';
import 'package:reelriot_tv/widgets/home/home_hero_button.dart';
import 'package:reelriot_tv/widgets/home/home_airing_today.dart';
import 'package:reelriot_tv/widgets/home/home_ai_recommendations.dart';
import 'package:reelriot_tv/widgets/home/home_update_card.dart';
import 'package:reelriot_tv/screens/genre_screen.dart';

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
  final GlobalKey<SettingsScreenState> _settingsKey = GlobalKey<SettingsScreenState>();
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
    final tabs = _visibleTabs.map((t) => HomeTab(label: t.label, icon: t.icon)).toList();
    if (_selectedIndex >= tabs.length) {
      _selectedIndex = 1; // Default to Home
    }

    if (_navNodes.length < tabs.length) {
      _navNodes.addAll(List.generate(tabs.length - _navNodes.length, (_) => FocusNode()));
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) => _onBackInvoke(didPop),
      child: Scaffold(
        backgroundColor: const Color(0xFF000000),
        body: Row(
          children: [
            HomeNavRail(
              selectedIndex: _selectedIndex,
              navNodes: _navNodes,
              tabs: tabs,
              onTabSelected: (index) {
                if (mounted) setState(() => _selectedIndex = index);
                final tabLabel = tabs[index].label;
                if (tabLabel == 'Sports') {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _sportsKey.currentState?.load();
                  });
                } else if (tabLabel == 'Favorites') {
                  _favoritesKey.currentState?.refresh();
                } else if (tabLabel == 'Profile') {
                  _settingsKey.currentState?.refresh();
                }
              },
              onTabReset: (index) {
                if (tabs[index].label == 'Home') {
                  _homeKey.currentState?.resetToTop();
                } else if (tabs[index].label == 'Sports') {
                  _sportsKey.currentState?.load();
                } else if (tabs[index].label == 'Profile') {
                  _settingsKey.currentState?.refresh();
                }
              },
            ),
            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                children: [
                  const SearchScreen(),
                  RepaintBoundary(child: _MainHomeView(key: _homeKey)),
                  if (SettingsService().sportsEnabled) RepaintBoundary(child: SportsScreen(key: _sportsKey)),
                  SettingsScreen(key: _settingsKey),
                  FavoritesScreen(key: _favoritesKey),
                ],
              ),
            ),
          ],
        ),
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
  bool _aiLoading = false;
  String? get _aiRecommendationsTitle {
    if (_aiAnchorTitle != null && _aiAnchorTitle!.isNotEmpty) {
      return 'Because you watched $_aiAnchorTitle, we think you might like';
    }
    return 'We think you might like';
  }
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
        apiKey: caffeineApiKey,
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
        await _historyService.waitForPendingSaves();
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

        final upNextItems = await _processUpNext(watchingShows);

         List<MovieListItem>? tvRecommendations;
        String? tvRecommendationsTitle;
 
        if (history.isNotEmpty) {
          // Try up to 3 items from history to get recommendations
          final historyItems = history.where((h) {
            final isLive = h['type'] == 'live' || h['media_type'] == 'live';
            final title = (h['title'] ?? '').toString();
            final isSports = title.contains(' at ') || title.contains(' vs ');
            return h['media_id'] != null && !isLive && !isSports;
          }).take(3);
          for (final item in historyItems) {
            try {
              final recs = await _api.fetchTvRecommendations(item['media_id']);
              if (recs.results.isNotEmpty) {
                tvRecommendations = recs.results.map((t) => MovieListItem(
                  id: t.id,
                  title: t.name,
                  posterPath: t.posterPath,
                  backdropPath: t.backdropPath,
                  overview: t.overview,
                )).toList();
                tvRecommendationsTitle = 'Because you watched ${item['title']}';
                break; // Success!
              }
            } catch (e) {
              debugPrint('[HomeScreen] ⚠️ Recommendation attempt failed for "${item['title']}" (ID: ${item['media_id']}): $e');
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

      // --- Ads Integration ---
      List<MovieListItem> ads = [];
      if (SettingsService().adsEnabled || (kDebugMode && SettingsService().simulateAds)) {
        try {
          final results = await Supabase.instance.client
              .from('sponsorships')
              .select('*')
              .eq('is_active', true);
          
          for (var ad in results) {
            ads.add(MovieListItem(
              id: ad['id'].toString().hashCode,
              title: ad['title'],
              overview: ad['description'],
              posterPath: ad['image_url'],
              backdropPath: ad['image_url'],
              mediaType: 'ad',
              isSponsored: true,
            ));
          }
        } catch (e) {
          debugPrint('[HomeScreen] ❌ Error fetching ads: $e');
        }

        // Inject simulated ads if simulation is enabled
        if (kDebugMode && SettingsService().simulateAds) {
          if (ads.isEmpty) {
            ads.add(MovieListItem(
              id: 999901,
              title: 'Aurora Ultra: Power Redefined',
              overview: 'Experience unparalleled performance with the new Aurora Ultra series.',
              posterPath: 'https://caffeine.synqholdings.com/assets/images/simulated/poster_ad_1.png',
              backdropPath: 'https://caffeine.synqholdings.com/assets/images/simulated/poster_ad_1.png',
              mediaType: 'ad',
              isSponsored: true,
            ));
            ads.add(MovieListItem(
              id: 999902,
              title: 'CyberShield VPN',
              overview: 'Stay secure anywhere with our ultra-fast VPN service.',
              posterPath: 'https://caffeine.synqholdings.com/assets/images/simulated/poster_ad_2.png',
              backdropPath: 'https://caffeine.synqholdings.com/assets/images/simulated/poster_ad_2.png',
              mediaType: 'ad',
              isSponsored: true,
            ));
          }
        }
      }

      if (mounted) {
        setState(() {
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

          // Inject ads into rows
          if (ads.isNotEmpty && _popular != null && _popular!.length > 5) {
            _popular!.insert(2, ads[0]);
            if (ads.length > 1 && _topRated != null && _topRated!.length > 5) {
              _topRated!.insert(4, ads[1]);
            }
          }
        });
      }
    } catch (e) {
      debugPrint('[HomeScreen] ❌ Error loading content: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _processUpNext(List<Map<String, dynamic>> watchingShows) async {
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
        } catch (e) {
          debugPrint('[HomeScreen] ❌ Error calculating next episode: $e');
        }
      }
      if (upNextItems.length >= 10) break;
    }
    return upNextItems;
  }

  Future<void> _reloadHistory({bool forceRefresh = false}) async {
    if (forceRefresh) {
      await _historyService.waitForPendingSaves();
    }
    final mediaType = _selectedCategory == 'TV Shows' ? 'tv' : 'movie';
    final h = await _historyService.getHistory(mediaType: mediaType, forceRefresh: forceRefresh);
    List<Map<String, dynamic>>? upNext;
    if (mediaType == 'tv') {
      final watchingShows = await _historyService.getRecentlyWatchedShows(forceRefresh: forceRefresh);
      upNext = await _processUpNext(watchingShows);
    }
    if (mounted) {
      setState(() {
        _history = h;
        _watchingShows = upNext;
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

    double s(double v) => ResponsiveUtils.scale(context, v);

    return Stack(
      children: [
        HomeHeroSection(
          backgroundOnly: true,
          focusedMovie: _focusedMovie,
          trending: _trending,
          trendingIndex: _trendingIndex,
          liveStreamUrls: _liveStreamUrls,
          onWatchNow: () async {
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

              if (_selectedCategory == 'TV Shows') {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => TvDetailScreen(tvId: _focusedMovie!.id)),
                );
              } else {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => MovieDetailScreen(movieId: _focusedMovie!.id)),
                );
              }
              await _historyService.waitForPendingSaves();
              await Future.delayed(const Duration(seconds: 2));
              _reloadHistory(forceRefresh: true);
            } finally {
              _isProcessing = false;
              if (mounted) setState(() {});
            }
          },
          onFavorite: () {},
        ),
        // Content
        SingleChildScrollView(
          controller: _scrollController,
          primary: false,
          padding: EdgeInsets.symmetric(horizontal: s(96)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HomeTopNav(
                selectedCategory: _selectedCategory,
                onCategorySelected: (cat) {
                  setState(() => _selectedCategory = cat);
                  _loadContent();
                },
              ),
              if (_updateInfo != null) HomeUpdateCard(updateInfo: _updateInfo!),
              HomeHeroSection(
                contentOnly: true,
                focusedMovie: _focusedMovie,
                trending: _trending,
                trendingIndex: _trendingIndex,
                liveStreamUrls: _liveStreamUrls,
                onWatchNow: () async {
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

                    if (_selectedCategory == 'TV Shows') {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => TvDetailScreen(tvId: _focusedMovie!.id)),
                      );
                    } else {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => MovieDetailScreen(movieId: _focusedMovie!.id)),
                      );
                    }
                    await _historyService.waitForPendingSaves();
                    await Future.delayed(const Duration(seconds: 2));
                    _reloadHistory(forceRefresh: true);
                  } finally {
                    _isProcessing = false;
                    if (mounted) setState(() {});
                  }
                },
                onFavorite: () {},
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
              HomeAiRecommendationsRow(
                recommendations: _aiRecommendations,
                title: _aiRecommendationsTitle,
                loading: _aiLoading,
                onRefresh: () async {
                  final situation = await _showSituationDialog(context);
                  if (situation != null && situation.isNotEmpty) {
                    _loadAiRecommendations(situation: situation);
                  }
                },
                onFocus: (id) => _updateFocusedMovie(id),
                onTap: (m) => _navigateToDetail(m),
                onLongPress: (m) => _showItemContextMenu(item: m, isMovie: _selectedCategory != 'TV Shows'),
              ),
              if (_selectedCategory == 'TV Shows') ...[
                if (_tvRecommendations != null && _tvRecommendations!.isNotEmpty) ...[
                  SizedBox(height: s(96)),
                  HomeMediaRow(
                    title: _tvRecommendationsTitle ?? 'Recommended for You',
                    items: _tvRecommendations,
                    onFocus: (id) => _updateFocusedMovie(id),
                    onTap: (m) => _navigateToDetail(m),
                    onLongPress: (m) => _showItemContextMenu(item: m, isMovie: false),
                  ),
                ],
                if (_watchingShows != null && _watchingShows!.isNotEmpty) ...[
                  SizedBox(height: s(96)),
                  RepaintBoundary(child: _buildUpNextRow(context, s)),
                ],
                SizedBox(height: s(96)),
                HomeGenresRow(
                  genres: _tvGenres,
                  onGenreTap: (g) => _navigateToGenre(g),
                ),
                SizedBox(height: s(96)),
                HomeMediaRow(
                  title: 'Popular shows this week',
                  items: _weeklyTrending,
                  onFocus: (id) => _updateFocusedMovie(id),
                  onTap: (m) => _navigateToDetail(m),
                  onLongPress: (m) => _showItemContextMenu(item: m, isMovie: false),
                ),
                SizedBox(height: s(96)),
                HomeProvidersRow(onProviderTap: (p) => _navigateToProvider(p)),
                SizedBox(height: s(96)),
                HomeAiringTodayRow(
                  airingToday: _airingToday,
                  dateLabel: _airingToday != null && _airingToday!.isNotEmpty 
                      ? '${_monthName(DateTime.now().month)} ${DateTime.now().day}, ${DateTime.now().year}' 
                      : null,
                  onFocus: (id) => _updateFocusedMovie(id),
                  onTap: (m) => _navigateToDetail(m),
                  onLongPress: (m) => _showItemContextMenu(item: m, isMovie: false),
                ),
                SizedBox(height: s(96)),
                HomeMediaRow(
                  title: 'Top Rated TV Shows',
                  items: _topRated,
                  onFocus: (id) => _updateFocusedMovie(id),
                  onTap: (m) => _navigateToDetail(m),
                  onLongPress: (m) => _showItemContextMenu(item: m, isMovie: false),
                ),
                SizedBox(height: s(96)),
                HomeMediaRow(
                  title: 'Popular TV Shows',
                  items: _popular,
                  onFocus: (id) => _updateFocusedMovie(id),
                  onTap: (m) => _navigateToDetail(m),
                  onLongPress: (m) => _showItemContextMenu(item: m, isMovie: false),
                ),
              ] else ...[
                SizedBox(height: s(96)),
                HomeMediaRow(
                  title: 'Popular movies this week',
                  items: _weeklyTrending,
                  onFocus: (id) => _updateFocusedMovie(id),
                  onTap: (m) => _navigateToDetail(m),
                  onLongPress: (m) => _showItemContextMenu(item: m, isMovie: true),
                ),
                SizedBox(height: s(96)),
                RepaintBoundary(
                  child: HomeGenresRow(
                    genres: _movieGenres,
                    onGenreTap: (g) => _navigateToGenre(g),
                  ),
                ),
                SizedBox(height: s(96)),
                RepaintBoundary(
                  child: HomeMediaRow(
                    title: 'Now Playing',
                    items: _nowPlaying,
                    onFocus: (id) => _updateFocusedMovie(id),
                    onTap: (m) => _navigateToDetail(m),
                    onLongPress: (m) => _showItemContextMenu(item: m, isMovie: true),
                  ),
                ),
                SizedBox(height: s(96)),
                RepaintBoundary(child: HomeProvidersRow(onProviderTap: (p) => _navigateToProvider(p))),
                SizedBox(height: s(96)),
                RepaintBoundary(
                  child: HomeMediaRow(
                    title: 'Top Rated Movies',
                    items: _topRated,
                    onFocus: (id) => _updateFocusedMovie(id),
                    onTap: (m) => _navigateToDetail(m),
                    onLongPress: (m) => _showItemContextMenu(item: m, isMovie: true),
                  ),
                ),
                SizedBox(height: s(96)),
                RepaintBoundary(
                  child: HomeMediaRow(
                    title: 'Upcoming Movies',
                    items: _upcoming,
                    onFocus: (id) => _updateFocusedMovie(id),
                    onTap: (m) => _navigateToDetail(m),
                    onLongPress: (m) => _showItemContextMenu(item: m, isMovie: true),
                  ),
                ),
                SizedBox(height: s(96)),
                RepaintBoundary(
                  child: HomeMediaRow(
                    title: 'Popular Movies',
                    items: _popular,
                    onFocus: (id) => _updateFocusedMovie(id),
                    onTap: (m) => _navigateToDetail(m),
                    onLongPress: (m) => _showItemContextMenu(item: m, isMovie: true),
                  ),
                ),
              ],
              SizedBox(height: s(150)),
            ],
          ),
        ),
      ],
    );
  }

  void _navigateToDetail(MovieListItem m) async {
    final isTv = _selectedCategory == 'TV Shows';
    if (isTv) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => TvDetailScreen(tvId: m.id)),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => MovieDetailScreen(movieId: m.id)),
      );
    }
    await _historyService.waitForPendingSaves();
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) _loadContent(quiet: true, forceRefresh: true);
  }

  void _navigateToGenre(Map<String, dynamic> g) {
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
  }

  void _navigateToProvider(Map<String, dynamic> p) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ProviderScreen(
      providerId: p['id'] as int,
      providerName: p['name'] as String,
    )));
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

  Future<void> _loadAiRecommendations({String? situation}) async {
    setState(() => _aiLoading = true);
    try {
      final result = await _recService.getRecommendations(
        mediaType: _selectedCategory == 'TV Shows' ? 'tv' : 'movie',
        situation: situation,
      );
      if (mounted) {
        setState(() {
          _aiRecommendations = result.items;
          _aiAnchorTitle = result.anchorTitle;
        });
      }
    } catch (e) {
      debugPrint('[HomeScreen] ❌ Error loading AI recommendations: $e');
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  String _monthName(int month) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return months[month - 1];
  }

  Widget _buildContinueWatchingRow(BuildContext context, double Function(double) s) {
    if (_history == null) return const SizedBox.shrink();
    final validHistory = _history!.where((h) => h['media_id'] != null && h['title'] != null).toList();
    if (validHistory.isEmpty) return const SizedBox.shrink();

    final seenIds = <int>{};
    final dedupedHistory = validHistory.where((h) {
      final id = h['media_id'] as int;
      return seenIds.add(id);
    }).toList();

    return HomeContinueWatchingRow(
      history: dedupedHistory,
      onFocus: (id, isMovie) => _updateFocusedMovie(id, isMovie: isMovie),
      onClearAll: () async {
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
          _loadContent();
        }
      },
      onTap: (h) async {
        if (_isProcessing) return;
        _isProcessing = true;
        try {
          final isMovie = h['type'] == 'movie';
          final mediaId = h['media_id'] as int;
          final positionMs = h['position_ms'] as int? ?? 0;
          final durationMs = h['duration_ms'] as int? ?? 0;
          final savedPosition = Duration(milliseconds: positionMs);

          Duration? startAt;
          if (positionMs > 0) {
            startAt = await _showResumeDialog(context, savedPosition, durationMs);
            if (startAt == null) return;
          }

          if (isMovie) {
            final detail = await _api.fetchMovieDetail(mediaId);
            if (!context.mounted) return;
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
            
            if (h['season_num'] == null || h['episode_num'] == null) {
              if (!context.mounted) return;
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => TvDetailScreen(tvId: h['media_id'])),
              );
            } else {
              if (!context.mounted) return;
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

          await _historyService.waitForPendingSaves();
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) _loadContent(quiet: true, forceRefresh: true);
        } finally {
          _isProcessing = false;
          if (mounted) setState(() {});
        }
      },
      onLongPress: (h) => _showItemContextMenu(
        item: h,
        isMovie: h['type'] == 'movie',
        season: h['season_num'] as int?,
        episode: h['episode_num'] as int?,
        episodeId: h['id'],
        episodeName: h['episode_name'],
        showId: h['media_id'],
      ),
    );
  }


  Widget _buildUpNextRow(BuildContext context, double Function(double) s) {
    if (_watchingShows == null || _watchingShows!.isEmpty) return const SizedBox.shrink();

    return HomeUpNextRow(
      watchingShows: _watchingShows!,
      onFocus: (id) => _updateFocusedMovie(id, isMovie: false),
      onLongPress: (show) => _showItemContextMenu(
        item: show,
        isMovie: false,
        season: show['season_num'] as int?,
        episode: show['episode_num'] as int?,
        showId: show['id'] as int?,
      ),
      onTap: (show) async {
        final season = show['season_num'] as int?;
        final episode = show['episode_num'] as int?;
        
        if (season != null && episode != null) {
          final detail = await _api.fetchTvDetail(show['id']);
          if (!mounted) return;
          
          final history = await _historyService.getHistory(mediaType: 'tv');
          final itemHistory = history.firstWhere(
            (h) => h['media_id'] == show['id'] && h['season_num'] == season && h['episode_num'] == episode,
            orElse: () => {},
          );

          Duration? startAt;
          if (itemHistory.isNotEmpty && (itemHistory['position_ms'] ?? 0) > 0) {
            if (!context.mounted) return;
            startAt = await _showResumeDialog(
              context,
              Duration(milliseconds: itemHistory['position_ms']), 
              itemHistory['duration_ms'] ?? 0
            );
            if (startAt == null) return;
          }

          if (!context.mounted) return;
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
        await _historyService.waitForPendingSaves();
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) _loadContent(quiet: true, forceRefresh: true);
      },
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


}


