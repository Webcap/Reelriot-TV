import 'package:flutter/material.dart';
import 'package:reelriot_tv/screens/dev_build_settings_screen.dart';
import 'package:reelriot_tv/services/beta_service.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/widgets/long_press_focus.dart';

/// Top bar overlay badge displayed when running on a non-stable build channel.
///
/// Features:
/// - Semantic color ramp: warning amber for 'beta', info blue for 'dev'
/// - Zero-CLS: renders SizedBox.shrink() when on 'stable' channel
/// - Interactive: clicking/selecting opens DevBuildSettingsScreen
/// - Accessible TV focus ring adhering to WCAG 2.1 AA
class DevBuildBadge extends StatefulWidget {
  final FocusNode? focusNode;

  const DevBuildBadge({
    super.key,
    this.focusNode,
  });

  @override
  State<DevBuildBadge> createState() => _DevBuildBadgeState();
}

class _DevBuildBadgeState extends State<DevBuildBadge> {
  String _channel = 'stable';

  @override
  void initState() {
    super.initState();
    _loadChannel();
  }

  Future<void> _loadChannel() async {
    final ch = await BetaService.getBuildChannel();
    if (mounted) {
      setState(() => _channel = ch);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_channel == 'stable') {
      return const SizedBox.shrink();
    }

    double s(double v) => ResponsiveUtils.scale(context, v);

    final isBeta = _channel == 'beta';
    final Color badgeColor =
        isBeta ? DashboardTheme.warningAmber : DashboardTheme.infoBlue;

    return Padding(
      padding: EdgeInsets.only(right: s(16)),
      child: LongPressFocus(
        focusNode: widget.focusNode,
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const DevBuildSettingsScreen(),
            ),
          );
          _loadChannel();
        },
        child: Builder(builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return Semantics(
            label: '$_channel build channel active. Select to manage.',
            button: true,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: s(12),
                vertical: s(6),
              ),
              decoration: BoxDecoration(
                color: focused
                    ? Colors.white
                    : badgeColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(s(16)),
                border: Border.all(
                  color: focused
                      ? Colors.white
                      : badgeColor.withValues(alpha: 0.5),
                  width: s(1.2),
                ),
                boxShadow: focused
                    ? DashboardDecorations.focusGlow(context,
                        color: badgeColor, strength: 0.8)
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isBeta ? Icons.science_rounded : Icons.developer_mode_rounded,
                    size: s(14),
                    color: focused ? Colors.black : badgeColor,
                  ),
                  SizedBox(width: s(6)),
                  Text(
                    _channel.toUpperCase(),
                    style: TextStyle(
                      color: focused ? Colors.black : badgeColor,
                      fontSize: s(12),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
