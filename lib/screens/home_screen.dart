import 'package:caffeine_core/caffeine_core.dart';
import 'package:caffeine_tv/screens/tv_detail_screen.dart';
import 'package:caffeine_tv/screens/movie_detail_screen.dart';
import 'package:caffeine_tv/screens/search_screen.dart';
import 'package:caffeine_tv/screens/favorites_screen.dart';
import 'package:caffeine_tv/screens/settings_screen.dart';
import 'package:caffeine_tv/screens/sports_screen.dart';
import 'package:caffeine_tv/services/api_service.dart';
import 'package:caffeine_tv/services/watch_history_service.dart';
import 'package:caffeine_tv/screens/video_loader_screen.dart';
import 'package:caffeine_tv/widgets/poster_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:caffeine_tv/widgets/exit_dialog.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 1;
  final GlobalKey<FavoritesScreenState> _favoritesKey = GlobalKey<FavoritesScreenState>();
  final List<FocusNode> _navNodes = List.generate(5, (_) => FocusNode());

  @override
  void dispose() {
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

  static const _tabs = [
    _Tab(label: 'Search', icon: Icons.search),
    _Tab(label: 'Home', icon: Icons.home_filled),
    _Tab(label: 'Sports', icon: Icons.sports_soccer),
    _Tab(label: 'Profile', icon: Icons.person_outline),
    _Tab(label: 'Favorites', icon: Icons.favorite_border),
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: _onBackInvoke,
      child: Scaffold(
        backgroundColor: const Color(0xFF000000), // Pure black per design.json
        body: Row(
          children: [
            _buildNavRail(context),
            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                children: [
                  const SearchScreen(),
                  const _MainHomeView(),
                  const SportsScreen(),
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

  Widget _buildNavRail(BuildContext context) {
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
                children: List.generate(_tabs.length, (i) {
                  final tab = _tabs[i];
                  final selected = _selectedIndex == i;
                  return Focus(
                    focusNode: _navNodes[i],
                    onKeyEvent: (node, event) {
                      if (event is! KeyDownEvent) return KeyEventResult.ignored;
                      if (event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.select) {
                        setState(() => _selectedIndex = i);
                        if (i == 4) {
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
  const _MainHomeView();

  @override
  State<_MainHomeView> createState() => _MainHomeViewState();
}

class _MainHomeViewState extends State<_MainHomeView> {
  final ApiService _api = ApiService();
  final WatchHistoryService _historyService = WatchHistoryService();
  String _selectedCategory = 'Movies';
  MovieDetail? _focusedMovie;
  List<MovieListItem>? _trending;
  List<MovieListItem>? _weeklyTrending;
  List<MovieListItem>? _popular;
  List<MovieListItem>? _airingToday;
  List<Map<String, dynamic>>? _history;
  bool _loading = true;
  Timer? _autoSlideTimer;
  int _trendingIndex = 0;
  late ScrollController _scrollController;
  bool _isHeroInView = true;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _loadContent();
    _listenToAuthChanges();
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

  Future<void> _loadContent({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _history = null;
        _trending = null;
        _weeklyTrending = null;
        _popular = null;
        _airingToday = null;
      });
    }
    
    try {
      final isTv = _selectedCategory == 'TV Shows';
      
      if (isTv) {
        final results = await Future.wait([
          _historyService.getHistory(mediaType: 'tv'),
          _api.fetchTrendingTv(),
          _api.fetchPopularTv(),
          _api.fetchAiringToday(),
        ]);

        final history = results[0] as List<Map<String, dynamic>>;
        final trending = results[1] as TvListResponse;
        final popular = results[2] as TvListResponse;
        final airingToday = results[3] as TvListResponse;

        if (mounted) {
          setState(() {
            _history = history;
            
            if (trending.results.isNotEmpty) {
              final first = trending.results.first;
              _focusedMovie = MovieDetail(
                id: first.id,
                title: first.name,
                overview: first.overview,
                posterPath: first.posterPath,
                backdropPath: first.backdropPath,
                voteAverage: first.voteAverage,
              );
              
              _trending = trending.results.take(5).map((t) => MovieListItem(
                id: t.id,
                title: t.name,
                posterPath: t.posterPath,
                backdropPath: t.backdropPath,
                overview: t.overview,
              )).toList();

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
          _historyService.getHistory(mediaType: 'movie'),
          _api.fetchTrendingMovies(),
          _api.fetchPopularMovies(),
        ]);

        final history = results[0] as List<Map<String, dynamic>>;
        final trending = results[1] as MovieListResponse;
        final popular = results[2] as MovieListResponse;

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
        
        if (mounted) {
          setState(() {
            _history = history;
            if (releasedTrending.isNotEmpty) {
              final first = releasedTrending.first;
              // Note: fetchMovieDetail is still needed for more details if necessary, 
              // but we can use trending item for basic hero display.
              _focusedMovie = MovieDetail(
                id: first.id,
                title: first.title,
                overview: first.overview,
                posterPath: first.posterPath,
                backdropPath: first.backdropPath,
                voteAverage: first.voteAverage,
              );
              _trending = releasedTrending.take(5).toList();
              _weeklyTrending = releasedTrending;
            }
            _popular = releasedPopular;
          });
          _startAutoSlide();
        }
      }
    } catch (e) {
      debugPrint('[HomeScreen] ❌ Error loading content: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reloadHistory() async {
    final mediaType = _selectedCategory == 'TV Shows' ? 'tv' : 'movie';
    final h = await _historyService.getHistory(mediaType: mediaType);
    if (mounted) setState(() => _history = h);
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
        final nextId = _trending![_trendingIndex].id;
        _updateFocusedMovie(nextId, isAuto: true);
      });
    });
  }

  void _resetAutoSlide() {
    _startAutoSlide();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _autoSlideTimer?.cancel();
    _authSubscription?.cancel();
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
                    image: NetworkImage('https://image.tmdb.org/t/p/original${_focusedMovie!.backdropPath}'),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                      const Color(0xFFEC1D24).withOpacity(0.3), // brand red
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
              SizedBox(height: s(150)),
              AnimatedSwitcher(
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
                            'TRENDING', 
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
                              onTap: () {
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
                                push.then((_) => _reloadHistory());
                              },
                            ),
                            SizedBox(width: s(36)),
                            _HeroButton(
                              label: 'Favourite',
                              icon: Icons.favorite_border,
                              style: HeroButtonStyle.secondaryRed,
                              onTap: () {},
                            ),
                            SizedBox(width: s(36)),
                            _HeroButton(
                              label: 'Share',
                              icon: Icons.share_outlined,
                              style: HeroButtonStyle.secondaryWhite,
                              onTap: () {},
                            ),
                          ],
                        ),
                        SizedBox(height: s(48)),
                        _buildSliderIndicators(context),
                      ],
                    ),
              ),
              _buildContinueWatchingRow(context, s),
              if (_selectedCategory == 'TV Shows') ...[
                SizedBox(height: s(96)),
                _buildAiringTodayRow(context, s),
              ],
              SizedBox(height: s(96)),
              _buildRow(context, _selectedCategory == 'TV Shows' ? 'Popular shows this week' : 'Popular movies this week', _weeklyTrending),
              SizedBox(height: s(72)),
              _buildRow(context, _selectedCategory == 'TV Shows' ? 'Popular TV' : 'Popular Movies', _popular),
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
                    padding: EdgeInsets.symmetric(horizontal: s(48)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          cat,
                          style: TextStyle(
                            color: focused ? Colors.white : (isSelected ? Colors.white : Colors.white38),
                            fontSize: s(48),
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
        Text(
          'Continue Watching',
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
            itemCount: dedupedHistory.length,
            itemBuilder: (context, index) {
              final h = dedupedHistory[index];
              final isMovie = h['type'] == 'movie';
              final mediaId = h['media_id'] as int;
              
              return Padding(
                padding: EdgeInsets.only(right: s(36)),
                child: PosterCard(
                  posterPath: h['poster_path'],
                  title: h['title'] ?? '',
                  onFocus: () => _updateFocusedMovie(mediaId, isMovie: isMovie),
                  onTap: () async {
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
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => VideoLoaderScreen(
                            tvShow: detail,
                            season: h['season'],
                            episode: h['episode'],
                            episodeName: h['episode_name'],
                            startPosition: startAt,
                          ),
                        ),
                      );
                    }

                    // Refresh history so completed items disappear immediately
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
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => TvDetailScreen(tvId: m.id)),
                    );
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

  String _monthName(int month) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return months[month - 1];
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
