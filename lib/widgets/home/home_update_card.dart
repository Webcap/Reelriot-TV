import 'package:reelriot_tv/services/update_service.dart';
import 'package:reelriot_tv/screens/update_screen.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HomeUpdateCard extends StatelessWidget {
  final UpdateInfo updateInfo;

  const HomeUpdateCard({super.key, required this.updateInfo});

  @override
  Widget build(BuildContext context) {
    if (!updateInfo.isUpdateAvailable) {
      return const SizedBox.shrink();
    }

    double s(double v) => ResponsiveUtils.scale(context, v);

    return Column(
      children: [
        SizedBox(height: s(48)),
        Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent && TvKeys.isSelect(event.logicalKey)) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UpdateScreen(updateInfo: updateInfo),
                ),
              );
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Builder(
            builder: (context) {
              final focused = Focus.of(context).hasFocus;
              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UpdateScreen(updateInfo: updateInfo),
                    ),
                  );
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: EdgeInsets.all(s(24)),
                  decoration: BoxDecoration(
                    color: focused
                        ? DashboardTheme.surfaceRaised
                        : DashboardTheme.surface,
                    borderRadius: BorderRadius.circular(s(14)),
                    boxShadow: focused
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: s(20),
                              offset: Offset(0, s(10)),
                            ),
                            BoxShadow(
                              color: DashboardTheme.warningAmber.withValues(
                                alpha: 0.3,
                              ),
                              blurRadius: s(24),
                              spreadRadius: s(1),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(s(12)),
                        decoration: BoxDecoration(
                          color: DashboardTheme.warningAmber.withValues(
                            alpha: focused ? 0.2 : 0.1,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.system_update_alt,
                          color: DashboardTheme.warningAmber,
                          size: s(32),
                        ),
                      ),
                      SizedBox(width: s(24)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              updateInfo.isForced
                                  ? 'Mandatory Update Required'
                                  : 'New Update Available',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: s(26),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Version ${updateInfo.latestVersion} is now available with new features and improvements.',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: s(18),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: s(24)),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: s(20),
                          vertical: s(10),
                        ),
                        decoration: BoxDecoration(
                          color: DashboardTheme.signalRed,
                          borderRadius: BorderRadius.circular(s(8)),
                        ),
                        child: Text(
                          'Update Now',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: s(18),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
