import 'package:caffeine_core/caffeine_core.dart';
import 'package:caffeine_tv/utils/responsive_utils.dart';
import 'package:caffeine_tv/widgets/poster_card.dart';
import 'package:flutter/material.dart';

class HomeMediaRow extends StatelessWidget {
  final String title;
  final List<MovieListItem>? items;
  final Function(int id) onFocus;
  final Function(MovieListItem item) onTap;
  final Function(MovieListItem item) onLongPress;

  const HomeMediaRow({
    super.key,
    required this.title,
    required this.items,
    required this.onFocus,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (items == null || items!.isEmpty) return const SizedBox.shrink();
    double s(double v) => ResponsiveUtils.scale(context, v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontSize: s(48),
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: s(42)),
        SizedBox(
          height: s(480),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            primary: false,
            itemCount: items!.length,
            itemBuilder: (context, index) {
              final m = items![index];
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
