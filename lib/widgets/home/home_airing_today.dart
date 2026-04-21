import 'package:caffeine_core/caffeine_core.dart';
import 'package:caffeine_tv/utils/responsive_utils.dart';
import 'package:caffeine_tv/widgets/poster_card.dart';
import 'package:flutter/material.dart';

class HomeAiringTodayRow extends StatelessWidget {
  final List<MovieListItem>? airingToday;
  final String? dateLabel;
  final Function(int id) onFocus;
  final Function(MovieListItem item) onTap;
  final Function(MovieListItem item) onLongPress;

  const HomeAiringTodayRow({
    super.key,
    required this.airingToday,
    this.dateLabel,
    required this.onFocus,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (airingToday == null || airingToday!.isEmpty) return const SizedBox.shrink();
    double s(double v) => ResponsiveUtils.scale(context, v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Airing Today',
              style: TextStyle(
                color: Colors.white,
                fontSize: s(48),
                fontWeight: FontWeight.w800,
              ),
            ),
            if (dateLabel != null) ...[
              SizedBox(width: s(24)),
              Padding(
                padding: EdgeInsets.only(bottom: s(6)),
                child: Text(
                  dateLabel!,
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: s(22),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: s(42)),
        SizedBox(
          height: s(480),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            primary: false,
            itemCount: airingToday!.length,
            itemBuilder: (context, index) {
              final m = airingToday![index];
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
    );
  }
}
