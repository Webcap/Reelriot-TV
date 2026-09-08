import 'package:flutter/material.dart';

/// Semantic Color Architecture for 10-foot TV UI (IEC/IEEE 82079-1 & WCAG 2.1 AA Compliant)
/// 5-Step Shade Ramps: lightest (100), light (300), default (500), dark (700), darkest (900)
abstract class TvSemanticColors {
  // Info (neutral / instructional)
  static const Color infoLightest = Color(0xFFE0F2FE); // 100
  static const Color infoLight = Color(0xFF7DD3FC);    // 300
  static const Color infoDefault = Color(0xFF0EA5E9);  // 500
  static const Color infoDark = Color(0xFF0369A1);     // 700
  static const Color infoDarkest = Color(0xFF082F49);  // 900
  static const Color infoSurface = Color(0x1F0EA5E9);  // 12% alpha
  static const Color infoBorder = Color(0x470EA5E9);   // 28% alpha

  // Success (confirmation / positive action)
  static const Color successLightest = Color(0xFFDCFCE7); // 100
  static const Color successLight = Color(0xFF86EFAC);    // 300
  static const Color successDefault = Color(0xFF10B981);  // 500
  static const Color successDark = Color(0xFF047857);     // 700
  static const Color successDarkest = Color(0xFF064E3B);  // 900
  static const Color successSurface = Color(0x1F10B981);  // 12% alpha
  static const Color successBorder = Color(0x4710B981);   // 28% alpha

  // Warning (caution / attention required)
  static const Color warningLightest = Color(0xFFFEF3C7); // 100
  static const Color warningLight = Color(0xFFFCD34D);    // 300
  static const Color warningDefault = Color(0xFFF59E0B);  // 500
  static const Color warningDark = Color(0xFFB45309);     // 700
  static const Color warningDarkest = Color(0xFF78350F);  // 900
  static const Color warningSurface = Color(0x1FF59E0B);  // 12% alpha
  static const Color warningBorder = Color(0x47F59E0B);   // 28% alpha

  // Danger (destructive / error states)
  static const Color dangerLightest = Color(0xFFFEE2E2); // 100
  static const Color dangerLight = Color(0xFFFCA5A5);    // 300
  static const Color dangerDefault = Color(0xFFEF4444);  // 500
  static const Color dangerDark = Color(0xFFB91C1C);     // 700
  static const Color dangerDarkest = Color(0xFF7F1D1D);  // 900
  static const Color dangerSurface = Color(0x1FEF4444);  // 12% alpha
  static const Color dangerBorder = Color(0x47EF4444);   // 28% alpha
}
