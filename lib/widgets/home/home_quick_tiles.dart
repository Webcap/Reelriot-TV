import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/widgets/long_press_focus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A compact landscape tile for the dashboard's side column — used for
/// "keep watching," "up next," and "live now" — everything that isn't the
/// single biggest spotlight tile but still deserves to be seen without
/// scrolling.
class HomeQuickTile extends StatelessWidget {
  final String? imageUrl;
  final String title;
  final String? subtitle;
  final String badgeLabel;
  final Color badgeColor;
  final double? progress;
  final IconData? leadingIcon;
  final VoidCallback? onTap;
  final VoidCallback? onFocus;
  final VoidCallback? onLongPress;
  final FocusNode? focusNode;

  const HomeQuickTile({
    super.key,
    required this.imageUrl,
    required this.title,
    this.subtitle,
    required this.badgeLabel,
    required this.badgeColor,
    this.progress,
    this.leadingIcon,
    this.onTap,
    this.onFocus,
    this.onLongPress,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);

    return LongPressFocus(
      focusNode: focusNode,
      onFocusChange: (focused) {
        if (focused) onFocus?.call();
      },
      onTap: onTap,
      onLongPress: onLongPress,
      child: Builder(
        builder: (context) {
          final focused = Focus.maybeOf(context)?.hasFocus ?? false;
          return AnimatedScale(
            scale: focused ? 1.03 : 1.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: Container(
              padding: EdgeInsets.all(s(14)),
              decoration: BoxDecoration(
                color: focused
                    ? DashboardTheme.surfaceRaised
                    : DashboardTheme.surface,
                borderRadius: BorderRadius.circular(s(16)),
                boxShadow: focused
                    ? DashboardDecorations.focusGlow(context, strength: 0.6)
                    : null,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(s(10)),
                        child: SizedBox(
                          width: s(96),
                          height: s(96),
                          child:
                              (imageUrl != null && imageUrl!.isNotEmpty)
                              ? CachedNetworkImage(
                                  imageUrl: imageUrl!,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) =>
                                      Container(color: DashboardTheme.surface),
                                )
                              : Container(
                                  color: DashboardTheme.surface,
                                  child: leadingIcon != null
                                      ? Icon(
                                          leadingIcon,
                                          color: Colors.white38,
                                          size: s(32),
                                        )
                                      : null,
                                ),
                        ),
                      ),
                      if (progress != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: ClipRRect(
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(s(10)),
                              bottomRight: Radius.circular(s(10)),
                            ),
                            child: Container(
                              height: s(4),
                              color: Colors.black45,
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: progress!.clamp(0.0, 1.0),
                                child: Container(
                                  color: DashboardTheme.signalRed,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(width: s(16)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: s(8),
                            vertical: s(2),
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(s(4)),
                          ),
                          child: Text(
                            badgeLabel,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: s(11),
                              fontWeight: FontWeight.bold,
                              letterSpacing: s(0.4),
                            ),
                          ),
                        ),
                        SizedBox(height: s(8)),
                        Text(
                          title,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: s(19),
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null) ...[
                          SizedBox(height: s(4)),
                          Text(
                            subtitle!,
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: s(14),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
