import 'package:caffeine_core/caffeine_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'package:reelriot_tv/widgets/home/home_hero_button.dart';
import 'package:reelriot_tv/widgets/tv_skeleton_loader.dart';

/// Full-Bleed Parallax Backdrop Widget.
///
/// Fills the entire screen behind the scroll view.
/// Contains the background artwork, cross-fade transition, left-weighted scrim,
/// and bottom-to-black fade scrim.
class CinematicBackdrop extends StatelessWidget {
  final MovieDetail? focusedMovie;
  final double parallaxOffset;

  const CinematicBackdrop({
    super.key,
    required this.focusedMovie,
    this.parallaxOffset = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final movie = focusedMovie;
    final String? backdropUrl = movie?.backdropPath != null
        ? (movie!.backdropPath!.startsWith('http')
            ? movie.backdropPath!
            : 'https://image.tmdb.org/t/p/w1280${movie.backdropPath}')
        : null;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Backdrop Image with Cross-Fade
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: Container(
            key: ValueKey(movie?.id),
            color: DashboardTheme.canvasBlack,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (backdropUrl != null)
                  Positioned(
                    top: -parallaxOffset * 0.25,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Image.network(
                      backdropUrl,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      errorBuilder: (context, error, stackTrace) =>
                          Container(color: DashboardTheme.surface),
                    ),
                  )
                else
                  Container(color: DashboardTheme.surface),

                // Left Scrim (protects text contrast)
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: DashboardTheme.heroLeftScrim,
                    ),
                  ),
                ),

                // Bottom Scrim (smooth fade to pure black)
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: DashboardTheme.heroBottomScrim,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// In-Flow Hero Content Block (Badges, Title, Meta, Actions, Indicators).
///
/// Renders naturally inside the scroll view above the shelves, preventing
/// any possibility of collision or overlap.
class CinematicHeroBlock extends StatelessWidget {
  final MovieDetail? focusedMovie;
  final List<MovieListItem>? trending;
  final int trendingIndex;
  final Map<int, String> liveStreamUrls;
  final VoidCallback onWatchNow;
  final VoidCallback onFavorite;
  final FocusNode? focusNode;
  final VoidCallback? onMoveToNav;
  final VoidCallback? onHeroFocused;

  const CinematicHeroBlock({
    super.key,
    required this.focusedMovie,
    required this.trending,
    required this.trendingIndex,
    required this.liveStreamUrls,
    required this.onWatchNow,
    required this.onFavorite,
    this.focusNode,
    this.onMoveToNav,
    this.onHeroFocused,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);
    final movie = focusedMovie;

    if (movie == null) {
      return _buildSkeleton(context, s);
    }

    final isLive = movie.mediaType == 'live';
    final isAd = movie.mediaType == 'ad';

    String? releaseYear;
    if (movie.releaseDate != null && movie.releaseDate!.isNotEmpty) {
      releaseYear = movie.releaseDate!.split('-').first;
    }

    int? matchPercent;
    if (movie.voteAverage != null && movie.voteAverage! > 0) {
      matchPercent = (movie.voteAverage! * 10).clamp(50, 99).toInt();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Badges and Meta line
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLive)
              _buildBadge(s, 'LIVE NOW', DashboardTheme.signalRed)
            else if (isAd)
              _buildBadge(s, 'SPONSORED', Colors.white.withValues(alpha: 0.18))
            else
              _buildBadge(s, 'FEATURED', Colors.white.withValues(alpha: 0.18)),
            if (matchPercent != null) ...[
              SizedBox(width: s(14)),
              Text(
                '$matchPercent% Match',
                style: TextStyle(
                  color: const Color(0xFF46D369),
                  fontSize: s(18),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ],
            if (releaseYear != null) ...[
              SizedBox(width: s(14)),
              Text(
                releaseYear,
                style: DashboardTheme.heroMeta(context),
              ),
            ],
            if (movie.runtime != null && movie.runtime! > 0) ...[
              SizedBox(width: s(14)),
              Text(
                '${movie.runtime}m',
                style: DashboardTheme.heroMeta(context),
              ),
            ],
          ],
        ),
        SizedBox(height: s(18)),

        // High-impact Title
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: s(1350)),
          child: Text(
            (movie.title ?? '').toUpperCase(),
            style: DashboardTheme.heroTitle(context),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),

