import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reelriot_tv/services/profile_service.dart';
import 'package:reelriot_tv/services/settings_service.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';

/// Cinematic Top Navigation Bar.
///
/// Floats transparently over the full-bleed hero backdrop when on the Home tab,
/// smoothly transitioning to solid black upon downward scrolling.
///
/// Features:
/// - Left: Reelriot TV Brand Logo
/// - Center-left: Text category labels (HOME, MOVIES, SERIES, SPORTS)
///   with thin Signal Red active underline indicator.
/// - Right: Frosted icon buttons for Search, Favorites, and Profile.
class HomeTopBar extends StatelessWidget {
  final double scrollOffset;
  final bool isHomeTab;
  final String selectedCategory; // 'Home', 'Movies', 'TV Shows'
  final int selectedTabIndex;
  final List<FocusNode> navNodes;
  final ValueChanged<String> onCategorySelected;
  final ValueChanged<int> onTabSelected;
  final ValueChanged<int> onTabReset;
  final VoidCallback? onMoveIntoContent;

  const HomeTopBar({
    super.key,
    this.scrollOffset = 0.0,
    required this.isHomeTab,
    required this.selectedCategory,
    required this.selectedTabIndex,
    required this.navNodes,
    required this.onCategorySelected,
    required this.onTabSelected,
    required this.onTabReset,
    this.onMoveIntoContent,
  });

