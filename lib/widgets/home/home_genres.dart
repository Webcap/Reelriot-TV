import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';

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
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'BROWSE BY GENRE',
          style: DashboardTheme.sectionTitle(context),
        ),
        SizedBox(height: s(16)),
        SizedBox(
          height: s(84),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: genres.length,
            itemBuilder: (context, index) {
              final g = genres[index];
              final color = g['color'] as Color;
              return Padding(
                padding: EdgeInsets.only(right: s(16)),
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
                      return Semantics(
                        label: g['name'],
                        button: true,
                        child: GestureDetector(
                          onTap: () => onGenreTap(g),
                          child: AnimatedScale(
                            scale: focused ? 1.06 : 1.0,
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: s(180),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: color.withValues(
                                  alpha: focused ? 1.0 : 0.55,
                                ),
                                borderRadius: BorderRadius.circular(s(10)),
                                border: Border.all(
                                  color: focused
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.1),
                                  width: focused ? s(2) : s(1),
                                ),
                                boxShadow: focused
                                    ? DashboardDecorations.focusGlow(
                                        context,
                                        strength: 0.6,
                                      )
                                    : null,
                              ),
                              child: Text(
                                g['name'],
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: s(20),
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
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
