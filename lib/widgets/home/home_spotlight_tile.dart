import 'package:caffeine_core/caffeine_core.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/widgets/home/home_hero_button.dart';
import 'package:flutter/material.dart';

/// The dashboard's largest tile — a contained, rounded card, not a
/// full-bleed background wash. It replaces the old edge-to-edge hero: the
/// featured title is presented as the biggest tile in a grid of tiles,
/// not as a backdrop the whole screen sits on top of.
class HomeSpotlightTile extends StatelessWidget {
  final MovieDetail? focusedMovie;
  final List<MovieListItem>? trending;
  final int trendingIndex;
  final Map<int, String> liveStreamUrls;
  final VoidCallback onWatchNow;
  final VoidCallback onFavorite;
  final FocusNode? focusNode;

  const HomeSpotlightTile({
    super.key,
    required this.focusedMovie,
    required this.trending,
    required this.trendingIndex,
    required this.liveStreamUrls,
    required this.onWatchNow,
    required this.onFavorite,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);
    final movie = focusedMovie;
    final isLive = movie?.mediaType == 'live';
    final isAd = movie?.mediaType == 'ad';

    return ClipRRect(
      borderRadius: BorderRadius.circular(s(20)),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: Container(
          key: ValueKey(movie?.id),
          color: DashboardTheme.surface,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (movie?.backdropPath != null)
                Image.network(
                  movie!.backdropPath!.startsWith('http')
                      ? movie.backdropPath!
                      : 'https://image.tmdb.org/t/p/w1280${movie.backdropPath}',
                  fit: BoxFit.cover,
                ),
              // Bottom-weighted scrim so text stays legible over any art.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.55),
                      Colors.black.withValues(alpha: 0.92),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(s(40)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (isLive)
                      _chip(s, 'LIVE NOW', DashboardTheme.signalRed)
                    else if (isAd)
                      _chip(s, 'SPONSORED', Colors.white.withValues(alpha: 0.15))
                    else
                      _chip(s, 'FEATURED', Colors.white.withValues(alpha: 0.15)),
                    SizedBox(height: s(14)),
                    Text(
                      movie?.title?.toUpperCase() ?? '',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: s(52),
                        fontWeight: FontWeight.w900,
                        letterSpacing: s(-1.5),
                        height: 1.0,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: s(12)),
                    SizedBox(
                      width: s(560),
                      child: Text(
                        movie?.overview ?? '',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: s(18),
                          height: 1.35,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(height: s(28)),
                    Row(
                      children: [
                        HomeHeroButton(
                          focusNode: focusNode,
                          label: isAd ? 'Learn More' : 'Play',
                          icon: isAd
                              ? Icons.info_outline
                              : Icons.play_arrow_rounded,
                          style: HeroButtonStyle.primary,
                          onTap: onWatchNow,
                        ),
                        SizedBox(width: s(20)),
                        HomeHeroButton(
                          label: 'Favourite',
                          icon: Icons.favorite_border,
                          style: HeroButtonStyle.secondaryWhite,
                          onTap: onFavorite,
                        ),
                        const Spacer(),
                        if (trending != null && trending!.length > 1)
                          _indicators(s),
                      ],
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

  Widget _chip(double Function(double) s, String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: s(12), vertical: s(5)),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(s(4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: s(13),
          fontWeight: FontWeight.bold,
          letterSpacing: s(0.5),
        ),
      ),
    );
  }

  Widget _indicators(double Function(double) s) {
    final count = trending!.length > 6 ? 6 : trending!.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final active = i == trendingIndex;
        return Container(
          margin: EdgeInsets.only(left: s(6)),
          width: active ? s(22) : s(7),
          height: s(7),
          decoration: BoxDecoration(
            color: active
                ? DashboardTheme.signalRed
                : Colors.white.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(s(4)),
          ),
        );
      }),
    );
  }
}
