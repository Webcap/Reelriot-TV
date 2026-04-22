import 'package:reelriot_tv/services/update_service.dart';
import 'package:reelriot_tv/screens/update_screen.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HomeUpdateCard extends StatelessWidget {
  final UpdateInfo updateInfo;

  const HomeUpdateCard({
    super.key,
    required this.updateInfo,
  });

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
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.select)) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => UpdateScreen(updateInfo: updateInfo)),
              );
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Builder(builder: (context) {
            final focused = Focus.of(context).hasFocus;
            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => UpdateScreen(updateInfo: updateInfo)),
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding: EdgeInsets.all(s(24)),
                decoration: BoxDecoration(
                  color: focused ? Colors.white : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(s(16)),
                  border: Border.all(
                    color: focused ? Colors.white : Colors.white12,
                    width: s(2),
                  ),
                  boxShadow: focused
                      ? [
                          BoxShadow(
                            color: Colors.amber.withValues(alpha: 0.3),
                            blurRadius: s(30),
                            spreadRadius: s(5),
                          )
                        ]
                      : [],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(s(12)),
                      decoration: BoxDecoration(
                        color: focused ? Colors.amber.withValues(alpha: 0.2) : Colors.amber.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.system_update_alt,
                        color: focused ? Colors.amber : Colors.amberAccent,
                        size: s(32),
                      ),
                    ),
                    SizedBox(width: s(24)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            updateInfo.isForced ? 'Mandatory Update Required' : 'New Update Available',
                            style: TextStyle(
                              color: focused ? Colors.black : Colors.white,
                              fontSize: s(26),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Version ${updateInfo.latestVersion} is now available with new features and improvements.',
                            style: TextStyle(
                              color: focused ? Colors.black87 : Colors.white60,
                              fontSize: s(18),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: s(24)),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: s(20), vertical: s(10)),
                      decoration: BoxDecoration(
                        color: focused ? Colors.black : Colors.white10,
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
          }),
        ),
      ],
    );
  }
}
