import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';

enum HeroButtonStyle { primary, secondaryRed, secondaryWhite, iconCircle }

class HomeHeroButton extends StatelessWidget {
  final String? label;
  final IconData icon;
  final HeroButtonStyle style;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final String? semanticLabel;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;
  final ValueChanged<bool>? onFocusChange;

  const HomeHeroButton({
    super.key,
    this.label,
    required this.icon,
    required this.style,
    required this.onTap,
    this.focusNode,
    this.semanticLabel,
    this.onKeyEvent,
    this.onFocusChange,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);
    final isPrimary = style == HeroButtonStyle.primary;
    final isCircle = style == HeroButtonStyle.iconCircle;

    return Focus(
      focusNode: focusNode,
      onFocusChange: onFocusChange,
      onKeyEvent: (node, event) {
        if (onKeyEvent != null) {
          final res = onKeyEvent!(node, event);
          if (res != KeyEventResult.ignored) return res;
        }
        if (event is KeyDownEvent && TvKeys.isSelect(event.logicalKey)) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;

          Widget buttonContent;
          if (isCircle) {
            buttonContent = AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: s(72),
              height: s(72),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: focused
                    ? Colors.white.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.12),
                border: Border.all(
                  color: focused
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.25),
                  width: s(2),
                ),
                boxShadow: focused
                    ? DashboardDecorations.focusGlow(
                        context,
                        strength: 0.8,
                      )
                    : null,
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: s(34),
                ),
              ),
            );
          } else {
            // Pill / Rounded button
            buttonContent = AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.symmetric(
                horizontal: isPrimary ? s(42) : s(32),
                vertical: s(19),
              ),
              decoration: BoxDecoration(
                gradient: isPrimary ? DashboardTheme.accentGradient : null,
                color: isPrimary
                    ? null
                    : (focused
                        ? Colors.white.withValues(alpha: 0.25)
                        : Colors.white.withValues(alpha: 0.12)),
                borderRadius: BorderRadius.circular(s(32)),
                border: Border.all(
                  color: focused
                      ? Colors.white
                      : (isPrimary
                          ? Colors.transparent
                          : Colors.white.withValues(alpha: 0.2)),
                  width: focused ? s(2.5) : s(1),
                ),
                boxShadow: focused
                    ? DashboardDecorations.focusGlow(
                        context,
                        strength: isPrimary ? 0.9 : 0.6,
                        color: isPrimary ? DashboardTheme.signalRed : null,
                      )
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    color: Colors.white,
                    size: s(32),
                  ),
                  if (label != null && label!.isNotEmpty) ...[
                    SizedBox(width: s(12)),
                    Text(
                      label!,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: s(22),
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }

          return Semantics(
            label: semanticLabel ?? label ?? 'Action button',
            button: true,
            child: GestureDetector(
              onTap: onTap,
              child: AnimatedScale(
                scale: focused ? 1.08 : 1.0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: buttonContent,
              ),
            ),
          );
        },
      ),
    );
  }
}
