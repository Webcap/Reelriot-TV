import 'package:caffeine_core/caffeine_core.dart';
import 'package:caffeine_tv/services/api_service.dart';
import 'package:caffeine_tv/widgets/poster_card.dart';
import 'package:caffeine_tv/screens/movie_detail_screen.dart';
import 'package:caffeine_tv/screens/tv_detail_screen.dart';
import 'package:flutter/material.dart';
import 'dart:ui';

class GenreScreen extends StatefulWidget {
  final int genreId;
  final String genreName;
  final bool isMovie;

  const GenreScreen({
    super.key,
    required this.genreId,
    required this.genreName,
    this.isMovie = true,
  });

  @override
  State<GenreScreen> createState() => _GenreScreenState();
}

class _GenreScreenState extends State<GenreScreen> {
  final ApiService _api = ApiService();
  final ScrollController _scrollController = ScrollController();
  
  List<MovieListItem> _items = [];
  bool _loading = true;
  String? _error;
  int _page = 1;
  bool _hasMore = true;
  bool _isProcessing = false;
  String _selectedFilter = 'Popular';

  @override
  void initState() {
    super.initState();
    _load();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 500) {
      if (!_loading && _hasMore) {
        _load(loadMore: true);
      }
    }
  }

  Future<void> _load({bool loadMore = false}) async {
    if (loadMore) {
      _page++;
    } else {
      _page = 1;
      if (mounted) setState(() => _loading = true);
    }

    final sortBy = _selectedFilter == 'Popular' 
      ? 'popularity.desc' 
      : (widget.isMovie ? 'primary_release_date.desc' : 'first_air_date.desc');

    try {
      List<MovieListItem> newItems = [];
      
      if (widget.isMovie) {
        final movies = await _api.fetchMoviesByGenre(widget.genreId, page: _page, sortBy: sortBy);
        newItems.addAll(movies.results);
      } else {
        final tv = await _api.fetchTvByGenre(widget.genreId, page: _page, sortBy: sortBy);
        newItems.addAll(tv.results.map((t) => MovieListItem(
          id: t.id,
          title: t.name,
          posterPath: t.posterPath,
          backdropPath: t.backdropPath,
          overview: t.overview,
          mediaType: 'tv',
          voteAverage: t.voteAverage,
        )));
      }

      if (mounted) {
        setState(() {
          if (loadMore) {
            _items.addAll(newItems);
          } else {
            _items = newItems;
          }
          _loading = false;
          _hasMore = newItems.isNotEmpty;
          _error = null;
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

  double _scale(double v) {
    return v * (MediaQuery.of(context).size.width / 1920);
  }

  @override
  Widget build(BuildContext context) {
    final s = _scale;

    return Scaffold(
      backgroundColor: const Color(0xFF000000), // Match home screen pure black
      body: Stack(
        children: [
          // Background Glow
          Positioned(
            top: -s(200),
            right: -s(200),
            child: Container(
              width: s(800),
              height: s(800),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEC1D24).withValues(alpha: 0.08),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with Glass Look
              _buildHeader(context, s),
              
              // Grid
              Expanded(
                child: _loading && _items.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFEC1D24)))
                  : _error != null && _items.isEmpty
                    ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white70)))
                    : GridView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.fromLTRB(s(96), s(40), s(96), s(80)),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6,
                          childAspectRatio: 0.65,
                          crossAxisSpacing: s(36),
                          mainAxisSpacing: s(42),
                        ),
                        itemCount: _items.length + (_hasMore ? 6 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _items.length) {
                             return _hasMore ? _buildSkeletonCard(s) : const SizedBox.shrink();
                          }
                          final item = _items[index];
                          return PosterCard(
                            posterPath: item.posterPath,
                            title: item.title ?? 'Unknown',
                            onTap: () async {
                              if (_isProcessing) return;
                              _isProcessing = true;
                              try {
                                if (widget.isMovie) {
                                  await Navigator.push(context, MaterialPageRoute(builder: (_) => MovieDetailScreen(movieId: item.id)));
                                } else {
                                  await Navigator.push(context, MaterialPageRoute(builder: (_) => TvDetailScreen(tvId: item.id)));
                                }
                              } finally {
                                _isProcessing = false;
                                if (mounted) setState(() {});
                                // After returning, we might want to refresh history if we added a back navigation listener,
                                // but for now, we just reset processing state.
                              }
                            },
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

  Widget _buildHeader(BuildContext context, double Function(double) s) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(s(96), s(80), s(96), s(40)),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.08),
                width: s(1.5),
              ),
            ),
          ),
          child: Row(
            children: [
              _buildBackButton(context, s),
              SizedBox(width: s(48)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.genreName.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: s(72),
                      fontWeight: FontWeight.w900,
                      letterSpacing: s(-2),
                    ),
                  ),
                  Text(
                    widget.isMovie ? 'MOVIES' : 'TV SHOWS',
                    style: TextStyle(
                      color: const Color(0xFFEC1D24).withValues(alpha: 0.9),
                      fontSize: s(20),
                      fontWeight: FontWeight.bold,
                      letterSpacing: s(4),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Filters
              Row(
                children: [
                  _buildFilterButton('Popular', s),
                  SizedBox(width: s(24)),
                  _buildFilterButton('Newest', s),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterButton(String label, double Function(double) s) {
    final isSelected = _selectedFilter == label;
    
    return Focus(
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          
          return GestureDetector(
            onTap: () {
              if (_selectedFilter != label) {
                setState(() {
                  _selectedFilter = label;
                  _items = [];
                  _load();
                });
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(horizontal: s(40), vertical: s(20)),
              decoration: BoxDecoration(
                color: isFocused 
                  ? Colors.white 
                  : (isSelected ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.04)),
                borderRadius: BorderRadius.circular(s(16)),
                border: Border.all(
                  color: isFocused 
                    ? Colors.white 
                    : (isSelected ? Colors.white.withValues(alpha: 0.3) : Colors.white10),
                  width: s(2),
                ),
                boxShadow: isFocused ? [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.2),
                    blurRadius: s(20),
                    spreadRadius: s(2),
                  )
                ] : [],
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: isFocused ? Colors.black : Colors.white,
                  fontSize: s(24),
                  fontWeight: isSelected || isFocused ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _buildBackButton(BuildContext context, double Function(double) s) {
    return Focus(
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () => Navigator.pop(context),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.all(s(24)),
              decoration: BoxDecoration(
                color: focused ? Colors.white : Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
                border: Border.all(
                  color: focused ? Colors.white : Colors.white24,
                  width: s(2),
                ),
              ),
              child: Icon(
                Icons.arrow_back, 
                color: focused ? Colors.black : Colors.white,
                size: s(36),
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _buildSkeletonCard(double Function(double) s) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(s(20)),
      ),
    );
  }
}
