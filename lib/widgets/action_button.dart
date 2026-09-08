import 'package:flutter/material.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/widgets/long_press_focus.dart';

/// Shared primary/secondary action pill used on full-bleed detail heroes
/// (movie, sports) — one focus/press treatment so "play this" and "watch
/// live" read as the same gesture everywhere.
class ActionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onTap;
  final double Function(double) s;
  final bool autofocus;
  final double? progress;
  final VoidCallback? onLongPress;

  const ActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.isPrimary,
    required this.onTap,
    required this.s,
    this.autofocus = false,
    this.progress,
    this.onLongPress,
  });

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  double _scale = 1.0;

  void _handleTap() {
    setState(() => _scale = 1.08);
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _scale = 1.0);
    });
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return LongPressFocus(
      autofocus: widget.autofocus,
      onTap: _handleTap,
      onLongPress: widget.onLongPress,
      child: Builder(builder: (context) {
        final focused = Focus.of(context).hasFocus;
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.s(8)),
          child: Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                transform: Matrix4.identity()..scaleByDouble(focused ? 1.05 : _scale, focused ? 1.05 : _scale, 1.0, 1.0),
                padding: EdgeInsets.symmetric(horizontal: widget.s(40), vertical: widget.s(16)),
                decoration: BoxDecoration(
                  gradient: widget.isPrimary && !focused ? DashboardTheme.accentGradient : null,
                  color: widget.isPrimary
                      ? (focused ? Colors.white : null)
                      : (focused ? Colors.white.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.08)),
                  borderRadius: BorderRadius.circular(widget.s(12)),
                  border: Border.all(
                    color: focused ? Colors.white : Colors.white.withValues(alpha: 0.15),
                    width: widget.s(1.5),
                  ),
                  boxShadow: focused
                      ? DashboardDecorations.focusGlow(
                          context,
                          strength: widget.isPrimary ? 0.9 : 0.6,
                          color: widget.isPrimary ? DashboardTheme.signalRed : null,
                        )
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.icon,
                      color: widget.isPrimary
                          ? (focused ? Colors.black : Colors.white)
                          : Colors.white,
                      size: widget.s(28),
                    ),
                    SizedBox(width: widget.s(12)),
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: widget.isPrimary
                            ? (focused ? Colors.black : Colors.white)
                            : Colors.white,
                        fontSize: widget.s(20),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.progress != null && widget.progress! > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: widget.s(4),
                    color: Colors.white.withValues(alpha: 0.2),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: widget.progress!,
                      child: Container(color: focused ? Colors.black : DashboardTheme.signalRed),
                    ),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}
