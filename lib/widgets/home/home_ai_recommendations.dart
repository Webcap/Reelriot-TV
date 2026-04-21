import 'package:caffeine_core/caffeine_core.dart';
import 'package:caffeine_tv/utils/responsive_utils.dart';
import 'package:caffeine_tv/widgets/home/home_hero_button.dart';
import 'package:caffeine_tv/widgets/poster_card.dart';
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
                  Row(
                    children: [
                      Text(
                        title ?? 'AI Recommendations',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: s(48),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(width: s(24)),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: s(12), vertical: s(4)),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE60000), Color(0xFFFF4D4D)],
                          ),
                          borderRadius: BorderRadius.circular(s(8)),
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
          borderRadius: BorderRadius.circular(s(24)),
          child: Container(
            width: s(300),
            height: s(450),
            color: Colors.white.withValues(alpha: 0.05),
            child: const Center(
              child: CircularProgressIndicator(color: Color(0xFFE60000)),
            ),
          ),
        ),
      ),
    );
  }
}
