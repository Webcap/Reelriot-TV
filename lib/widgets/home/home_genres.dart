import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HomeGenresRow extends StatelessWidget {
  final List<Map<String, dynamic>> genres;
  final Function(Map<String, dynamic> genre) onGenreTap;

  const HomeGenresRow({
    super.key,
    required this.genres,
    required this.onGenreTap,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Browse by Genre',
          style: TextStyle(
            color: Colors.white,
            fontSize: s(48),
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: s(42)),
        SizedBox(
          height: s(120),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: genres.length,
            itemBuilder: (context, index) {
              final g = genres[index];
              final color = g['color'] as Color;
              return Padding(
                padding: EdgeInsets.only(right: s(24)),
                child: Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent && TvKeys.isSelect(event.logicalKey)) {
                      onGenreTap(g);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Builder(
                    builder: (context) {
                      final focused = Focus.of(context).hasFocus;
                      return GestureDetector(
                        onTap: () => onGenreTap(g),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: s(220),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                color.withValues(alpha: focused ? 1.0 : 0.6),
                                color.withValues(alpha: focused ? 0.8 : 0.3),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(s(16)),
                            border: Border.all(
                              color: focused ? Colors.white : Colors.white12,
                              width: s(focused ? 4 : 2),
                            ),
                            boxShadow: focused ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.5),
                                blurRadius: s(15),
                                spreadRadius: s(2),
                              )
                            ] : null,
                          ),
                          child: Text(
                            g['name'],
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: s(28),
                              fontWeight: focused ? FontWeight.w900 : FontWeight.w600,
                              letterSpacing: s(1),
                            ),
                          ),
                        ),
                      );
                    }
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
