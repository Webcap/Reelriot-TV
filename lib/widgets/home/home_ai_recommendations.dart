import 'package:caffeine_core/caffeine_core.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/widgets/home/home_hero_button.dart';
import 'package:reelriot_tv/widgets/poster_card.dart';
import 'package:reelriot_tv/utils/quality_utils.dart';
import 'package:flutter/material.dart';

class HomeAiRecommendationsRow extends StatelessWidget {
  final List<MovieListItem>? recommendations;
  final String? title;
  final bool loading;
  final VoidCallback onRefresh;
  final Function(int id) onFocus;
  final Function(MovieListItem item) onTap;
  final Function(MovieListItem item) onLongPress;

  const HomeAiRecommendationsRow({
    super.key,
    required this.recommendations,
    required this.title,
    required this.loading,
    required this.onRefresh,
    required this.onFocus,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: recommendations != null || loading
          ? Column(
              key: const ValueKey('ai_recommendations_section'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: s(72)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              title ?? 'AI Recommendations',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: s(40),
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: s(24)),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: s(12),
                              vertical: s(4),
                            ),
                            decoration: BoxDecoration(
                              color: DashboardTheme.signalRed,
                              borderRadius: BorderRadius.circular(s(6)),
                            ),
                            child: Text(
                              'BETA',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: s(14),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: s(24)),
                    HomeHeroButton(
                      label: 'Refresh',
                      icon: Icons.auto_awesome_outlined,
                      style: HeroButtonStyle.secondaryWhite,
                      onTap: onRefresh,
                    ),
                  ],
                ),
                SizedBox(height: s(42)),
                SizedBox(
                  height: s(480),
                  child: loading
                      ? _buildLoadingState(context)
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          primary: false,
                          itemCount: recommendations!.length,
                          itemBuilder: (context, index) {
                            final m = recommendations![index];
                            return Padding(
                              padding: EdgeInsets.only(right: s(36)),
                              child: PosterCard(
                                posterPath: m.posterPath,
                                title: m.title ?? '',
                                onFocus: () => onFocus(m.id),
                                onLongPress: () => onLongPress(m),
                                onTap: () => onTap(m),
                                quality: QualityUtils.getQualityBadgeSync(
                                  mediaId: m.id,
                                  releaseDate: m.releaseDate,
                                  isMovie:
                                      true, // Recommendations are currently movies
                                ),
                                mediaId: m.id,
                                isMovie: true,
                                releaseDate: m.releaseDate,
                              ),
                            );
                          },
                        ),
                ),
              ],
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 5,
      itemBuilder: (context, index) => Padding(
        padding: EdgeInsets.only(right: s(36)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(s(10)),
          child: Container(
            width: s(300),
            height: s(450),
            color: DashboardTheme.surface,
            child: Center(
              child: CircularProgressIndicator(
                color: DashboardTheme.signalRed,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
