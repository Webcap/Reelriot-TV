import 'package:caffeine_tv/utils/responsive_utils.dart';
import 'package:caffeine_tv/widgets/poster_card.dart';
import 'package:flutter/material.dart';

class HomeUpNextRow extends StatelessWidget {
  final List<Map<String, dynamic>> watchingShows;
  final Function(int id) onFocus;
  final Function(Map<String, dynamic> show) onTap;
  final Function(Map<String, dynamic> show) onLongPress;

  const HomeUpNextRow({
    super.key,
    required this.watchingShows,
    required this.onFocus,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (watchingShows.isEmpty) return const SizedBox.shrink();
    double s(double v) => ResponsiveUtils.scale(context, v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Up Next',
          style: TextStyle(
            color: Colors.white,
            fontSize: s(48),
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: s(42)),
        SizedBox(
          height: s(520),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            primary: false,
            itemCount: watchingShows.length,
            itemBuilder: (context, index) {
              final show = watchingShows[index];
              final season = show['season_num'] as int?;
              final episode = show['episode_num'] as int?;
              final epName = show['episode_name'] as String?;
              
              String? subtitle;
              if (season != null && episode != null) {
                subtitle = 'S${season.toString().padLeft(2, '0')} E${episode.toString().padLeft(2, '0')}${epName != null ? ' • $epName' : ''}';
              }

              return Padding(
                padding: EdgeInsets.only(right: s(36)),
                child: PosterCard(
                  posterPath: show['poster_path'],
                  title: show['name'] ?? '',
                  subtitle: subtitle,
                  onFocus: () => onFocus(show['id']),
                  onLongPress: () => onLongPress(show),
                  onTap: () => onTap(show),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
