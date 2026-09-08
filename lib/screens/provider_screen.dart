import 'dart:ui';
import 'package:caffeine_core/caffeine_core.dart';
import 'package:reelriot_tv/services/api_service.dart';
import 'package:reelriot_tv/widgets/poster_card.dart';
import 'package:reelriot_tv/screens/movie_detail_screen.dart';
import 'package:reelriot_tv/screens/tv_detail_screen.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'package:reelriot_tv/utils/quality_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ProviderScreen extends StatefulWidget {
  final int providerId;
  final String providerName;

  const ProviderScreen({
    super.key,
    required this.providerId,
    required this.providerName,
  });

  @override
  State<ProviderScreen> createState() => _ProviderScreenState();
}

class _ProviderScreenState extends State<ProviderScreen> {
  final ApiService _api = ApiService();
  final ScrollController _scrollController = ScrollController();
  
  List<MovieListItem> _items = [];
  bool _loading = true;
  String? _error;
  int _page = 1;
  bool _hasMore = true;
  bool _isProcessing = false;

  // Filters
  String _selectedSort = 'popularity.desc';
  String _selectedType = 'all'; // all, movie, tv

  final List<Map<String, String>> _sortOptions = [
    {'label': 'Popular', 'value': 'popularity.desc'},
    {'label': 'Newest', 'value': 'primary_release_date.desc'},
    {'label': 'Top Rated', 'value': 'vote_average.desc'},
  ];

  final List<Map<String, String>> _typeOptions = [
    {'label': 'All Content', 'value': 'all'},
    {'label': 'Movies', 'value': 'movie'},
    {'label': 'TV Shows', 'value': 'tv'},
  ];

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

    try {
      List<MovieListItem> newItems = [];
      
      if (_selectedType == 'all' || _selectedType == 'movie') {
        final movies = await _api.fetchMoviesByProvider(widget.providerId, page: _page, sortBy: _selectedSort);
        newItems.addAll(movies.results);
      }

      if (_selectedType == 'all' || _selectedType == 'tv') {
        final tv = await _api.fetchTvByProvider(widget.providerId, page: _page, sortBy: _selectedSort);
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

      // If "all" and we have multiple items, we might want to re-sort locally by popularity or date 
      // since the two lists are fetched independently.
      if (_selectedType == 'all') {
        if (_selectedSort == 'popularity.desc') {
          newItems.sort((a, b) => (b.popularity ?? 0).compareTo(a.popularity ?? 0));
        } else if (_selectedSort == 'vote_average.desc') {
          newItems.sort((a, b) => (b.voteAverage ?? 0).compareTo(a.voteAverage ?? 0));
        }
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

  double _scale(BuildContext context, double v) {
    return v * (MediaQuery.of(context).size.width / 1920);
  }

  @override
  Widget build(BuildContext context) {
    double s(double v) => _scale(context, v);

    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
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
                color: const Color(0xFFDC2626).withValues(alpha: 0.05),
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
              // Header & Filters
              _buildHeader(context, s),
              
              // Grid
              Expanded(
                child: _loading && _items.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFDC2626)))
                  : _error != null && _items.isEmpty
                    ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white70)))
                    : GridView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.fromLTRB(s(80), s(20), s(80), s(80)),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6,
                          childAspectRatio: 0.68,
                          crossAxisSpacing: s(40),
                          mainAxisSpacing: s(46),
                        ),
                        itemCount: _items.length + (_hasMore ? 6 : 0), // Extra items for skeleton/loading
                        itemBuilder: (context, index) {
                          if (index >= _items.length) {
                             return _hasMore ? _buildSkeletonCard(s) : const SizedBox.shrink();
                          }
                          final item = _items[index];
                          return PosterCard(
                            posterPath: item.posterPath,
                            title: item.title ?? 'Unknown',
                            quality: QualityUtils.getQualityBadgeSync(
                              mediaId: item.id,
                              releaseDate: item.releaseDate,
                              isMovie: item.mediaType != 'tv',
                            ),
                            mediaId: item.id,
                            isMovie: item.mediaType != 'tv',
                            releaseDate: item.releaseDate,
                            onTap: () async {
                              if (_isProcessing) return;
                              _isProcessing = true;
                              try {
                                if (item.mediaType == 'tv') {
                                  await Navigator.push(context, MaterialPageRoute(builder: (_) => TvDetailScreen(tvId: item.id)));
                                } else {
                                  await Navigator.push(context, MaterialPageRoute(builder: (_) => MovieDetailScreen(movieId: item.id)));
                                }
                              } finally {
                                _isProcessing = false;
                                if (mounted) setState(() {});
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
    return Container(
      padding: EdgeInsets.fromLTRB(s(80), s(64), s(80), s(32)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildBackButton(context, s),
              SizedBox(width: s(32)),
              Text(
                widget.providerName.toUpperCase(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: s(64),
                  fontWeight: FontWeight.w900,
                  letterSpacing: s(2),
                ),
              ),
              const Spacer(),
              _buildFilterBar(s),
            ],
          ),
          SizedBox(height: s(40)),
          _buildSortBar(s),
        ],
      ),
    );
  }

  Widget _buildBackButton(BuildContext context, double Function(double) s) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && TvKeys.isSelect(event.logicalKey)) {
          Navigator.pop(context);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () => Navigator.pop(context),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.all(s(16)),
              decoration: BoxDecoration(
                color: focused ? Colors.white : Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_back, 
                color: focused ? Colors.black : Colors.white,
                size: s(32),
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _buildFilterBar(double Function(double) s) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(s(40)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: s(8), vertical: s(8)),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(s(40)),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: _typeOptions.map((opt) => _buildFilterItem(opt, _selectedType, (val) {
              setState(() => _selectedType = val);
              _load();
            }, s)).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildSortBar(double Function(double) s) {
    return Row(
      children: _sortOptions.map((opt) => Padding(
        padding: EdgeInsets.only(right: s(24)),
        child: _buildSortItem(opt, s),
      )).toList(),
    );
  }

  Widget _buildFilterItem(Map<String, String> opt, String current, Function(String) onSelect, double Function(double) s) {
    final isSelected = opt['value'] == current;
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && TvKeys.isSelect(event.logicalKey)) {
          onSelect(opt['value']!);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () => onSelect(opt['value']!),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(horizontal: s(32), vertical: s(12)),
              decoration: BoxDecoration(
                color: focused ? Colors.white : (isSelected ? Colors.white.withValues(alpha: 0.1) : Colors.transparent),
                borderRadius: BorderRadius.circular(s(30)),
              ),
              child: Text(
                opt['label']!,
                style: TextStyle(
                  color: focused ? Colors.black : (isSelected ? Colors.white : Colors.white54),
                  fontSize: s(24),
                  fontWeight: isSelected || focused ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _buildSortItem(Map<String, String> opt, double Function(double) s) {
    final isSelected = opt['value'] == _selectedSort;
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && TvKeys.isSelect(event.logicalKey)) {
           setState(() => _selectedSort = opt['value']!);
           _load();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () {
              setState(() => _selectedSort = opt['value']!);
              _load();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                   Text(
                    opt['label']!,
                    style: TextStyle(
                      color: focused ? Colors.white : (isSelected ? Colors.white : Colors.white38),
                      fontSize: s(28),
                      fontWeight: isSelected || focused ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  SizedBox(height: s(4)),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: s(3),
                    width: focused ? s(40) : (isSelected ? s(24) : 0),
                    color: focused || isSelected ? const Color(0xFFDC2626) : Colors.transparent,
                  ),
                ],
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
        borderRadius: BorderRadius.circular(s(16)),
      ),
    );
  }
}
