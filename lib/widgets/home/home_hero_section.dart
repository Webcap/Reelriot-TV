import 'package:caffeine_core/caffeine_core.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/widgets/home/home_hero_button.dart';
import 'package:flutter/material.dart';

class HomeHeroSection extends StatelessWidget {
  final MovieDetail? focusedMovie;
  final List<MovieListItem>? trending;
  final int trendingIndex;
  final Map<int, String> liveStreamUrls;
  final VoidCallback onWatchNow;
  final VoidCallback onFavorite;
  final bool backgroundOnly;
  final bool contentOnly;
  final FocusNode? focusNode;

  const HomeHeroSection({
    super.key,
    required this.focusedMovie,
    required this.trending,
    required this.trendingIndex,
    required this.liveStreamUrls,
    required this.onWatchNow,
    required this.onFavorite,
    this.backgroundOnly = false,
    this.contentOnly = false,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);

    if (contentOnly) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(height: s(150)),
          SizedBox(
            height: s(620),
            child: _buildContentSwitcher(context, s),
          ),
        ],
      );
    }

    return Stack(
      children: [
        // Hero Background
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: focusedMovie?.backdropPath != null
            ? Container(
                key: ValueKey(focusedMovie!.id),
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: NetworkImage(
                      focusedMovie!.backdropPath != null && focusedMovie!.backdropPath!.startsWith('http')
                          ? focusedMovie!.backdropPath!
                          : 'https://image.tmdb.org/t/p/w1280${focusedMovie!.backdropPath}'
                    ),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                      const Color(0xFFEC1D24).withValues(alpha: 0.35),
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
                Colors.black.withValues(alpha: 0.95),
                const Color(0xFF7F1D1D).withValues(alpha: 0.6),
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
        if (!backgroundOnly)
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: s(96)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(height: s(150)),
                  SizedBox(
                    height: s(620),
                    child: _buildContentSwitcher(context, s),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildContentSwitcher(BuildContext context, double Function(double) s) {
    return AnimatedSwitcher(
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
      child: focusedMovie == null 
        ? const SizedBox.shrink()
        : Column(
            key: ValueKey('hero_content_${focusedMovie!.id}'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Brand Label
              Container(
                padding: EdgeInsets.symmetric(horizontal: s(12), vertical: s(4)),
                decoration: BoxDecoration(
                  color: const Color(0xFFEC1D24),
                  borderRadius: BorderRadius.circular(s(4)),
                ),
                child: Text(
                  focusedMovie?.mediaType == 'live' ? 'LIVE NOW' : 'TRENDING', 
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: s(15),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(height: s(18)),
              Text(
                focusedMovie?.title?.toUpperCase() ?? '',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: s(130),
                  fontWeight: FontWeight.w900,
                  letterSpacing: s(-4),
                  height: 0.9,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: s(24)),
              SizedBox(
                width: s(780),
                child: Text(
                  focusedMovie?.overview ?? '',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
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
                  HomeHeroButton(
                    focusNode: focusNode,
                    label: 'Watch Now',
                    icon: Icons.play_arrow_outlined,
                    style: HeroButtonStyle.primary,
                    onTap: onWatchNow,
                  ),
                  SizedBox(width: s(36)),
                  HomeHeroButton(
                    label: 'Favourite',
                    icon: Icons.favorite_border,
                    style: HeroButtonStyle.secondaryRed,
                    onTap: onFavorite,
                  ),
                ],
              ),
              SizedBox(height: s(48)),
              _buildSliderIndicators(context),
            ],
          ),
    );
  }

  Widget _buildSliderIndicators(BuildContext context) {
    if (trending == null || trending!.isEmpty) return const SizedBox.shrink();
    double s(double v) => ResponsiveUtils.scale(context, v);
    
    final displayCount = trending!.length > 10 ? 10 : trending!.length;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(displayCount, (i) {
        final isActive = i == trendingIndex;
        return Padding(
          padding: EdgeInsets.only(right: s(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: isActive ? s(80) : s(40),
                height: s(4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: isActive ? 0.3 : 0.1),
                  borderRadius: BorderRadius.circular(s(2)),
                ),
                clipBehavior: Clip.antiAlias,
                child: isActive 
                  ? TweenAnimationBuilder<double>(
                      key: ValueKey('indicator_${focusedMovie?.id}'),
                      tween: Tween<double>(begin: 0.0, end: 1.0),
                      duration: const Duration(seconds: 8),
                      builder: (context, value, _) {
                        return FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: value,
                          child: Container(
                            color: const Color(0xFFEC1D24),
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
}
