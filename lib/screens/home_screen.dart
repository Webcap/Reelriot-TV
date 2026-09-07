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
import 'package:url_launcher/url_launcher.dart';
import 'package:reelriot_tv/widgets/native_ad_banner.dart';
import 'package:reelriot_tv/widgets/native_ad_poster_card.dart';
import 'package:reelriot_tv/models/ad.dart' as model;
import 'package:reelriot_tv/widgets/home/home_media_row.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'package:reelriot_tv/widgets/home/home_top_bar.dart';
import 'package:reelriot_tv/widgets/home/cinematic_hero.dart';
import 'package:reelriot_tv/widgets/home/home_continue_watching.dart';
import 'package:reelriot_tv/widgets/home/home_genres.dart';
import 'package:reelriot_tv/widgets/home/home_providers.dart';
import 'package:reelriot_tv/widgets/home/home_up_next.dart';
import 'package:reelriot_tv/widgets/long_press_focus.dart';
import 'package:reelriot_tv/widgets/home/home_airing_today.dart';
import 'package:reelriot_tv/widgets/home/home_ai_recommendations.dart';
import 'package:reelriot_tv/widgets/home/home_update_card.dart';
import 'package:reelriot_tv/screens/genre_screen.dart';
import 'package:reelriot_tv/models/discovery_section.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/widgets/tv_skeleton_loader.dart';

