import 'package:cached_network_image/cached_network_image.dart';
import 'package:caffeine_core/caffeine_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reelriot_tv/constants.dart';
import 'package:reelriot_tv/screens/movie_detail_screen.dart';
import 'package:reelriot_tv/screens/tv_detail_screen.dart';
import 'package:reelriot_tv/services/api_service.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/utils/quality_utils.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'package:reelriot_tv/widgets/long_press_focus.dart';
import 'package:reelriot_tv/widgets/poster_card.dart';

/// Full-screen browse grid for exploring all titles in a section, triggered
/// when the user selects a [SeeMorePosterCard].
///
/// Features dynamic infinite pagination, live hero backdrop morphing,
/// zero-CLS layout mirroring, and D-pad edge boundary handling.
class SeeMoreScreen extends StatefulWidget {
  final String title;
  final List<MovieListItem> items;
  final bool isMovie;
  final String? subtitle;
  final String? sectionType;
  final String? mediaType;
  final int? genreId;

  const SeeMoreScreen({
    super.key,
    required this.title,
    required this.items,
    this.isMovie = true,
    this.subtitle,
    this.sectionType,
    this.mediaType,
    this.genreId,
  });

  @override
  State<SeeMoreScreen> createState() => _SeeMoreScreenState();
}

class _SeeMoreScreenState extends State<SeeMoreScreen> {
  static const int _crossAxisCount = 6;
  static const int _maxPages = 20;

  final ApiService _api = ApiService();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _backFocusNode = FocusNode();

  late final List<MovieListItem> _items = List<MovieListItem>.from(widget.items);
  late final Set<int> _seenIds = widget.items.map((i) => i.id).toSet();

