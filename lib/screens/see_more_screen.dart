import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:caffeine_core/caffeine_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reelriot_tv/constants.dart';
import 'package:reelriot_tv/screens/movie_detail_screen.dart';
import 'package:reelriot_tv/screens/tv_detail_screen.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/utils/quality_utils.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'package:reelriot_tv/widgets/long_press_focus.dart';
import 'package:reelriot_tv/widgets/poster_card.dart';

/// Full-screen browse grid for exploring all titles in a section, triggered
/// when the user selects a [SeeMorePosterCard].
///
/// Structure: a narrower poster grid on the left paired with a persistent
/// preview rail on the right that tracks whichever poster currently holds
/// D-pad focus — backdrop, title, quality/year/rating, and synopsis update
/// live as focus moves, so browsing surfaces enough to decide without
/// leaving the grid.
class SeeMoreScreen extends StatefulWidget {
  final String title;
  final List<MovieListItem> items;
  final bool isMovie;
  final String? subtitle;

  const SeeMoreScreen({
    super.key,
    required this.title,
    required this.items,
    this.isMovie = true,
    this.subtitle,
  });

  @override
  State<SeeMoreScreen> createState() => _SeeMoreScreenState();
}

class _SeeMoreScreenState extends State<SeeMoreScreen> {
  static const int _crossAxisCount = 4;

  final ScrollController _scrollController = ScrollController();
  final FocusNode _backFocusNode = FocusNode();
  bool _isProcessing = false;
  late MovieListItem? _focusedItem =
      widget.items.isNotEmpty ? widget.items.first : null;

  @override
  void dispose() {
    _scrollController.dispose();
    _backFocusNode.dispose();
    super.dispose();
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

    return Scaffold(
      backgroundColor: DashboardTheme.canvasBlack,
      body: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(color: DashboardTheme.canvasBlack),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, s),
              Expanded(
                child: widget.items.isEmpty
                    ? Center(
                        child: Text(
                          'No items found in this section.',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: s(18),
                          ),
                        ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _buildGrid(context, s)),
                          _buildPreviewRail(context, s),
                        ],
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context, double Function(double) s) {
    return GridView.builder(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(s(64), s(32), s(32), s(80)),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _crossAxisCount,
        // Exact 2:3 poster ratio (153 × 230) so grid cells match PosterCard's
        // internal fixed dimensions.
        childAspectRatio: 153 / 230,
        crossAxisSpacing: s(28),
        mainAxisSpacing: s(28),
      ),
      itemCount: widget.items.length,
      itemBuilder: (context, index) {
        final item = widget.items[index];
        final isEndOfRow = (index + 1) % _crossAxisCount == 0 ||
            index == widget.items.length - 1;

        return PosterCard(
          posterPath: item.posterPath,
          title: item.title ?? 'Unknown',
          onTap: () => _navigateToDetail(item),
          onFocus: () => setState(() => _focusedItem = item),
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

  Widget _buildPreviewRail(BuildContext context, double Function(double) s) {
    final item = _focusedItem;
    final railWidth = s(440);

    return Container(
      width: railWidth,
      decoration: BoxDecoration(
        color: DashboardTheme.canvasCool,
        border: Border(
          left: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: s(1),
          ),
        ),
      ),
      child: item == null
          ? const SizedBox.shrink()
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: SingleChildScrollView(
                key: ValueKey(item.id),
                child: _buildPreviewContent(context, s, item),
              ),
            ),
    );
  }

  Widget _buildPreviewContent(
    BuildContext context,
    double Function(double) s,
    MovieListItem item,
  ) {
    final backdropUrl = (item.backdropPath != null && item.backdropPath!.isNotEmpty)
        ? '$tmdbImageBaseUrl/w780${item.backdropPath}'
        : null;
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (backdropUrl != null)
                CachedNetworkImage(
                  imageUrl: backdropUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) =>
                      Container(color: DashboardTheme.surface),
                  errorWidget: (context, url, error) =>
                      Container(color: DashboardTheme.surface),
                )
              else
                Container(color: DashboardTheme.surface),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      DashboardTheme.canvasCool.withValues(alpha: 0.4),
                      DashboardTheme.canvasCool,
                    ],
                    stops: const [0.0, 0.6, 1.0],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(s(28), s(20), s(28), s(28)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title ?? 'Unknown',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: s(26),
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: s(12)),
              Wrap(
                spacing: s(10),
                runSpacing: s(8),
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (quality != null) _buildMetaBadge(s, quality),
                  if (year != null) _buildMetaText(s, year),
                  if (rating != null)
                    _buildMetaText(s, '★ $rating', color: Colors.white70),
                ],
              ),
              if (item.overview != null && item.overview!.isNotEmpty) ...[
                SizedBox(height: s(18)),
                Text(
                  item.overview!,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: s(16),
                    fontWeight: FontWeight.w400,
                    height: 1.5,
                  ),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              SizedBox(height: s(24)),
              Row(
                children: [
                  Icon(
                    Icons.keyboard_return_rounded,
                    color: Colors.white38,
                    size: s(16),
                  ),
                  SizedBox(width: s(8)),
                  Text(
                    'SELECT TO VIEW DETAILS',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: s(11),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetaBadge(double Function(double) s, String quality) {
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
          fontSize: s(11),
          fontWeight: FontWeight.w800,
          letterSpacing: s(0.5),
        ),
      ),
    );
  }

  Widget _buildMetaText(double Function(double) s, String text, {Color? color}) {
    return Text(
      text,
      style: TextStyle(
        color: color ?? Colors.white54,
        fontSize: s(13),
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    );
  }

  Widget _buildHeader(BuildContext context, double Function(double) s) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(s(64), s(40), s(64), s(20)),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.08),
                width: s(1.5),
              ),
            ),
          ),
          child: Row(
            children: [
              // Back Button
              LongPressFocus(
                focusNode: _backFocusNode,
                onTap: () => Navigator.of(context).maybePop(),
                child: Builder(
                  builder: (ctx) {
                    final hasFocus = Focus.maybeOf(ctx)?.hasFocus ?? false;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: EdgeInsets.symmetric(
                        horizontal: s(16),
                        vertical: s(10),
                      ),
                      decoration: BoxDecoration(
                        color: hasFocus
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(s(8)),
                        border: Border.all(
                          color: hasFocus
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.12),
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
              ),
              SizedBox(width: s(32)),

              // Title and Section Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          widget.title.toUpperCase(),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: s(28),
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            height: 1.1,
                          ),
                        ),
                        SizedBox(width: s(16)),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: s(10),
                            vertical: s(4),
                          ),
                          decoration: BoxDecoration(
                            color: DashboardTheme.signalRed.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(s(6)),
                            border: Border.all(
                              color: DashboardTheme.signalRed.withValues(alpha: 0.4),
                              width: s(1),
                            ),
                          ),
                          child: Text(
                            '${widget.items.length} TITLES',
                            style: TextStyle(
                              color: DashboardTheme.signalRed,
                              fontSize: s(11),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: s(4)),
                    Text(
                      widget.subtitle ?? 'EXPLORE ALL TITLES IN THIS COLLECTION',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: s(12),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
