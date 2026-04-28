import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/widgets/home/home_hero_button.dart';
import 'package:reelriot_tv/widgets/poster_card.dart';
import 'package:reelriot_tv/utils/quality_utils.dart';
import 'package:flutter/material.dart';

class HomeContinueWatchingRow extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  final Function(int id, bool isMovie) onFocus;
  final Function() onClearAll;
  final Function(Map<String, dynamic> item) onTap;
  final Function(Map<String, dynamic> item) onLongPress;

  const HomeContinueWatchingRow({
    super.key,
    required this.history,
    required this.onFocus,
    required this.onClearAll,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) return const SizedBox.shrink();
    double s(double v) => ResponsiveUtils.scale(context, v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: s(72)),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Continue Watching',
              style: TextStyle(
                color: Colors.white,
                fontSize: s(48),
                fontWeight: FontWeight.w800,
              ),
            ),
            HomeHeroButton(
              label: 'Clear All',
              icon: Icons.delete_outline,
              style: HeroButtonStyle.secondaryWhite,
              onTap: onClearAll,
            ),
          ],
        ),
        SizedBox(height: s(42)),
        SizedBox(
          height: s(480),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            primary: false,
            itemCount: history.length,
            itemBuilder: (context, index) {
              final h = history[index];
              final isMovie = h['type'] == 'movie';
              final mediaId = h['media_id'] as int;
              
              String? subtitle;
              if (!isMovie) {
                final season = h['season_num'] as int?;
                final episode = h['episode_num'] as int?;
                final epName = h['episode_name'] as String?;
                if (season != null && episode != null) {
                  subtitle = 'S${season.toString().padLeft(2, '0')} E${episode.toString().padLeft(2, '0')}${epName != null ? ' • $epName' : ''}';
                }
              }

              return Padding(
                padding: EdgeInsets.only(right: s(36)),
                child: PosterCard(
                  posterPath: h['poster_path'],
                  title: h['title'] ?? '',
                  subtitle: subtitle,
                  onFocus: () => onFocus(mediaId, isMovie),
                  onLongPress: () => onLongPress(h),
                  onTap: () => onTap(h),
                  quality: QualityUtils.getQualityBadgeSync(
                    releaseDate: h['release_date'] as String?,
                    isMovie: isMovie,
                  ),
                  mediaId: mediaId,
                  isMovie: isMovie,
                  releaseDate: h['release_date'] as String?,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