  bool _isProcessing = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  late MovieListItem? _focusedItem =
      widget.items.isNotEmpty ? widget.items.first : null;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    // Automatically prefetch page 2 in the background to expand options past the initial row
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchNextPage();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _backFocusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        !_isLoadingMore &&
        _hasMore &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 400) {
      _fetchNextPage();
    }
  }

  Future<void> _fetchNextPage() async {
    if (_isLoadingMore || !_hasMore || _currentPage >= _maxPages) return;
    setState(() => _isLoadingMore = true);

    try {
      final nextPage = _currentPage + 1;
      final newBatch = await _api.fetchCategoryItems(
        title: widget.title,
        sectionType: widget.sectionType,
        isMovie: widget.isMovie,
        page: nextPage,
        genreId: widget.genreId,
      );

      if (!mounted) return;

      if (newBatch.isEmpty) {
        setState(() {
          _hasMore = false;
          _isLoadingMore = false;
        });
        return;
      }

      final filtered = newBatch.where((m) => !_seenIds.contains(m.id)).toList();
      for (final m in filtered) {
        _seenIds.add(m.id);
      }

      setState(() {
        _currentPage = nextPage;
        _items.addAll(filtered);
        _isLoadingMore = false;
        if (newBatch.length < 5) {
          _hasMore = false;
        }
      });
    } catch (e) {
      debugPrint('[SeeMoreScreen] ⚠️ Failed to fetch page ${_currentPage + 1}: $e');
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  bool _isItemMovie(MovieListItem item) {
    return item.mediaType != null ? item.mediaType != 'tv' : widget.isMovie;
  }

  void _navigateToDetail(MovieListItem item) async {
    if (_isProcessing) return;
    _isProcessing = true;
    try {
      if (_isItemMovie(item)) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MovieDetailScreen(movieId: item.id),
          ),
        );
      } else {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TvDetailScreen(tvId: item.id),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);
    final heroHeight = s(420);

    return Scaffold(
      backgroundColor: DashboardTheme.canvasBlack,
      body: Column(
        children: [
          SizedBox(
            height: heroHeight,
            child: _buildHero(context, s),
          ),
          Expanded(
            child: _items.isEmpty
                ? Center(
                    child: Text(
                      'No items found in this section.',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: s(18),
                      ),
                    ),
                  )
                : _buildGrid(context, s),
          ),
        ],
      ),
    );
  }

  Widget _buildHero(BuildContext context, double Function(double) s) {
    final item = _focusedItem;
    final backdropUrl = item != null &&
            item.backdropPath != null &&
            item.backdropPath!.isNotEmpty
        ? '$tmdbImageBaseUrl/w1280${item.backdropPath}'
        : null;

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            fit: StackFit.expand,
            children: [...previousChildren, ?currentChild],
          ),
          child: KeyedSubtree(
            key: ValueKey(item?.id ?? -1),
            child: backdropUrl != null
                ? CachedNetworkImage(
                    imageUrl: backdropUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        Container(color: DashboardTheme.surface),
                    errorWidget: (context, url, error) =>
                        Container(color: DashboardTheme.surface),
                  )
                : Container(color: DashboardTheme.surface),
          ),
        ),
        // Legibility scrim for the back button / badge sitting on the image.
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.65),
                Colors.transparent,
              ],
              stops: const [0.0, 0.35],
            ),
          ),
        ),
        // Blend the hero into the black canvas the grid sits on.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                DashboardTheme.canvasBlack.withValues(alpha: 0.5),
                DashboardTheme.canvasBlack,
              ],
              stops: const [0.45, 0.85, 1.0],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(s(64), s(40), s(64), s(28)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBackButton(context, s),
              const Spacer(),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: item == null
                    ? const SizedBox.shrink()
                    : _buildHeroInfo(context, s, item),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeroInfo(
    BuildContext context,
    double Function(double) s,
    MovieListItem item,
  ) {
    final year = (item.releaseDate != null && item.releaseDate!.length >= 4)
        ? item.releaseDate!.substring(0, 4)
        : null;
    final rating = item.voteAverage != null && item.voteAverage! > 0
        ? item.voteAverage!.toStringAsFixed(1)
        : null;
    final quality = QualityUtils.getQualityBadgeSync(
      mediaId: item.id,
      releaseDate: item.releaseDate,
      isMovie: _isItemMovie(item),
    );

    return Column(
      key: ValueKey(item.id),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: s(10), vertical: s(4)),
              decoration: BoxDecoration(
                color: DashboardTheme.signalRed.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(s(6)),
                border: Border.all(
                  color: DashboardTheme.signalRed.withValues(alpha: 0.4),
                  width: s(1),
                ),
              ),
              child: Text(
                '${_items.length}${_hasMore ? '+' : ''} TITLES',
                style: TextStyle(
                  color: DashboardTheme.signalRed,
                  fontSize: s(11),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            SizedBox(width: s(10)),
            Text(
              (widget.subtitle ?? 'EXPLORE ALL TITLES IN THIS COLLECTION')
                  .toUpperCase(),
              style: TextStyle(
                color: Colors.white54,
                fontSize: s(12),
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        SizedBox(height: s(10)),
        Text(
          item.title ?? 'Unknown',
          style: TextStyle(
            color: Colors.white,
            fontSize: s(48),
            fontWeight: FontWeight.w900,
            height: 1.05,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: s(12)),
        Row(
          children: [
            if (quality != null) ...[
              _buildQualityBadge(s, quality),
              SizedBox(width: s(12)),
            ],
            if (year != null) ...[
              _buildMetaText(s, year),
              SizedBox(width: s(12)),
            ],
            if (rating != null) _buildMetaText(s, '★ $rating'),
          ],
        ),
      ],
    );
  }

  Widget _buildGrid(BuildContext context, double Function(double) s) {
    final showSkeleton = _isLoadingMore && _hasMore;
    final totalCount = _items.length + (showSkeleton ? _crossAxisCount : 0);

    return GridView.builder(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(s(96), s(28), s(96), s(80)),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _crossAxisCount,
        childAspectRatio: 153 / 230,
        crossAxisSpacing: s(36),
        mainAxisSpacing: s(32),
      ),
      itemCount: totalCount,
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          // Zero-CLS Shimmer Skeleton matching exact 153x230 poster footprint
          return Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(s(8)),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: s(1),
              ),
            ),
          );
        }

        final item = _items[index];
        final isEndOfRow = (index + 1) % _crossAxisCount == 0 ||
            index == _items.length - 1;

        return PosterCard(
          posterPath: item.posterPath,
          title: item.title ?? 'Unknown',
          onTap: () => _navigateToDetail(item),
          onFocus: () {
            setState(() => _focusedItem = item);
            // Pre-fetch when D-pad focus gets close to the bottom of the current list
            if (index >= _items.length - 8 && !_isLoadingMore && _hasMore) {
              _fetchNextPage();
            }
          },
          quality: QualityUtils.getQualityBadgeSync(
            mediaId: item.id,
            releaseDate: item.releaseDate,
            isMovie: _isItemMovie(item),
          ),
          mediaId: item.id,
          isMovie: _isItemMovie(item),
          releaseDate: item.releaseDate,
          onKeyEvent: isEndOfRow
              ? (node, event) {
                  if (TvKeys.isRight(event.logicalKey)) {
                    if (event is KeyDownEvent) {
                      SystemSound.play(SystemSoundType.click);
                      HapticFeedback.lightImpact();
                    }
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                }
              : null,
        );
      },
    );
  }

  Widget _buildQualityBadge(double Function(double) s, String quality) {
    Color bgColor = Colors.black.withValues(alpha: 0.8);
    Color borderColor = DashboardTheme.divider;
    final q = quality.toUpperCase();

    if (q == 'CAM') {
      bgColor = DashboardTheme.signalRed.withValues(alpha: 0.9);
      borderColor = DashboardTheme.signalRed.withValues(alpha: 0.5);
    } else if (q == 'SOON') {
      bgColor = DashboardTheme.warningAmber.withValues(alpha: 0.9);
      borderColor = DashboardTheme.warningAmber.withValues(alpha: 0.5);
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: s(8), vertical: s(3)),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(s(6)),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        q,
        style: TextStyle(
          color: Colors.white,
          fontSize: s(12),
          fontWeight: FontWeight.w800,
          letterSpacing: s(0.5),
        ),
      ),
    );
  }

  Widget _buildMetaText(double Function(double) s, String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white70,
        fontSize: s(16),
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    );
  }

  Widget _buildBackButton(BuildContext context, double Function(double) s) {
    return LongPressFocus(
      focusNode: _backFocusNode,
      onTap: () => Navigator.of(context).maybePop(),
      child: Builder(
        builder: (ctx) {
          final hasFocus = Focus.maybeOf(ctx)?.hasFocus ?? false;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.symmetric(horizontal: s(16), vertical: s(10)),
            decoration: BoxDecoration(
              color: hasFocus
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(s(8)),
              border: Border.all(
                color: hasFocus ? Colors.white : Colors.white.withValues(alpha: 0.12),
                width: s(1.5),
              ),
              boxShadow: hasFocus
                  ? DashboardDecorations.focusGlow(context, strength: 0.7)
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_back_rounded,
                  size: s(20),
                  color: hasFocus ? Colors.black : Colors.white,
                ),
                SizedBox(width: s(8)),
                Text(
                  'BACK',
                  style: TextStyle(
                    color: hasFocus ? Colors.black : Colors.white,
                    fontSize: s(13),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
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
