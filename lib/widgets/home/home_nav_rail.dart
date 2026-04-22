import 'package:reelriot_tv/services/settings_service.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HomeTab {
  final String label;
  final IconData icon;
  const HomeTab({required this.label, required this.icon});
}

class HomeNavRail extends StatelessWidget {
  final int selectedIndex;
  final List<FocusNode> navNodes;
  final List<HomeTab> tabs;
  final Function(int) onTabSelected;
  final Function(int) onTabReset;

  const HomeNavRail({
    super.key,
    required this.selectedIndex,
    required this.navNodes,
    required this.tabs,
    required this.onTabSelected,
    required this.onTabReset,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);

    return Container(
      width: s(128),
      color: const Color(0xFF111111),
      child: Column(
        children: [
          SizedBox(height: s(40)),
          // Logo placeholder
          Container(
            width: s(90),
            height: s(45),
            decoration: BoxDecoration(
              color: const Color(0xFFEC1D24), // Exact Marvel Brand Red
              borderRadius: BorderRadius.circular(s(4)),
            ),
            alignment: Alignment.center,
            child: Text(
              'REELRIOT',
              style: TextStyle(
                color: Colors.white,
                fontSize: s(16),
                fontWeight: FontWeight.w900,
                letterSpacing: s(1),
              ),
            ),
          ),
          SizedBox(height: s(60)),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: List.generate(tabs.length, (i) {
                  final tab = tabs[i];
                  final selected = selectedIndex == i;
                  return Focus(
                    autofocus: i == selectedIndex,
                    focusNode: navNodes[i],
                    onKeyEvent: (node, event) {
                      if (event is! KeyDownEvent) return KeyEventResult.ignored;
                      if (event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.select) {
                        if (selectedIndex == i) {
                          onTabReset(i);
                        } else {
                          onTabSelected(i);
                        }
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Builder(
                      builder: (context) {
                        final focused = Focus.of(context).hasFocus;
                        return Padding(
                          padding: EdgeInsets.symmetric(vertical: s(24)),
                          child: AnimatedScale(
                            scale: selected || focused ? 1.08 : 1.0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: s(85),
                              height: s(85),
                              decoration: BoxDecoration(
                                color: selected ? const Color(0xFF1F2937) : (focused ? Colors.white.withValues(alpha: 0.05) : Colors.transparent),
                                borderRadius: BorderRadius.circular(s(18)),
                                border: Border.all(
                                  color: focused ? Colors.white24 : Colors.transparent,
                                  width: s(2),
                                ),
                              ),
                              child: Icon(
                                tab.icon,
                                color: Colors.white,
                                size: s(42),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                }),
              ),
            ),
          ),
          if (SettingsService().isOffline)
            Padding(
              padding: EdgeInsets.only(bottom: s(24)),
              child: Tooltip(
                message: 'Offline Mode',
                child: Container(
                  width: s(54),
                  height: s(54),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEC1D24).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFEC1D24).withValues(alpha: 0.3), width: s(1)),
                  ),
                  child: Icon(
                    Icons.cloud_off_rounded,
                    color: const Color(0xFFEC1D24),
                    size: s(24),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
