import 'package:flutter/material.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';

/// Shared row-label style for content below a detail hero (CAST, BOXSCORE,
/// MORE LIKE THIS, etc.) — one typography treatment across detail screens.
class SectionHeader extends StatelessWidget {
  final String title;
  final double Function(double) s;

  const SectionHeader({super.key, required this.title, required this.s});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: DashboardTheme.sectionTitle(context).copyWith(fontSize: s(20)),
    );
  }
}
