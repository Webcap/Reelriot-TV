import 'package:flutter/material.dart';

class ResponsiveUtils {
  static double scale(BuildContext context, double value) {
    final width = MediaQuery.of(context).size.width;
    // Base scale on 1080p width (1920)
    return (value * width) / 1920;
  }
}

extension ResponsiveExtension on num {
  double s(BuildContext context) => ResponsiveUtils.scale(context, toDouble());
}
