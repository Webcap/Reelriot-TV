import 'package:flutter/material.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';

/// Small rounded label used across hero/detail headers (LIVE, quality,
/// IMDb rating, watched, etc.) — one consistent badge shape so these
/// signals read as the same visual language wherever they appear.
class HeroBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color borderColor;
  final IconData? icon;

  const HeroBadge({
    super.key,
    required this.label,
    required this.color,
    this.borderColor = Colors.transparent,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: s(14), vertical: s(6)),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(s(6)),
        border: Border.all(color: borderColor, width: s(1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: s(14)),
            SizedBox(width: s(6)),
          ],
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: s(14),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
