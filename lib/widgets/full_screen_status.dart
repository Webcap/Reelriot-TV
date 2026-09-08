import 'package:flutter/material.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/widgets/long_press_focus.dart';

/// Full-bleed loading state matching the app's shared dashboard visual
/// language (near-black canvas, signal-red spinner) — the initial-load
/// placeholder for any screen that fetches before it can render.
class FullScreenLoading extends StatelessWidget {
  final String? message;
  const FullScreenLoading({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);
    return Scaffold(
      backgroundColor: DashboardTheme.canvasBlack,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: s(32),
              height: s(32),
              child: const CircularProgressIndicator(
                color: DashboardTheme.signalRed,
                strokeWidth: 3,
              ),
            ),
            if (message != null) ...[
              SizedBox(height: s(20)),
              Text(
                message!,
                style: TextStyle(color: Colors.white54, fontSize: s(18)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Full-bleed error state matching the app's shared dashboard visual
/// language — icon, message, and a focusable retry action.
class FullScreenError extends StatelessWidget {
  final String message;
  final String subtitle;
  final String retryLabel;
  final VoidCallback onRetry;

  const FullScreenError({
    super.key,
    required this.message,
    this.subtitle = '',
    this.retryLabel = 'Try Again',
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);
    return Scaffold(
      backgroundColor: DashboardTheme.canvasBlack,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: s(560)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: s(72),
                height: s(72),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: DashboardTheme.signalRed.withValues(alpha: 0.12),
                  border: Border.all(
                    color: DashboardTheme.signalRed.withValues(alpha: 0.4),
                    width: s(1.5),
                  ),
                ),
                child: Icon(
                  Icons.error_outline_rounded,
                  color: DashboardTheme.signalRed,
                  size: s(34),
                ),
              ),
              SizedBox(height: s(28)),
              Text(
                message,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: s(22),
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              if (subtitle.isNotEmpty) ...[
                SizedBox(height: s(10)),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.white54, fontSize: s(16)),
                  textAlign: TextAlign.center,
                ),
              ],
              SizedBox(height: s(32)),
              _RetryButton(label: retryLabel, onTap: onRetry),
            ],
          ),
        ),
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _RetryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);
    return LongPressFocus(
      autofocus: true,
      onTap: onTap,
      child: Builder(builder: (context) {
        final focused = Focus.of(context).hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(horizontal: s(36), vertical: s(18)),
          decoration: BoxDecoration(
            gradient: DashboardTheme.accentGradient,
            borderRadius: BorderRadius.circular(s(30)),
            border: Border.all(
              color: focused ? Colors.white : Colors.transparent,
              width: focused ? s(2.5) : 0,
            ),
            boxShadow: focused
                ? DashboardDecorations.focusGlow(
                    context,
                    strength: 0.9,
                    color: DashboardTheme.signalRed,
                  )
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh_rounded, color: Colors.white, size: s(22)),
              SizedBox(width: s(10)),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: s(18),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
