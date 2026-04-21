import 'dart:ui';
import 'package:caffeine_tv/utils/responsive_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HomeTopNav extends StatelessWidget {
  final String selectedCategory;
  final Function(String) onCategorySelected;

  const HomeTopNav({
    super.key,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);
    final categories = ['Movies', 'TV Shows'];

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(s(40)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: s(32), vertical: s(8)),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(s(40)),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: s(20),
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: categories.map((cat) {
                final isSelected = cat == selectedCategory;
                return Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent && (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.select)) {
                      if (selectedCategory != cat) {
                        onCategorySelected(cat);
                      }
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Builder(
                    builder: (context) {
                      final focused = Focus.of(context).hasFocus;
                      return GestureDetector(
                        onTap: () {
                          if (selectedCategory != cat) {
                            onCategorySelected(cat);
                          }
                        },
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: s(48), vertical: s(8)),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                cat,
                                style: TextStyle(
                                  color: focused ? Colors.white : (isSelected ? Colors.white : Colors.white38),
                                  fontSize: s(42),
                                  fontWeight: isSelected || focused ? FontWeight.w600 : FontWeight.w400,
                                ),
                              ),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: EdgeInsets.only(top: s(4)),
                                height: s(4),
                                width: focused ? s(64) : (isSelected ? s(42) : 0),
                                color: focused || isSelected ? const Color(0xFFEC1D24) : Colors.transparent,
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}
