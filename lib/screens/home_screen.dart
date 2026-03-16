import 'package:caffeine_core/caffeine_core.dart';
import 'package:caffeine_tv/screens/movie_detail_screen.dart';
import 'package:caffeine_tv/screens/search_screen.dart';
import 'package:caffeine_tv/screens/settings_screen.dart';
import 'package:caffeine_tv/services/api_service.dart';
import 'package:caffeine_tv/widgets/poster_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 1;

  static const _tabs = [
    _Tab(label: 'Search', icon: Icons.search),
    _Tab(label: 'Home', icon: Icons.home_filled),
    _Tab(label: 'Trending', icon: Icons.arrow_outward),
    _Tab(label: 'TV', icon: Icons.tv),
    _Tab(label: 'Movie', icon: Icons.movie_outlined),
    _Tab(label: 'Add', icon: Icons.add_box_outlined),
    _Tab(label: 'Profile', icon: Icons.person_outline),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                const Center(child: Text('Trending', style: TextStyle(color: Colors.white))),
                const Center(child: Text('TV', style: TextStyle(color: Colors.white))),
                const Center(child: Text('Movies', style: TextStyle(color: Colors.white))),
                const Center(child: Text('Add', style: TextStyle(color: Colors.white))),
                const SettingsScreen(), // Profile goes to settings
              ],
            ),
          ),
        ],
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
                    onKeyEvent: (node, event) {
                      if (event is! KeyDownEvent) return KeyEventResult.ignored;
                      if (event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.select) {
                        setState(() => _selectedIndex = i);
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Builder(
                      builder: (context) {
                        final focused = Focus.of(context).hasFocus;
                        return Padding(
                          padding: EdgeInsets.symmetric(vertical: s(12)),
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
  MovieDetail? _focusedMovie;
  List<MovieListItem>? _trending;
  List<MovieListItem>? _popular;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    try {
      final trending = await _api.fetchTrendingMovies();
      final popular = await _api.fetchPopularMovies();
      
      if (trending.results.isNotEmpty) {
        final hero = await _api.fetchMovieDetail(trending.results.first.id);
        if (mounted) {
          setState(() {
            _focusedMovie = hero;
            _trending = trending.results;
            _popular = popular.results;
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _updateFocusedMovie(int movieId) async {
    try {
      final detail = await _api.fetchMovieDetail(movieId);
      if (mounted) {
        setState(() => _focusedMovie = detail);
      }
    } catch (e) {
      // Ignore
    }
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
          primary: true, 
          padding: EdgeInsets.symmetric(horizontal: s(96), vertical: s(60)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopNav(context),
              SizedBox(height: s(150)),
              if (_focusedMovie != null) ...[
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
                      color: Colors.white70,
                      fontSize: s(30),
                      height: 1.4,
                    ),
                    maxLines: 2,
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
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (context) => MovieDetailScreen(movieId: _focusedMovie!.id)),
                        );
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
              ],
              SizedBox(height: s(96)),
              _buildRow(context, 'Trending Now', _trending),
              SizedBox(height: s(72)),
              _buildRow(context, 'Popular Movies', _popular),
              SizedBox(height: s(150)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopNav(BuildContext context) {
    final s = (double v) => _scale(context, v);
    final categories = ['Movies', 'TV Shows', 'Sports', 'Live (Beta)'];
    return Row(
      children: categories.map((cat) {
        final isSelected = cat == 'Movi';
        return Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent && (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.select)) {
              // Handle category selection
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Builder(
            builder: (context) {
              final focused = Focus.of(context).hasFocus;
              return Padding(
                padding: EdgeInsets.only(right: s(96)),
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
              );
            }
          ),
        );
      }).toList(),
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
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => MovieDetailScreen(movieId: m.id)),
                    );
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
