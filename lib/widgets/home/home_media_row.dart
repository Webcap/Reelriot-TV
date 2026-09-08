import 'package:caffeine_core/caffeine_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/utils/quality_utils.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import 'package:reelriot_tv/widgets/native_ad_poster_card.dart' as native;
import 'package:reelriot_tv/widgets/poster_card.dart';
import '../../models/ad.dart' as model;

class HomeMediaRow extends StatelessWidget {
  final String title;
  final List<MovieListItem>? items;
  final Function(int id) onFocus;
  final Function(MovieListItem item) onTap;
  final Function(MovieListItem item) onLongPress;
  final int? index;
  final bool isSocial;
  final VoidCallback? onMoveUp;

  const HomeMediaRow({
    super.key,
    required this.title,
    required this.items,
    required this.onFocus,
    required this.onTap,
    required this.onLongPress,
    this.isSocial = false,
    this.index,
    this.onMoveUp,
  });

  @override
  Widget build(BuildContext context) {
    if (items == null || items!.isEmpty) return const SizedBox.shrink();
    double s(double v) => ResponsiveUtils.scale(context, v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Section Header
        Row(
          children: [
            Text(
              title.toUpperCase(),
              style: DashboardTheme.sectionTitle(context),
            ),
            if (isSocial) ...[
              SizedBox(width: s(12)),
              Icon(
                Icons.trending_up,
                color: DashboardTheme.signalRed,
                size: s(22),
              ),
            ],
          ],
        ),
        SizedBox(height: s(12)),

        // Horizontal Shelf Cards
        SizedBox(
          height: s(245),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            primary: false,
            clipBehavior: Clip.none,
            itemCount: items!.length,
            itemBuilder: (context, index) {
              final m = items![index];
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
                child: m.isSponsored
                    ? native.NativeAdPosterCard(
                        ad: model.Ad(
                          id: m.id.toString(),
                          title: m.title ?? '',
                          description: m.overview ?? '',
                          imageUrl: m.posterPath ?? '',
                          cta: 'Learn More',
                          link: 'https://reelriot.app',
                          placement: 'poster',
                        ),
                        onKeyEvent: onMoveUp != null ? handleCardKey : null,
                      )
                    : PosterCard(
                        posterPath: m.posterPath,
                        title: m.title ?? '',
                        isSponsored: m.isSponsored,
                        onFocus: () => onFocus(m.id),
                        onLongPress: () => onLongPress(m),
                        onTap: () => onTap(m),
                        quality: QualityUtils.getQualityBadgeSync(
                          mediaId: m.id,
                          releaseDate: m.releaseDate,
                          isMovie: m.mediaType != 'tv',
                        ),
                        mediaId: m.id,
                        isMovie: m.mediaType != 'tv',
                        releaseDate: m.releaseDate,
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