// Home dashboard — canon direction (see the note atop
// lib/theme/dashboard_theme.dart). Clean, restrained streaming-TV
// dashboard; no themed visual metaphor.

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  static HomeScreenState? of(BuildContext context) =>
      context.findAncestorStateOfType<HomeScreenState>();

  int _selectedIndex = 1;
  String _currentCategory = 'Home';
  final ValueNotifier<double> _homeScrollNotifier = ValueNotifier<double>(0.0);

  final GlobalKey<SearchScreenState> _searchKey =
      GlobalKey<SearchScreenState>();
  final GlobalKey<FavoritesScreenState> _favoritesKey =
      GlobalKey<FavoritesScreenState>();
  final GlobalKey<SportsScreenState> _sportsKey =
      GlobalKey<SportsScreenState>();
  final GlobalKey<SettingsScreenState> _settingsKey =
      GlobalKey<SettingsScreenState>();
  final GlobalKey<_MainHomeViewState> _homeKey =
      GlobalKey<_MainHomeViewState>();
  late List<FocusNode> _navNodes;

  void setIndex(int index) {
    if (mounted) {
      setState(() => _selectedIndex = index);
    }
  }

  @override
  void initState() {
    super.initState();
    // 7 navigation nodes: Categories (Home, Movies, Series, [Sports]) + Actions (Search, Favorites, Profile)
    _navNodes = List.generate(7, (_) => FocusNode());
    SettingsService().addListener(_onSettingsChanged);

    // Request initial focus on the first category item (HOME)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_navNodes.isNotEmpty) {
        _navNodes[0].requestFocus();
      }
    });
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SettingsService().removeListener(_onSettingsChanged);
    _homeScrollNotifier.dispose();
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
      if (_selectedIndex == 1) {
        if (_currentCategory == 'Movies') {
          _navNodes[1].requestFocus();
        } else if (_currentCategory == 'TV Shows') {
          _navNodes[2].requestFocus();
        } else {
          _navNodes[0].requestFocus();
        }
      } else if (_selectedIndex == 0) {
        _navNodes[SettingsService().sportsEnabled ? 4 : 3].requestFocus();
      } else {
        _navNodes[0].requestFocus();
      }
      return;
    }

    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const ExitDialog(),
    );

    if (shouldExit == true) {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);
    final isHomeTab = _selectedIndex == 1;
    final topNavHeight = s(DashboardTheme.topNavHeight);
    final sportsEnabled = SettingsService().sportsEnabled;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) => _onBackInvoke(didPop),
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent && TvKeys.isBack(event.logicalKey)) {
              _onBackInvoke(false);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Scaffold(
            backgroundColor: DashboardTheme.canvasBlack,
            body: Stack(
              children: [
                IndexedStack(
                  index: _selectedIndex,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: topNavHeight),
                      child: SearchScreen(key: _searchKey),
                    ),
                    _buildMainView(),
                    if (sportsEnabled)
                      Padding(
                        padding: EdgeInsets.only(top: topNavHeight),
                        child: RepaintBoundary(
                          child: SportsScreen(key: _sportsKey),
                        ),
                      ),
                    Padding(
                      padding: EdgeInsets.only(top: topNavHeight),
                      child: SettingsScreen(key: _settingsKey),
                    ),
                    Padding(
                      padding: EdgeInsets.only(top: topNavHeight),
                      child: FavoritesScreen(key: _favoritesKey),
                    ),
                  ],
                ),

                // Floating Cinematic Top Nav Bar
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ValueListenableBuilder<double>(
                    valueListenable: _homeScrollNotifier,
                    builder: (context, scrollOffset, _) {
                      return HomeTopBar(
                        scrollOffset: scrollOffset,
                        isHomeTab: isHomeTab,
                        selectedCategory: _currentCategory,
                        selectedTabIndex: _selectedIndex,
                        navNodes: _navNodes,
                        onCategorySelected: (cat) {
                          setState(() {
                            _currentCategory = cat;
                            _selectedIndex = 1;
                          });
                          _homeKey.currentState?.setCategory(cat);
                          _homeKey.currentState?.scrollToTop();
                        },
                        onTabSelected: (index) {
                          if (mounted) setState(() => _selectedIndex = index);
                          if (index == 2 && sportsEnabled) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _sportsKey.currentState?.load();
                            });
                          } else if (index == (sportsEnabled ? 4 : 3)) {
                            _favoritesKey.currentState?.refresh();
                          } else if (index == (sportsEnabled ? 3 : 2)) {
                            _settingsKey.currentState?.refresh();
                          }
                        },
                        onTabReset: (index) {
                          if (index == 1) {
                            _homeKey.currentState?.resetToTop();
                          } else if (index == 2 && sportsEnabled) {
                            _sportsKey.currentState?.load();
                          } else if (index == (sportsEnabled ? 3 : 2)) {
                            _settingsKey.currentState?.refresh();
                          }
                        },
                        onMoveIntoContent: () {
                          if (_selectedIndex == 0) {
                            _searchKey.currentState?.requestFocus();
                          } else if (_selectedIndex == 1) {
                            _homeKey.currentState?.requestFocus();
                          } else if (_selectedIndex == 2 && sportsEnabled) {
                            _sportsKey.currentState?.requestFocus();
                          } else if (_selectedIndex == (sportsEnabled ? 3 : 2)) {
                            _settingsKey.currentState?.requestFocus();
                          } else {
                            _favoritesKey.currentState?.requestFocus();
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _focusNavNode() {
    _homeKey.currentState?.scrollToTop();
    int targetIndex = 0;
    if (_currentCategory == 'Movies') {
      targetIndex = 1;
    } else if (_currentCategory == 'TV Shows') {
      targetIndex = 2;
    } else if (_currentCategory == 'Sports' && SettingsService().sportsEnabled) {
      targetIndex = 3;
    }

    if (targetIndex < _navNodes.length) {
      _navNodes[targetIndex].requestFocus();
    } else if (_navNodes.isNotEmpty) {
      _navNodes[0].requestFocus();
    }
  }

  Widget _buildMainView() {
    return RepaintBoundary(
      child: _MainHomeView(
        key: _homeKey,
        scrollNotifier: _homeScrollNotifier,
        onMoveToNav: _focusNavNode,
      ),
    );
  }
}

class _MainHomeView extends StatefulWidget {
  final ValueNotifier<double>? scrollNotifier;
  final VoidCallback? onMoveToNav;
  const _MainHomeView({
    super.key,
    this.scrollNotifier,
    this.onMoveToNav,
  });

  @override
  State<_MainHomeView> createState() => _MainHomeViewState();
}

class _MainHomeViewState extends State<_MainHomeView> {
  final ApiService _api = ApiService();
  final WatchHistoryService _historyService = WatchHistoryService();
  final FocusNode _entryFocusNode = FocusNode();
  final ValueNotifier<double> _localScrollNotifier = ValueNotifier<double>(0.0);

  void scrollToTop() {
    if (_scrollController.hasClients && _scrollController.offset > 0) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _onMoveUpFromFirstShelf() {
    scrollToTop();
    _entryFocusNode.requestFocus();
  }

  void requestFocus() {
    scrollToTop();
    _entryFocusNode.requestFocus();
  }

  void setCategory(String category) {
    if (_selectedCategory == category) return;
    setState(() {
      _selectedCategory = category;
    });
    _loadContent();
  }



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
        ? (item is MovieDetail
              ? item.title
              : (item is MovieListItem ? item.title : item['title'] ?? 'Movie'))
        : (item is TvShowDetail
              ? item.name
              : (item is MovieListItem
                    ? item.title
                    : item['name'] ?? item['title'] ?? 'TV Show'));

    // Resolve the show/movie ID for navigation
    final resolvedId =
        showId ??
        (item is MovieDetail
            ? item.id
            : item is MovieListItem
            ? item.id
            : item is TvShowDetail
            ? item.id
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
            final id = item is MovieDetail
                ? item.id
                : (item is MovieListItem
                      ? item.id
                      : (item is TvShowDetail
                            ? item.id
                            : (item as Map)['media_id'] ??
                                  item['id'] ??
                                  item['mediaId']));
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

  // Numbers each home shelf as a call-slot, in the order it actually
  // renders; reset once per build so it stays accurate regardless of which
  // optional rows (continue watching, up next) are present that frame.
  int _shelfCounter = 0;
  int _nextShelf() {
    _shelfCounter++;
    return _shelfCounter;
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
  List<DiscoverySection>? _apiSections;
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
  final Map<int, String> _adUrls = {};
  UpdateInfo? _updateInfo;
  Timer? _debounceTimer;
  bool _isLegacyFallback = false;
  bool _historyDirty = false;
  final bool _isVisible = true;

  final List<Map<String, dynamic>> _movieGenres = [
    {'id': 28, 'name': 'Action', 'color': DashboardTheme.signalRed},
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
    {'id': 10759, 'name': 'Action', 'color': DashboardTheme.signalRed},
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
    _entryFocusNode.addListener(_onEntryFocusChanged);
    _loadContent();
    _listenToAuthChanges();
    _historyService.addListener(_onHistoryChanged);
  }

  void _onEntryFocusChanged() {
    if (_entryFocusNode.hasFocus) {
      scrollToTop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? false;
    if (isCurrent && _historyDirty) {
      debugPrint(
        '[HomeScreen] 🔄 Became current and history is dirty, reloading...',
      );
      _historyDirty = false;
      _reloadHistory(forceRefresh: true);
    }
  }

  void _onHistoryChanged() {
    if (!mounted) return;

    // Check if this screen is currently visible/active in the navigator
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? false;

    if (isCurrent) {
      debugPrint('[HomeScreen] 🔄 History changed, reloading content quietly');
      _reloadHistory(forceRefresh: true);
      _historyDirty = false;
    } else {
      debugPrint(
        '[HomeScreen] ⏳ History changed while backgrounded, marking as dirty',
      );
      _historyDirty = true;
    }
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

      debugPrint(
        '[HomeScreen] 🏁 Structured Update check result: available=${info.isUpdateAvailable}, version=${info.latestVersion}, forced=${info.isForced}',
      );
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
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) {
      final event = data.event;
      if (event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.signedOut ||
          event == AuthChangeEvent.tokenRefreshed) {
        debugPrint(
          '[HomeScreen] 👤 Auth state changed: $event. Refreshing content.',
        );
        _loadContent();
      }
    });
  }

  void _onScroll() {
    if (!mounted) return;
    final offset = _scrollController.offset;
    widget.scrollNotifier?.value = offset;
    _localScrollNotifier.value = offset;
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

  Future<void> _loadContent({
    bool quiet = false,
    bool forceRefresh = false,
  }) async {
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
      }
      _checkForUpdate();

      final isTv = _selectedCategory == 'TV Shows';
      final userId = Supabase.instance.client.auth.currentUser?.id;

      // 1. Fetch Discovery Feed with Retries (The Brain)
      Map<String, dynamic>? discovery;
      int retryCount = 0;
      const maxRetries = 3;

      while (retryCount < maxRetries) {
        try {
          discovery = await _api.fetchDiscovery(
            userId: userId,
            mediaType: isTv ? 'tv' : 'movie',
            region: _api.region,
          );
          break; // Success
        } catch (e) {
          retryCount++;
          debugPrint(
            '[HomeScreen] ⚠️ Discovery load attempt $retryCount failed: $e',
          );
          if (retryCount >= maxRetries) rethrow;
          await Future.delayed(Duration(seconds: retryCount)); // Backoff
        }
      }

      if (discovery == null) {
        throw Exception('Discovery data is null after retries');
      }

      // 2. Fetch History & Contextual Data in parallel
      final results = await Future.wait([
        _historyService.getHistory(
          mediaType: isTv ? 'tv' : 'movie',
          forceRefresh: forceRefresh,
        ),
        if (isTv)
          _historyService.getRecentlyWatchedShows(forceRefresh: forceRefresh)
        else
          Future.value(null),
      ]);

      final history = results[0] as List<Map<String, dynamic>>;
      final watchingShows = results[1];
      List<Map<String, dynamic>>? upNextItems;
      if (isTv && watchingShows != null) {
        upNextItems = await _processUpNext(
          watchingShows,
          continueWatchingHistory: history,
        );
      }

      // 3. Map Discovery Sections to existing variables
      List<DiscoverySection> apiSections = (discovery['sections'] as List)
          .map((s) => DiscoverySection.fromJson(s))
          .where((s) => s.isEnabled)
          .toList();
      debugPrint(
        '[HomeScreen] 📡 Discovery Feed Received: ${apiSections.length} sections',
      );
      for (var s in apiSections) {
        debugPrint(
          '[HomeScreen]    - Row: "${s.title}" (${s.items.length} items)',
        );
      }

      List<MovieListItem>? trending;
      List<MovieListItem>? communityTrending;
      List<MovieListItem>? aiRecs;
      List<MovieListItem>? popular;
      List<MovieListItem>? topRated;

      for (var section in apiSections) {
        if (section.type == 'community') {
          communityTrending = section.items;
          trending ??= section.items.take(5).toList();
        } else if (section.type == 'ai') {
          aiRecs = section.items;
        } else if (section.title.toLowerCase().contains('premiere') ||
            section.title.toLowerCase().contains('recent') ||
            section.title.toLowerCase().contains('fresh') ||
            section.title.toLowerCase().contains('popular')) {
          popular = section.items;
          trending ??= section.items.take(5).toList();
        } else if (section.title.toLowerCase().contains('acclaimed') ||
            section.title.toLowerCase().contains('trending') ||
            section.type == 'tmdb') {
          topRated = section.items;
          trending ??= section.items.take(5).toList();
        }
      }

      // Precision Fallbacks: Ensure we have something for the hero section
      trending ??=
          popular?.take(5).toList() ??
          communityTrending?.take(5).toList() ??
          (apiSections.isNotEmpty
              ? apiSections
                    .firstWhere(
                      (s) => s.items.isNotEmpty,
                      orElse: () => apiSections.first,
                    )
                    .items
                    .take(5)
                    .toList()
              : null);

      popular ??= trending;

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
            overview:
                "Experience the excitement of $sport live on Caffeine TV. Watch ${featured['title']} now!",
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
      if (SettingsService().adsEnabled ||
          (kDebugMode && SettingsService().simulateAds)) {
        try {
          final results = await Supabase.instance.client
              .from('sponsorships')
              .select('*')
              .eq('is_active', true);

          for (var ad in results) {
            final adId = ad['id'].toString().hashCode;
            _adUrls[adId] = ad['link'] ?? '';
            ads.add(
              MovieListItem(
                id: adId,
                title: ad['title'],
                overview: ad['description'],
                posterPath: ad['image_url'],
                backdropPath: ad['image_url'],
                mediaType: 'ad',
                isSponsored: true,
              ),
            );
          }
        } catch (e) {
          debugPrint('[HomeScreen] ❌ Error fetching ads: $e');
        }

        if (kDebugMode && SettingsService().simulateAds) {
          if (ads.isEmpty) {
            ads.add(
              MovieListItem(
                id: 999901,
                title: 'Aurora Ultra: Power Redefined',
                overview:
                    'Experience unparalleled performance with the new Aurora Ultra series.',
                posterPath:
                    'https://caffeine.synqholdings.com/assets/images/simulated/poster_ad_1.png',
                backdropPath:
                    'https://caffeine.synqholdings.com/assets/images/simulated/poster_ad_1.png',
                mediaType: 'ad',
                isSponsored: true,
              ),
            );
          }
        }
      }

      if (mounted) {
        setState(() {
          _history = history;
          _watchingShows = upNextItems;
          _apiSections = apiSections;
          _trending = trending;
          _popular = popular;
          _topRated = topRated;
          _aiRecommendations = aiRecs;
          _weeklyTrending = communityTrending;
          _nowPlaying = popular;
          _loading = false;

          if (featuredItem != null && _trending != null) {
            _trending!.insert(0, featuredItem);
          }

          // Inject ads into rows
          if (ads.isNotEmpty && _popular != null && _popular!.length > 5) {
            _popular!.insert(2, ads[0]);
          }

          if (trending != null && trending.isNotEmpty) {
            final first = trending.first;
            _focusedMovie = MovieDetail(
              id: first.id,
              title: first.title,
              overview: first.overview,
              posterPath: first.posterPath,
              backdropPath: first.backdropPath,
              voteAverage: first.voteAverage,
              mediaType: first.mediaType,
            );
          }
          _isLegacyFallback = false;
          debugPrint('[HomeScreen] ✅ Discovery Engine loaded successfully');
        });
        _startAutoSlide();
      }
    } catch (e) {
      debugPrint('[HomeScreen] ❌ Final Discovery Failure: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Failed to load discovery feed. Please check your connection.',
            ),
          ),
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _processUpNext(
    List<Map<String, dynamic>> watchingShows, {
    List<Map<String, dynamic>>? continueWatchingHistory,
  }) async {
    final List<Map<String, dynamic>> upNextItems = [];
    final now = DateTime.now();

    // Identify any series currently in Continue Watching (in-progress episodes)
    final historyToCheck = continueWatchingHistory ?? _history;
    final inProgressSeriesIds = <int>{};
    if (historyToCheck != null) {
      for (final item in historyToCheck) {
        final rawId = item['media_id'] ?? item['id'];
        if (rawId is int) {
          inProgressSeriesIds.add(rawId);
        } else if (rawId != null) {
          final parsed = int.tryParse(rawId.toString());
          if (parsed != null) inProgressSeriesIds.add(parsed);
        }
      }
    }

    bool isEpReleased(String? airDate) {
      if (airDate == null || airDate.isEmpty) return false;
      try {
        return DateTime.parse(
          airDate,
        ).isBefore(now.add(const Duration(days: 1)));
      } catch (_) {
        return false;
      }
    }

    final seenShowIds = <int>{};

    for (var originalShow in watchingShows) {
      final showTitle =
          originalShow['name'] ?? originalShow['title'] ?? 'Unknown Show';
      final isLive =
          originalShow['type'] == 'live' ||
          originalShow['media_type'] == 'live';
      final isSports = showTitle.contains(' at ') || showTitle.contains(' vs ');

      // Skip live games or sports from "Up Next" episode calculation
      if (isLive || isSports) continue;

      final dynamic rawId = originalShow['id'] ?? originalShow['media_id'];
      if (rawId == null) continue;

      final showId = rawId is int ? rawId : int.tryParse(rawId.toString());
      if (showId == null) continue;

      // Rule: If the same series is currently in Continue Watching,
      // it must not appear in Up Next until the in-progress episode is completed.
      if (inProgressSeriesIds.contains(showId)) continue;

      // Deduplicate so a series only appears once in Up Next
      if (!seenShowIds.add(showId)) continue;

      // Rule: Only calculate next episode if previous episode was completed
      if (originalShow['is_completed'] == true) {
        try {
          final show = Map<String, dynamic>.from(originalShow);
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
            show['season_num'] = seasonNum;
            show['episode_num'] = nextEp.episodeNumber;
            show['episode_name'] = nextEp.name;
            show['is_completed'] = false;
            upNextItems.add(show);
          } else if (nextEp == null) {
            // Check if there's a next season
            final tvDetail = await _api.fetchTvDetail(showId);
            if (seasonNum < (tvDetail.numberOfSeasons ?? 0)) {
              final nextSeasonDetail = await _api.fetchSeasonDetail(
                showId,
                seasonNum + 1,
              );
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
          debugPrint(
            '[HomeScreen] ❌ Error calculating next episode for "$showTitle": $e',
          );
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
    final h = await _historyService.getHistory(
      mediaType: mediaType,
      forceRefresh: forceRefresh,
    );
    List<Map<String, dynamic>>? upNext;
    if (mediaType == 'tv') {
      final watchingShows = await _historyService.getRecentlyWatchedShows(
        forceRefresh: forceRefresh,
      );
      upNext = await _processUpNext(
        watchingShows,
        continueWatchingHistory: h,
      );
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
      if (!mounted ||
          _trending == null ||
          _trending!.isEmpty ||
          _loading ||
          !_isHeroInView) {
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
    _entryFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _localScrollNotifier.dispose();
    _autoSlideTimer?.cancel();
    _entryFocusNode.removeListener(_onEntryFocusChanged);
    _entryFocusNode.dispose();
    _authSubscription?.cancel();
    _debounceTimer?.cancel();
    _historyService.removeListener(_onHistoryChanged);
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

  // Zero-CLS skeleton in the Home Video world's own shelf-body tones — a
  // shape of the coming screen, not a spinner sitting in the middle of
  // nothing.
  Widget _buildLoadingSkeleton(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: s(56)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: s(120)),
            const CinematicHeroBlock(
              focusedMovie: null,
              trending: null,
              trendingIndex: 0,
              liveStreamUrls: {},
              onWatchNow: _noop,
              onFavorite: _noop,
            ),
            SizedBox(height: s(36)),
            const TvShimmer(
              child: Column(
                children: [
                  TvRowSkeleton(),
                  SizedBox(height: 16),
                  TvRowSkeleton(),
                  SizedBox(height: 16),
                  TvRowSkeleton(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _noop() {}

  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildLoadingSkeleton(context);

    // Fallback if API returned 401/404 and left us with no content
    if (_trending == null && _popular == null && _topRated == null) {
      double s(double v) => ResponsiveUtils.scale(context, v);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: s(96),
              height: s(96),
              decoration: const BoxDecoration(
                color: DashboardTheme.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.live_tv_outlined,
                color: Colors.white54,
                size: s(44),
              ),
            ),
            SizedBox(height: s(28)),
            Text(
              'Nothing to Show Yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: s(32),
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: s(12)),
            SizedBox(
              width: s(520),
              child: Text(
                "We couldn't reach the discovery feed. Make sure this device is paired to your ReelRiot account, then try again.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: s(18),
                  height: 1.4,
                ),
              ),
            ),
            SizedBox(height: s(36)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LongPressFocus(
                  onTap: () => _loadContent(),
                  child: Builder(
                    builder: (context) {
                      final focused = Focus.of(context).hasFocus;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: EdgeInsets.symmetric(
                          horizontal: s(32),
                          vertical: s(16),
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(
                            alpha: focused ? 0.25 : 0.12,
                          ),
                          borderRadius: BorderRadius.circular(s(10)),
                          boxShadow: focused
                              ? DashboardDecorations.focusGlow(
                                  context,
                                  strength: 0.5,
                                )
                              : null,
                        ),
                        child: Text(
                          'Retry Connection',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: s(16),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(width: s(16)),
                LongPressFocus(
                  onTap: () => Navigator.of(context).pushNamed('/pairing'),
                  child: Builder(
                    builder: (context) {
                      final focused = Focus.of(context).hasFocus;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: EdgeInsets.symmetric(
                          horizontal: s(32),
                          vertical: s(16),
                        ),
                        decoration: BoxDecoration(
                          color: DashboardTheme.signalRed.withValues(
                            alpha: focused ? 0.85 : 1.0,
                          ),
                          borderRadius: BorderRadius.circular(s(10)),
                          boxShadow: focused
                              ? DashboardDecorations.focusGlow(
                                  context,
                                  strength: 0.5,
                                  color: DashboardTheme.signalRed,
                                )
                              : null,
                        ),
                        child: Text(
                          'Sign In',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: s(16),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    double s(double v) => ResponsiveUtils.scale(context, v);
    _shelfCounter = 0;
    bool firstShelfAssigned = false;
    VoidCallback? getFirstShelfMoveUp() {
      if (!firstShelfAssigned) {
        firstShelfAssigned = true;
        return _onMoveUpFromFirstShelf;
      }
      return null;
    }

    return Stack(
      children: [
        // 1. Full-Bleed Parallax Hero Backdrop (Background Layer)
        Positioned.fill(
          child: ValueListenableBuilder<double>(
            valueListenable: _localScrollNotifier,
            builder: (context, scrollOffset, _) {
              return CinematicBackdrop(
                focusedMovie: _focusedMovie,
                parallaxOffset: scrollOffset,
              );
            },
          ),
        ),

        // 2. Linear Scrollable Content (Hero Content + Shelves)
        SingleChildScrollView(
          controller: _scrollController,
          primary: false,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: s(56)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top spacing below floating TopNav (104px nav + breathing room = 144px)
                SizedBox(height: s(144)),

                // Cinematic Hero Content (in-flow, never collides with shelves)
                CinematicHeroBlock(
                  focusedMovie: _focusedMovie,
                  trending: _trending,
                  trendingIndex: _trendingIndex,
                  liveStreamUrls: _liveStreamUrls,
                  onWatchNow: _onSpotlightWatchNow,
                  onFavorite: () {},
                  focusNode: _entryFocusNode,
                  onMoveToNav: widget.onMoveToNav,
                  onHeroFocused: scrollToTop,
                ),

                // Clean breathing room between hero actions and first shelf
                SizedBox(height: s(36)),

                if (_updateInfo != null)
                  Padding(
                    padding: EdgeInsets.only(bottom: s(32)),
                    child: HomeUpdateCard(updateInfo: _updateInfo!),
                  ),

                // --- CONTINUE WATCHING ROW ---
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  transitionBuilder:
                      (Widget child, Animation<double> animation) {
                    return SizeTransition(
                      sizeFactor: animation,
                      alignment: Alignment.topCenter,
                      child:
                          FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: (_history == null || _history!.isEmpty)
                      ? const SizedBox.shrink()
                      : Column(
                          key: const ValueKey('continue_watching_section'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildContinueWatchingRow(
                              context,
                              s,
                              _nextShelf(),
                              onMoveUp: getFirstShelfMoveUp(),
                            ),
                            SizedBox(height: s(48)),
                          ],
                        ),
                ),

                // --- UP NEXT ROW (TV ONLY) ---
                if (_selectedCategory == 'TV Shows') ...[
                  _buildUpNextRow(
                    context,
                    s,
                    _nextShelf(),
                    onMoveUp: getFirstShelfMoveUp(),
                  ),
                  SizedBox(height: s(48)),
                ],

                // --- DYNAMIC DISCOVERY ROWS ---
                if (_apiSections != null)
                  ..._apiSections!.map((section) {
                    if (section.items.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        HomeMediaRow(
                          title: section.title,
                          items: section.items,
                          index: _nextShelf(),
                          isSocial: section.type == 'social',
                          onFocus: (id) => _updateFocusedMovie(id),
                          onTap: (m) => _navigateToDetail(m),
                          onLongPress: (m) => _showItemContextMenu(
                            item: m,
                            isMovie: m.mediaType != 'tv',
                          ),
                          onMoveUp: getFirstShelfMoveUp(),
                        ),
                        SizedBox(height: s(48)),
                      ],
                    );
                  }),

                // --- GENRES ROW ---
                HomeGenresRow(
                  genres: _selectedCategory == 'TV Shows'
                      ? _tvGenres
                      : _movieGenres,
                  index: _nextShelf(),
                  onGenreTap: (g) => _navigateToGenre(g),
                ),
                SizedBox(height: s(48)),

                // --- PROVIDERS ROW ---
                HomeProvidersRow(
                  index: _nextShelf(),
                  onProviderTap: (p) => _navigateToProvider(p),
                ),
                SizedBox(height: s(120)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _onSpotlightWatchNow() async {
    if (_isProcessing) return;
    _isProcessing = true;
    try {
      if (_focusedMovie!.mediaType == 'live') {
        final url = _liveStreamUrls[_focusedMovie!.id];
        if (url == null || url.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Stream link not found yet. Try again later!'),
            ),
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

      if (_focusedMovie!.mediaType == 'ad') {
        final url = _adUrls[_focusedMovie!.id];
        if (url != null && url.isNotEmpty) {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
        return;
      }

      if (_selectedCategory == 'TV Shows') {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TvDetailScreen(tvId: _focusedMovie!.id),
          ),
        );
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) =>
                MovieDetailScreen(movieId: _focusedMovie!.id),
          ),
        );
      }
      await _historyService.waitForPendingSaves();
    } finally {
      _isProcessing = false;
      if (mounted) setState(() {});
    }
  }



  void _navigateToDetail(MovieListItem m) async {
    if (m.mediaType == 'ad' || m.isSponsored) {
      final url = _adUrls[m.id];
      if (url != null && url.isNotEmpty) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
      return;
    }

    final isTv = _selectedCategory == 'TV Shows';
    if (isTv) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => TvDetailScreen(tvId: m.id)),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => MovieDetailScreen(movieId: m.id),
        ),
      );
    }
    await _historyService.waitForPendingSaves();
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderScreen(
          providerId: p['id'] as int,
          providerName: p['name'] as String,
        ),
      ),
    );
  }

  /// Shows a dialog asking the user to resume from their saved position or start over.
  /// Returns the Duration to start at, or null if the dialog was dismissed.
  Future<Duration?> _showResumeDialog(
    BuildContext context,
    Duration saved,
    int durationMs,
  ) {
    final pos = _formatDuration(saved);
    final total = durationMs > 0
        ? ' / ${_formatDuration(Duration(milliseconds: durationMs))}'
        : '';
    double s(double v) => ResponsiveUtils.scale(context, v);

    return showDialog<Duration>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DashboardTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(s(20)),
          side: BorderSide(color: DashboardTheme.divider, width: s(1.5)),
        ),
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
              if (event is KeyDownEvent && TvKeys.isSelect(event.logicalKey)) {
                Navigator.of(ctx).pop(saved);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(saved),
              style: TextButton.styleFrom(
                backgroundColor: DashboardTheme.signalRed,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: s(24),
                  vertical: s(12),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(s(10)),
                ),
              ),
              child: Text('Continue from $pos'),
            ),
          ),
          const SizedBox(width: 8),
          Focus(
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent && TvKeys.isSelect(event.logicalKey)) {
                Navigator.of(ctx).pop(Duration.zero);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(Duration.zero),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white54,
                padding: EdgeInsets.symmetric(
                  horizontal: s(24),
                  vertical: s(12),
                ),
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
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
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
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  Widget _buildUpNextRow(
    BuildContext context,
    double Function(double) s,
    int index, {
    VoidCallback? onMoveUp,
  }) {
    if (_watchingShows == null || _watchingShows!.isEmpty) {
      return const SizedBox.shrink();
    }

    return HomeUpNextRow(
      watchingShows: _watchingShows!,
      index: index,
      onMoveUp: onMoveUp,
      onFocus: (id) => _updateFocusedMovie(id, isMovie: false),
      onLongPress: (show) => _showItemContextMenu(
        item: show,
        isMovie: false,
        season: show['season_num'] as int?,
        episode: show['episode_num'] as int?,
        showId: show['id'] as int?,
      ),
      onTap: _onUpNextTap,
    );
  }

  Future<void> _onUpNextTap(Map<String, dynamic> show) async {
    final season = show['season_num'] as int?;
    final episode = show['episode_num'] as int?;

    if (season != null && episode != null) {
      if (_isProcessing) return;
      _isProcessing = true;

      try {
        final detail = await _api.fetchTvDetail(show['id']);
        if (!mounted) return;

        final history = await _historyService.getHistory(mediaType: 'tv');
        final itemHistory = history.firstWhere(
          (h) =>
              h['media_id'] == show['id'] &&
              h['season_num'] == season &&
              h['episode_num'] == episode,
          orElse: () => <String, dynamic>{},
        );

        Duration? startAt;
        if (itemHistory.isNotEmpty && (itemHistory['position_ms'] ?? 0) > 0) {
          if (!mounted) return;
          startAt = await _showResumeDialog(
            context,
            Duration(milliseconds: itemHistory['position_ms']),
            itemHistory['duration_ms'] ?? 0,
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
        await _historyService.waitForPendingSaves();
        _loadContent(quiet: true);
      } finally {
        _isProcessing = false;
      }
    } else {
      _navigateToDetail(
        MovieListItem(
          id: show['id'],
          title: show['name'] ?? '',
          mediaType: 'tv',
          posterPath: show['poster_path'],
        ),
      );
    }
  }

  Widget _buildContinueWatchingRow(
    BuildContext context,
    double Function(double) s,
    int index, {
    VoidCallback? onMoveUp,
  }) {
    if (_history == null) return const SizedBox.shrink();
    final validHistory = _history!
        .where((h) => h['media_id'] != null && h['title'] != null)
        .toList();
    if (validHistory.isEmpty) return const SizedBox.shrink();

    final seenIds = <int>{};
    final dedupedHistory = validHistory.where((h) {
      final id = h['media_id'] as int;
      return seenIds.add(id);
    }).toList();

    return HomeContinueWatchingRow(
      history: dedupedHistory,
      index: index,
      onMoveUp: onMoveUp,
      onFocus: (id, isMovie) => _updateFocusedMovie(id, isMovie: isMovie),
      onClearAll: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: DashboardTheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(s(20)),
              side: BorderSide(color: DashboardTheme.divider, width: s(1.5)),
            ),
            title: const Text(
              'Clear History?',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'Do you want to clear all "Continue Watching" items for this category?',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  'Clear',
                  style: TextStyle(color: DashboardTheme.signalRed),
                ),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          await _historyService.clearHistory(
            mediaType: _selectedCategory == 'TV Shows' ? 'tv' : 'movie',
          );
          if (_scrollController.hasClients) {
            await _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
            );
          }
          setState(() {
            _trendingIndex = 0;
          });
          _loadContent();
        }
      },
      onTap: _onContinueWatchingTap,
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

  Future<void> _onContinueWatchingTap(Map<String, dynamic> h) async {
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
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                VideoLoaderScreen(movie: detail, startPosition: startAt),
          ),
        );
      } else {
        final detail = await _api.fetchTvDetail(h['media_id']);
        if (!mounted) return;

        if (h['season_num'] == null || h['episode_num'] == null) {
          if (!mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TvDetailScreen(tvId: h['media_id']),
            ),
          );
        } else {
          if (!mounted) return;
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
    } finally {
      _isProcessing = false;
      if (mounted) setState(() {});
    }
  }

  Future<String?> _showSituationDialog(BuildContext context) {
    final controller = TextEditingController();
    double s(double v) => ResponsiveUtils.scale(context, v);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DashboardTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(s(20)),
          side: BorderSide(color: DashboardTheme.divider, width: s(1.5)),
        ),
        title: const Text(
          'What\'s the occasion?',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'e.g. "date night", "horror fans", "relaxing Sunday"',
              style: TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Enter a situation...',
                hintStyle: TextStyle(color: Colors.white24),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: DashboardTheme.signalRed),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(
              'Get Recommendations',
              style: TextStyle(color: DashboardTheme.signalRed),
            ),
          ),
        ],
      ),
    );
  }
}