        // Brief Overview
        if (movie.overview != null && movie.overview!.isNotEmpty) ...[
          SizedBox(height: s(18)),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: s(960)),
            child: Text(
              movie.overview!,
              style: DashboardTheme.heroMeta(context).copyWith(
                height: 1.4,
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: s(22),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],

        SizedBox(height: s(34)),

        // Action Buttons Row & Indicators
        Row(
          children: [
            HomeHeroButton(
              focusNode: focusNode,
              label: isAd ? 'LEARN MORE' : 'PLAY',
              icon: isAd
                  ? Icons.info_outline
                  : Icons.play_arrow_rounded,
              style: HeroButtonStyle.primary,
              onTap: onWatchNow,
              onKeyEvent: _handleHeroKey,
              onFocusChange: (focused) {
                if (focused) onHeroFocused?.call();
              },
            ),
            SizedBox(width: s(18)),
            HomeHeroButton(
              icon: Icons.add_rounded,
              style: HeroButtonStyle.iconCircle,
              semanticLabel: 'Add to My List',
              onTap: onFavorite,
              onKeyEvent: _handleHeroKey,
              onFocusChange: (focused) {
                if (focused) onHeroFocused?.call();
              },
            ),
            const Spacer(),
            if (trending != null && trending!.length > 1)
              _buildIndicators(s),
          ],
        ),
      ],
    );
  }

  KeyEventResult _handleHeroKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && TvKeys.isUp(event.logicalKey)) {
      onHeroFocused?.call();
      if (onMoveToNav != null) {
        onMoveToNav!();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Widget _buildBadge(double Function(double) s, String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: s(14), vertical: s(6)),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(s(6)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: s(1),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: s(14),
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildIndicators(double Function(double) s) {
    final count = trending!.length > 6 ? 6 : trending!.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final active = i == trendingIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: EdgeInsets.only(left: s(8)),
          width: active ? s(28) : s(8),
          height: s(6),
          decoration: BoxDecoration(
            color: active
                ? DashboardTheme.signalRed
                : Colors.white.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(s(3)),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: DashboardTheme.signalRed.withValues(alpha: 0.6),
                      blurRadius: s(6),
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }

  /// Zero-CLS Skeleton matching exact visual footprint
  Widget _buildSkeleton(BuildContext context, double Function(double) s) {
    return TvShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: s(150),
            height: s(26),
            decoration: BoxDecoration(
              color: DashboardTheme.surfaceRaised,
              borderRadius: BorderRadius.circular(s(6)),
            ),
          ),
          SizedBox(height: s(18)),
          Container(
            width: s(740),
            height: s(90),
            decoration: BoxDecoration(
              color: DashboardTheme.surfaceRaised,
              borderRadius: BorderRadius.circular(s(8)),
            ),
          ),
          SizedBox(height: s(18)),
          Container(
            width: s(540),
            height: s(40),
            decoration: BoxDecoration(
              color: DashboardTheme.surfaceRaised,
              borderRadius: BorderRadius.circular(s(6)),
            ),
          ),
          SizedBox(height: s(34)),
          Row(
            children: [
              Container(
                width: s(176),
                height: s(72),
                decoration: BoxDecoration(
                  color: DashboardTheme.surfaceRaised,
                  borderRadius: BorderRadius.circular(s(36)),
                ),
              ),
              SizedBox(width: s(18)),
              Container(
                width: s(72),
                height: s(72),
                decoration: const BoxDecoration(
                  color: DashboardTheme.surfaceRaised,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
