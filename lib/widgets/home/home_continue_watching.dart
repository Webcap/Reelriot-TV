import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/utils/quality_utils.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'package:reelriot_tv/widgets/poster_card.dart';

class HomeContinueWatchingRow extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  final Function(int id, bool isMovie) onFocus;
  final Function() onClearAll;
  final Function(Map<String, dynamic> item) onTap;
  final Function(Map<String, dynamic> item) onLongPress;
  final int index;
  final VoidCallback? onMoveUp;

  const HomeContinueWatchingRow({
    super.key,
    required this.history,
    required this.onFocus,
    required this.onClearAll,
    required this.onTap,
    required this.onLongPress,
    this.index = 1,
    this.onMoveUp,
  });

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) return const SizedBox.shrink();
    double s(double v) => ResponsiveUtils.scale(context, v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'CONTINUE WATCHING',
              style: DashboardTheme.sectionTitle(context),
            ),
            Focus(
              onKeyEvent: (node, event) {
                if (onMoveUp != null &&
                    event is KeyDownEvent &&
                    TvKeys.isUp(event.logicalKey)) {
                  onMoveUp!();
                  return KeyEventResult.handled;
                }
                if (event is KeyDownEvent && TvKeys.isSelect(event.logicalKey)) {
                  onClearAll();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Builder(
                builder: (context) {
                  final focused = Focus.of(context).hasFocus;
                  return Semantics(
                    label: 'Clear continue watching history',
                    button: true,
                    child: GestureDetector(
                      onTap: onClearAll,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: EdgeInsets.symmetric(
                          horizontal: s(12),
                          vertical: s(6),
                        ),
                        decoration: BoxDecoration(
                          color: focused
                              ? Colors.white.withValues(alpha: 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(s(6)),
                          border: Border.all(
                            color: focused ? Colors.white : Colors.white24,
                            width: s(1),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.delete_outline_rounded,
                              color: focused ? Colors.white : Colors.white70,
                              size: s(16),
                            ),
                            SizedBox(width: s(6)),
                            Text(
                              'CLEAR ALL',
                              style: TextStyle(
                                color: focused ? Colors.white : Colors.white70,
                                fontSize: s(12),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        SizedBox(height: s(12)),
        SizedBox(
          height: s(245),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            primary: false,
            clipBehavior: Clip.none,
            itemCount: history.length,
            itemBuilder: (context, index) {
              final h = history[index];
              final isMovie = h['type'] == 'movie';
              final mediaId = h['media_id'] as int;

              KeyEventResult handleCardKey(FocusNode node, KeyEvent event) {
                if (onMoveUp != null &&
                    event is KeyDownEvent &&
                    TvKeys.isUp(event.logicalKey)) {
                  onMoveUp!();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              }

              return Padding(
                padding: EdgeInsets.only(right: s(16)),
                child: PosterCard(
                  posterPath: h['poster_path'],
                  title: h['title'] ?? '',
                  onFocus: () => onFocus(mediaId, isMovie),
                  onLongPress: () => onLongPress(h),
                  onTap: () => onTap(h),
                  quality: QualityUtils.getQualityBadgeSync(
                    releaseDate: h['release_date'] as String?,
                    isMovie: isMovie,
                  ),
                  mediaId: mediaId,
                  isMovie: isMovie,
                  releaseDate: h['release_date'] as String?,
                  showTitle: false,
                  onKeyEvent: onMoveUp != null ? handleCardKey : null,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
