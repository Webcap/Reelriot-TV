import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum HeroButtonStyle { primary, secondaryRed, secondaryWhite }

class HomeHeroButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final HeroButtonStyle style;
  final VoidCallback onTap;

  const HomeHeroButton({
    super.key,
    required this.label,
    required this.icon,
    required this.style,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);

    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && TvKeys.isSelect(event.logicalKey)) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          
          Color bgColor = Colors.transparent;
          Color borderColor = Colors.white24;
          Color textColor = Colors.white;

          if (style == HeroButtonStyle.primary) {
            bgColor = Colors.white;
            textColor = Colors.black;
            borderColor = Colors.transparent;
          } else if (style == HeroButtonStyle.secondaryRed) {
            borderColor = const Color(0xFFE60000);
          } else {
            borderColor = Colors.white;
          }

          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(horizontal: s(42), vertical: s(18)),
            decoration: BoxDecoration(
              color: bgColor.withValues(alpha: focused ? 0.8 : 1.0),
              borderRadius: BorderRadius.circular(s(12)),
              border: Border.all(
                color: focused ? Colors.white : borderColor,
                width: s(3.5),
              ),
              boxShadow: focused ? [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.3),
                  blurRadius: s(20),
                  spreadRadius: s(2),
                )
              ] : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: textColor, size: s(42)),
                SizedBox(width: s(18)),
                Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                    fontSize: s(30),
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );
  }
}
