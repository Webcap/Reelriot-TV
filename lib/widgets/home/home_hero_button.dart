import 'package:reelriot_tv/theme/dashboard_theme.dart';
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
  final FocusNode? focusNode;

  const HomeHeroButton({
    super.key,
    required this.label,
    required this.icon,
    required this.style,
    required this.onTap,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);
    final isPrimary = style == HeroButtonStyle.primary;

    return Focus(
      focusNode: focusNode,
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

          return AnimatedScale(
            scale: focused ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(
                horizontal: isPrimary ? s(36) : s(32),
                vertical: s(18),
              ),
              decoration: BoxDecoration(
                color: isPrimary
                    ? DashboardTheme.signalRed
                    : (focused
                          ? Colors.white.withValues(alpha: 0.25)
                          : Colors.white.withValues(alpha: 0.12)),
                borderRadius: BorderRadius.circular(s(10)),
                boxShadow: focused
                    ? DashboardDecorations.focusGlow(
                        context,
                        strength: 0.7,
                        color: isPrimary ? DashboardTheme.signalRed : null,
                      )
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: s(38)),
                  SizedBox(width: s(16)),
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: s(28),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
