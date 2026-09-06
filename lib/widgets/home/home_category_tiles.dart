import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Replaces the small pill-shaped Movies/TV Shows switcher with two large,
/// equally-weighted destination tiles — a real navigational choice made at
/// the size the rest of the dashboard's tiles live at, not a footnote
/// floating above the content.
class HomeCategoryTiles extends StatelessWidget {
  final String selectedCategory;
  final Function(String) onCategorySelected;

  const HomeCategoryTiles({
    super.key,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);
    const categories = [
      {'label': 'Movies', 'icon': Icons.movie_outlined},
      {'label': 'TV Shows', 'icon': Icons.live_tv_outlined},
    ];

    return Row(
      children: categories.map((cat) {
        final label = cat['label'] as String;
        final icon = cat['icon'] as IconData;
        final isSelected = label == selectedCategory;

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: label == 'Movies' ? s(20) : 0,
            ),
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent && TvKeys.isSelect(event.logicalKey)) {
                  if (selectedCategory != label) onCategorySelected(label);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Builder(
                builder: (context) {
                  final focused = Focus.of(context).hasFocus;
                  return GestureDetector(
                    onTap: () {
                      if (selectedCategory != label) onCategorySelected(label);
                    },
                    child: AnimatedScale(
                      scale: focused ? 1.03 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: s(72),
                        padding: EdgeInsets.symmetric(horizontal: s(24)),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? DashboardTheme.signalRed
                              : (focused
                                    ? DashboardTheme.surfaceRaised
                                    : DashboardTheme.surface),
                          borderRadius: BorderRadius.circular(s(14)),
                          boxShadow: focused
                              ? DashboardDecorations.focusGlow(
                                  context,
                                  strength: 0.6,
                                )
                              : null,
                        ),
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, color: Colors.white, size: s(28)),
                            SizedBox(width: s(14)),
                            Text(
                              label,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: s(22),
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