  @override
  Widget build(BuildContext context) {
    double s(double v) => ResponsiveUtils.scale(context, v);

    final sportsEnabled = SettingsService().sportsEnabled;

    // Calculate dynamic background color and opacity
    final double scrollProgress = (scrollOffset / 180.0).clamp(0.0, 1.0);
    final Color bgColor = isHomeTab
        ? DashboardTheme.canvasBlack.withValues(alpha: scrollProgress * 0.95)
        : DashboardTheme.canvasBlack;

    // Build the list of category items
    final List<Map<String, dynamic>> categoryItems = [
      {'key': 'Home', 'label': 'HOME'},
      {'key': 'Movies', 'label': 'MOVIES'},
      {'key': 'TV Shows', 'label': 'SERIES'},
      if (sportsEnabled) {'key': 'Sports', 'label': 'SPORTS'},
    ];

    // Right action icons
    final List<Map<String, dynamic>> actionItems = [
      {
        'key': 'search',
        'label': 'Search',
        'icon': Icons.search_rounded,
        'tabIndex': 0,
      },
      {
        'key': 'favorites',
        'label': 'Favorites',
        'icon': Icons.favorite_border_rounded,
        'tabIndex': sportsEnabled ? 4 : 3,
      },
      {
        'key': 'profile',
        'label': 'Profile',
        'icon': Icons.person_outline_rounded,
        'tabIndex': sportsEnabled ? 3 : 2,
      },
    ];

    final int totalItems = categoryItems.length + actionItems.length;

    return Container(
      height: s(DashboardTheme.topNavHeight),
      decoration: BoxDecoration(
        color: bgColor,
        gradient: (isHomeTab && scrollProgress < 0.9)
            ? DashboardTheme.topNavScrim
            : null,
        border: Border(
          bottom: BorderSide(
            color: scrollProgress > 0.8
                ? DashboardTheme.divider
                : Colors.transparent,
            width: s(1),
          ),
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: s(56)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Reelriot TV Logo
          Container(
            width: s(54),
            height: s(54),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(s(12)),
              boxShadow: [
                BoxShadow(
                  color: DashboardTheme.signalRed.withValues(alpha: 0.3),
                  blurRadius: s(16),
                  spreadRadius: s(1.5),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(s(12)),
              child: Image.asset(
                'assets/images/ReelriotTVLogo.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          SizedBox(width: s(40)),

          // Categories (HOME, MOVIES, SERIES, SPORTS)
          Expanded(
            child: Row(
              children: List.generate(categoryItems.length, (i) {
                final cat = categoryItems[i];
                final catKey = cat['key'] as String;
                final catLabel = cat['label'] as String;

                final bool isSelected;
                if (catKey == 'Sports') {
                  isSelected = selectedTabIndex == 2;
                } else {
                  isSelected = isHomeTab &&
                      (selectedCategory == catKey ||
                          (catKey == 'Home' && selectedCategory == 'Home'));
                }

                final node = i < navNodes.length ? navNodes[i] : FocusNode();

                return Padding(
                  padding: EdgeInsets.only(right: s(28)),
                  child: Focus(
                    focusNode: node,
                    onKeyEvent: (node, event) {
                      if (event is! KeyDownEvent) return KeyEventResult.ignored;
                      final key = event.logicalKey;

                      if (TvKeys.isSelect(key)) {
                        if (catKey == 'Sports') {
                          onTabSelected(2);
                        } else {
                          onCategorySelected(catKey);
                          if (!isHomeTab) {
                            onTabSelected(1);
                          } else if (isSelected) {
                            onTabReset(1);
                          }
                        }
                        return KeyEventResult.handled;
                      }

                      if (TvKeys.isRight(key)) {
                        if (i < totalItems - 1) {
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

                      if (TvKeys.isDown(key)) {
                        if (onMoveIntoContent != null) {
                          onMoveIntoContent!();
                        } else {
                          FocusScope.of(context)
                              .focusInDirection(TraversalDirection.down);
                        }
                        return KeyEventResult.handled;
                      }

                      return KeyEventResult.ignored;
                    },
                    child: Builder(
                      builder: (context) {
                        final focused = Focus.of(context).hasFocus;
                        return Semantics(
                          label: catLabel,
                          button: true,
                          selected: isSelected,
                          child: GestureDetector(
                            onTap: () {
                              if (catKey == 'Sports') {
                                onTabSelected(2);
                              } else {
                                onCategorySelected(catKey);
                                if (!isHomeTab) onTabSelected(1);
                              }
                            },
                            child: AnimatedScale(
                              scale: focused ? 1.06 : 1.0,
                              duration: const Duration(milliseconds: 150),
                              curve: Curves.easeOutCubic,
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: s(16),
                                  vertical: s(10),
                                ),
                                decoration: BoxDecoration(
                                  color: focused
                                      ? Colors.white.withValues(alpha: 0.15)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(s(10)),
                                  border: Border.all(
                                    color: focused
                                        ? Colors.white.withValues(alpha: 0.4)
                                        : Colors.transparent,
                                    width: s(1.5),
                                  ),
                                  boxShadow: focused
                                      ? DashboardDecorations.focusGlow(
                                          context,
                                          strength: 0.5,
                                        )
                                      : null,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      catLabel,
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : (focused
                                                ? Colors.white
                                                : Colors.white60),
                                        fontSize: s(20),
                                        fontWeight: isSelected
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        letterSpacing: 1.4,
                                      ),
                                    ),
                                    SizedBox(height: s(6)),
                                    // Underline indicator
                                    AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      height: s(3),
                                      width: isSelected ? s(32) : 0,
                                      decoration: BoxDecoration(
                                        color: DashboardTheme.signalRed,
                                        borderRadius:
                                            BorderRadius.circular(s(2)),
                                        boxShadow: isSelected
                                            ? [
                                                BoxShadow(
                                                  color: DashboardTheme
                                                      .signalRed
                                                      .withValues(alpha: 0.8),
                                                  blurRadius: s(8),
                                                ),
                                              ]
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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

          // Right Action Icons (Search, Favorites, Profile)
          Row(
            children: List.generate(actionItems.length, (j) {
              final action = actionItems[j];
              final nodeIndex = categoryItems.length + j;
              final node = nodeIndex < navNodes.length
                  ? navNodes[nodeIndex]
                  : FocusNode();
              final tabIndex = action['tabIndex'] as int;
              final isSelected = selectedTabIndex == tabIndex;
              final icon = action['icon'] as IconData;
              final label = action['label'] as String;

              return Padding(
                padding: EdgeInsets.only(left: s(14)),
                child: Focus(
                  focusNode: node,
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent) return KeyEventResult.ignored;
                    final key = event.logicalKey;

                    if (TvKeys.isSelect(key)) {
                      if (selectedTabIndex == tabIndex) {
                        onTabReset(tabIndex);
                      } else {
                        onTabSelected(tabIndex);
                      }
                      return KeyEventResult.handled;
                    }

                    if (TvKeys.isRight(key)) {
                      if (nodeIndex < totalItems - 1) {
                        navNodes[nodeIndex + 1].requestFocus();
                        return KeyEventResult.handled;
                      }
                    }

                    if (TvKeys.isLeft(key)) {
                      if (nodeIndex > 0) {
                        navNodes[nodeIndex - 1].requestFocus();
                        return KeyEventResult.handled;
                      }
                    }

                    if (TvKeys.isDown(key)) {
                      if (onMoveIntoContent != null) {
                        onMoveIntoContent!();
                      } else {
                        FocusScope.of(context)
                            .focusInDirection(TraversalDirection.down);
                      }
                      return KeyEventResult.handled;
                    }

                    return KeyEventResult.ignored;
                  },
                  child: Builder(
                    builder: (context) {
                      final focused = Focus.of(context).hasFocus;
                      final isProfile = action['key'] == 'profile';

                      Widget buildButtonContent({
                        required bool showAvatar,
                        String? avatarUrl,
                        String? effectiveLabel,
                      }) {
                        return Semantics(
                          label: effectiveLabel ?? label,
                          button: true,
                          selected: isSelected,
                          child: GestureDetector(
                            onTap: () {
                              if (selectedTabIndex == tabIndex) {
                                onTabReset(tabIndex);
                              } else {
                                onTabSelected(tabIndex);
                              }
                            },
                            child: AnimatedScale(
                              scale: focused ? 1.12 : 1.0,
                              duration: const Duration(milliseconds: 150),
                              curve: Curves.easeOutCubic,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: s(48),
                                height: s(48),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected
                                      ? DashboardTheme.signalRed
                                      : (focused
                                          ? Colors.white.withValues(alpha: 0.22)
                                          : Colors.white.withValues(alpha: 0.08)),
                                  border: Border.all(
                                    color: focused
                                        ? Colors.white
                                        : (isSelected
                                            ? DashboardTheme.signalRed
                                            : (showAvatar
                                                ? Colors.white.withValues(alpha: 0.35)
                                                : Colors.white.withValues(alpha: 0.15))),
                                    width: focused ? s(2.5) : (isSelected ? s(2) : s(1.5)),
                                  ),
                                  boxShadow: focused
                                      ? DashboardDecorations.focusGlow(
                                          context,
                                          strength: 0.7,
                                        )
                                      : (isSelected && showAvatar
                                          ? [
                                              BoxShadow(
                                                color: DashboardTheme.signalRed.withValues(alpha: 0.6),
                                                blurRadius: s(8),
                                                spreadRadius: s(1),
                                              ),
                                            ]
                                          : null),
                                ),
                                child: showAvatar && avatarUrl != null
                                    ? ClipOval(
                                        child: CachedNetworkImage(
                                          imageUrl: avatarUrl,
                                          width: s(48),
                                          height: s(48),
                                          fit: BoxFit.cover,
                                          memCacheWidth: 96,
                                          memCacheHeight: 96,
                                          placeholder: (context, url) => Container(
                                            color: Colors.white.withValues(alpha: 0.08),
                                            child: Center(
                                              child: Icon(
                                                Icons.person_outline_rounded,
                                                color: Colors.white54,
                                                size: s(24),
                                              ),
                                            ),
                                          ),
                                          errorWidget: (context, url, error) => Container(
                                            color: Colors.white.withValues(alpha: 0.08),
                                            child: Center(
                                              child: Icon(
                                                Icons.person_outline_rounded,
                                                color: Colors.white,
                                                size: s(24),
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                    : Center(
                                        child: Icon(
                                          icon,
                                          color: Colors.white,
                                          size: s(24),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        );
                      }

                      if (isProfile) {
                        return ListenableBuilder(
                          listenable: ProfileService(),
                          builder: (context, _) {
                            final profile = ProfileService();
                            final bool showAvatar = profile.isSignedIn && profile.avatarUrl != null;
                            final avatarUrl = profile.avatarUrl;
                            final username = profile.username;
                            final effectiveLabel = (username != null && username.isNotEmpty)
                                ? 'Profile (@$username)'
                                : label;

                            return buildButtonContent(
                              showAvatar: showAvatar,
                              avatarUrl: avatarUrl,
                              effectiveLabel: effectiveLabel,
                            );
                          },
                        );
                      }

                      return buildButtonContent(showAvatar: false);
                    },
                  ),
                ),
              );
            }),
          ),

          // Offline indicator
          if (SettingsService().isOffline)
            Padding(
              padding: EdgeInsets.only(left: s(16)),
              child: Tooltip(
                message: 'Offline Mode',
                child: Container(
                  width: s(44),
                  height: s(44),
                  decoration: BoxDecoration(
                    color: DashboardTheme.signalRed.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: DashboardTheme.signalRed.withValues(alpha: 0.4),
                      width: s(1),
                    ),
                  ),
                  child: Icon(
                    Icons.cloud_off_rounded,
                    color: DashboardTheme.signalRed,
                    size: s(22),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
