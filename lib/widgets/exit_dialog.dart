// Exit confirmation — canon direction (see dashboard_theme.dart).
//
// Previous version was a small centered, bordered card (icon-in-circle,
// stacked title/subtitle, two equal-weight buttons) — a boxed dialog
// dropped on top of the screen. This redesign replaces that shape
// entirely: a full-bleed frosted scrim over the home screen behind it,
// with a low horizontal band (message left, actions right) instead of a
// centered vertical stack, and asymmetric action weight — "STAY" reads as
// the recommended path, "EXIT APP" is a quiet secondary — instead of two
// identical buttons.

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/widgets/long_press_focus.dart';

class ExitDialog extends StatelessWidget {
  const ExitDialog({super.key});

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(color: Colors.black.withValues(alpha: 0.55)),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(s(96), s(72), s(96), s(64)),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.9),
                    Colors.black.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'EXIT REELRIOT',
                          style: DashboardTheme.sectionTitle(context)
                              .copyWith(color: DashboardTheme.signalRed),
                        ),
                        SizedBox(height: s(14)),
                        Text(
                          'Sure you want to leave?',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: s(44),
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                            height: 1.05,
                          ),
                        ),
                        SizedBox(height: s(12)),
                        Text(
                          "We'll keep your place — pick up right where you left off.",
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: s(20),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: s(72)),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ExitAction(
                        label: 'STAY',
                        isPrimary: true,
                        autofocus: true,
                        onTap: () => Navigator.of(context).pop(false),
                      ),
                      SizedBox(height: s(16)),
                      _ExitAction(
                        label: 'EXIT APP',
                        onTap: () => Navigator.of(context).pop(true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExitAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;
  final bool autofocus;

  const _ExitAction({
    required this.label,
    required this.onTap,
    this.isPrimary = false,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);
    return LongPressFocus(
      autofocus: autofocus,
      onTap: onTap,
      child: Builder(builder: (context) {
        final focused = Focus.of(context).hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: s(260),
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(vertical: s(18)),
          decoration: BoxDecoration(
            gradient: isPrimary ? DashboardTheme.accentGradient : null,
            color: isPrimary
                ? null
                : (focused
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(s(10)),
            border: Border.all(
              color: isPrimary ? Colors.transparent : Colors.white24,
              width: s(1.5),
            ),
            boxShadow: focused
                ? DashboardDecorations.focusGlow(
                    context,
                    strength: 0.8,
                    color: isPrimary ? DashboardTheme.signalRed : null,
                  )
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isPrimary ? Colors.white : Colors.white70,
              fontSize: s(18),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        );
      }),
    );
  }
}
