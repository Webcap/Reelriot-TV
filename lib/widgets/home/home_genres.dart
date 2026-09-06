import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HomeGenresRow extends StatelessWidget {
  final List<Map<String, dynamic>> genres;
  final Function(Map<String, dynamic> genre) onGenreTap;
  final int index;

  const HomeGenresRow({
    super.key,
    required this.genres,
    required this.onGenreTap,
    this.index = 1,
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
            fontSize: s(40),
            fontWeight: FontWeight.w700,
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
                    if (event is KeyDownEvent &&
                        TvKeys.isSelect(event.logicalKey)) {
                      onGenreTap(g);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Builder(
                    builder: (context) {
                      final focused = Focus.of(context).hasFocus;
                      // Each genre keeps one flat identity color — no
                      // gradient wash — dimmed at rest, full and lifted
                      // under focus.
                      return GestureDetector(
                        onTap: () => onGenreTap(g),
                        child: AnimatedScale(
                          scale: focused ? 1.06 : 1.0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: s(220),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: color.withValues(
                                alpha: focused ? 1.0 : 0.55,
                              ),
                              borderRadius: BorderRadius.circular(s(12)),
                              boxShadow: focused
                                  ? DashboardDecorations.focusGlow(
                                      context,
                                      strength: 0.5,
                                    )
                                  : null,
                            ),
                            child: Text(
                              g['name'],
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: s(26),
                                fontWeight: FontWeight.w700,
                                letterSpacing: s(0.5),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
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
