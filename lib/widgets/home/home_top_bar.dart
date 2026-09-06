import 'package:reelriot_tv/services/settings_service.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HomeTab {
  final String label;
  final IconData icon;
  const HomeTab({required this.label, required this.icon});
}

/// Horizontal top bar — replaces the old persistent left icon rail. Moving
/// primary navigation to the top frees the full width for the dashboard
/// grid below and matches how a viewer's eye already lands on this surface
/// (top-left to top-right), rather than a strip of icons down the side.
class HomeTopBar extends StatelessWidget {
  final int selectedIndex;
  final List<FocusNode> navNodes;
  final List<HomeTab> tabs;
  final Function(int) onTabSelected;
  final Function(int) onTabReset;
  final VoidCallback? onMoveIntoContent;

  const HomeTopBar({
    super.key,
    required this.selectedIndex,
    required this.navNodes,
    required this.tabs,
    required this.onTabSelected,
    required this.onTabReset,
    this.onMoveIntoContent,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);

    return Container(
      height: s(120),
      color: DashboardTheme.surface,
      padding: EdgeInsets.symmetric(horizontal: s(48)),
      child: Row(
        children: [
          Container(
            width: s(56),
            height: s(56),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(s(14)),
              boxShadow: [
                BoxShadow(
                  color: DashboardTheme.signalRed.withValues(alpha: 0.18),
                  blurRadius: s(12),
                  spreadRadius: s(1),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(s(14)),
              child: Image.asset(
                'assets/images/ReelriotTVLogo.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          SizedBox(width: s(56)),
          Expanded(
            child: Row(
              children: List.generate(tabs.length, (i) {
                final tab = tabs[i];
                final selected = selectedIndex == i;
                return Padding(
                  padding: EdgeInsets.only(right: s(8)),
                  child: Focus(
                    autofocus: i == selectedIndex,
                    focusNode: navNodes[i],
                    onKeyEvent: (node, event) {
                      if (event is! KeyDownEvent) return KeyEventResult.ignored;

                      final key = event.logicalKey;

                      if (TvKeys.isSelect(key)) {
                        if (selectedIndex == i) {
                          onTabReset(i);
                        } else {
                          onTabSelected(i);
                        }
                        return KeyEventResult.handled;
                      }

                      // Horizontal navigation between tabs.
                      if (TvKeys.isRight(key)) {
                        if (i < navNodes.length - 1) {
                          navNodes[i + 1].requestFocus();
                          return KeyEventResult.handled;
                        }
                      }
                      if (TvKeys.isLeft(key)) {
                        if (i > 0) {
                          navNodes[i - 1].requestFocus();
                          return KeyEventResult.handled;
                        }
                      }

                      // Drop down into the dashboard below.
                      if (TvKeys.isDown(key)) {
                        if (onMoveIntoContent != null) {
                          onMoveIntoContent!();
                        } else {
                          FocusScope.of(
                            context,
                          ).focusInDirection(TraversalDirection.down);
                        }
                        return KeyEventResult.handled;
                      }

                      return KeyEventResult.ignored;
                    },
                    child: Builder(
                      builder: (context) {
                        final focused = Focus.of(context).hasFocus;
                        return AnimatedScale(
                          scale: focused ? 1.06 : 1.0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: EdgeInsets.symmetric(
                              horizontal: s(22),
                              vertical: s(14),
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? DashboardTheme.signalRed
                                  : (focused
                                        ? DashboardTheme.surfaceRaised
                                        : Colors.transparent),
                              borderRadius: BorderRadius.circular(s(12)),
                              boxShadow: focused
                                  ? DashboardDecorations.focusGlow(
                                      context,
                                      strength: 0.6,
                                    )
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  tab.icon,
                                  color: selected
                                      ? Colors.white
                                      : Colors.white70,
                                  size: s(26),
                                ),
                                SizedBox(width: s(12)),
                                Text(
                                  tab.label,
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : Colors.white70,
                                    fontSize: s(20),
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              }),
            ),
          ),
          if (SettingsService().isOffline)
            Padding(
              padding: EdgeInsets.only(left: s(16)),
              child: Tooltip(
                message: 'Offline Mode',
                child: Container(
                  width: s(44),
                  height: s(44),
                  decoration: BoxDecoration(
                    color: DashboardTheme.signalRed.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: DashboardTheme.signalRed.withValues(alpha: 0.3),
                      width: s(1),
                    ),
                  ),
                  child: Icon(
                    Icons.cloud_off_rounded,
                    color: DashboardTheme.signalRed,
                    size: s(20),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
