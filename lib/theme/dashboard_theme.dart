// Home dashboard — canon direction.
//
// Two themed visual worlds were tried on this screen ("Call Board" backstage
// brass/walnut, then "Home Video" video-rental-store shelves) and rejected.
// The standing direction (recorded in PRODUCT.md under Brand Commitments) is
// the category-standard streaming-TV dashboard, played straight at high
// craft, not reinterpreted as a themed concept: near-black canvas, hero +
// shelves, neutrals plus the one Signal Red accent. Craft bar: Netflix
// (browse density, hero/row composition) and Apple TV (restraint,
// typography polish, smooth soft-focus lift on selection).
//
// Signal Red is the ONE color that carries meaning — live, selected,
// primary action. Generic D-pad focus is a plain soft white lift, not a
// color change, the same way Netflix and Apple TV both do it — this keeps
// red legible as "act here" instead of diluting it into a hover color.

import 'package:flutter/material.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';

abstract class DashboardTheme {
  // Canvas — true black (OLED contrast, matches the player and other
  // full-bleed screens).
  static const Color canvasBlack = Color(0xFF000000);

  // Neutral surfaces — plain dark grays, no material metaphor. Used for
  // cards before artwork loads, panels, and the nav rail.
  static const Color surface = Color(0xFF181818);
  static const Color surfaceRaised = Color(0xFF262626);

  // Generic hairline for dividers/resting borders.
  static const Color divider = Colors.white12;
  static const Color dividerBright = Colors.white24;

  // The one accent. Live, selected, primary action, alert.
  static const Color signalRed = Color(0xFFEC1D24);
  static const Color signalRedDark = Color(0xFF9E1217);

  // Status (semantic, used sparingly)
  static const Color warningAmber = Color(0xFFF59E0B);
  static const Color successGreen = Color(0xFF16A34A);
  static const Color infoBlue = Color(0xFF3B82F6);

  // Cinematic Hero Proportions & Dimensions
  static const double heroHeightFraction = 0.75; // 75% of viewport height
  static const double topNavHeight = 104.0;

  // Gradients for cinematic full bleed
  static const LinearGradient heroLeftScrim = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xF2000000), // ~95% black
      Color(0xD9000000), // ~85% black
      Color(0x66000000), // ~40% black
      Colors.transparent,
    ],
    stops: [0.0, 0.35, 0.65, 1.0],
  );

  static const LinearGradient heroBottomScrim = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [
      Color(0xFF000000),
      Color(0xF2000000),
      Color(0x99000000),
      Colors.transparent,
    ],
    stops: [0.0, 0.25, 0.6, 1.0],
  );

  static const LinearGradient topNavScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xCC000000), // ~80% black
      Color(0x4D000000), // ~30% black
      Colors.transparent,
    ],
    stops: [0.0, 0.6, 1.0],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFF2E35),
      Color(0xFFC0141A),
    ],
  );

  // Typography presets
  static TextStyle heroTitle(BuildContext context) {
    final s = ResponsiveUtils.scale(context, 1.0);
    return TextStyle(
      color: Colors.white,
      fontSize: 58.0 * s,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.5,
      height: 1.08,
    );
  }

  static TextStyle heroMeta(BuildContext context) {
    final s = ResponsiveUtils.scale(context, 1.0);
    return TextStyle(
      color: Colors.white70,
      fontSize: 18.0 * s,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
    );
  }

  static TextStyle sectionTitle(BuildContext context) {
    final s = ResponsiveUtils.scale(context, 1.0);
    return TextStyle(
      color: Colors.white,
      fontSize: 16.0 * s,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    );
  }
}

abstract class DashboardDecorations {
  /// The one focus treatment used everywhere: a soft lift, not a color
  /// change. [color] defaults to white (generic focus); pass
  /// [DashboardTheme.signalRed] only where the element is itself the
  /// primary action, so red still means something when it appears.
  static List<BoxShadow> focusGlow(
    BuildContext context, {
    double strength = 1.0,
    Color? color,
  }) {
    double s(double v) => ResponsiveUtils.scale(context, v);
    final glow = color ?? Colors.white;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.45 * strength),
        blurRadius: s(20) * strength,
        offset: Offset(0, s(10) * strength),
      ),
      BoxShadow(
        color: glow.withValues(alpha: 0.22 * strength),
        blurRadius: s(20) * strength,
        spreadRadius: s(0.5) * strength,
      ),
    ];
  }
}
