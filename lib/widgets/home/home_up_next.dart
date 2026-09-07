import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'package:reelriot_tv/widgets/poster_card.dart';

class HomeUpNextRow extends StatelessWidget {
  final List<Map<String, dynamic>> watchingShows;
  final Function(int id) onFocus;
  final Function(Map<String, dynamic> show) onTap;
  final Function(Map<String, dynamic> show) onLongPress;
  final int index;
  final VoidCallback? onMoveUp;

  const HomeUpNextRow({
    super.key,
    required this.watchingShows,
    required this.onFocus,
    required this.onTap,
    required this.onLongPress,
    this.index = 1,
    this.onMoveUp,
  });

  @override
  Widget build(BuildContext context) {
    if (watchingShows.isEmpty) return const SizedBox.shrink();
    double s(double v) => ResponsiveUtils.scale(context, v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'UP NEXT',
          style: DashboardTheme.sectionTitle(context),
        ),
        SizedBox(height: s(12)),
        SizedBox(
          height: s(245),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            primary: false,
            clipBehavior: Clip.none,
            itemCount: watchingShows.length,
            itemBuilder: (context, index) {
              final show = watchingShows[index];
              KeyEventResult handleCardKey(FocusNode node, KeyEvent event) {
                if (onMoveUp != null &&
                    event is KeyDownEvent &&
                    TvKeys.isUp(event.logicalKey)) {
                  onMoveUp!();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              }

              return Padding(
                padding: EdgeInsets.only(right: s(16)),
                child: PosterCard(
                  posterPath: show['poster_path'],
                  title: show['name'] ?? '',
                  onFocus: () => onFocus(show['id'] as int),
                  onLongPress: () => onLongPress(show),
                  onTap: () => onTap(show),
                  mediaId: show['id'] as int,
                  isMovie: false,
                  showTitle: false,
                  onKeyEvent: onMoveUp != null ? handleCardKey : null,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
