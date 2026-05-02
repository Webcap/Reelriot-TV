import 'package:caffeine_core/caffeine_core.dart';
import 'package:reelriot_tv/utils/responsive_utils.dart';
import 'package:reelriot_tv/widgets/poster_card.dart';
import 'package:reelriot_tv/utils/quality_utils.dart';
import 'package:flutter/material.dart';
import 'package:reelriot_tv/widgets/native_ad_poster_card.dart' as native;
import '../../models/ad.dart' as model;

class HomeMediaRow extends StatelessWidget {
  final String title;
  final List<MovieListItem>? items;
  final Function(int id) onFocus;
  final Function(MovieListItem item) onTap;
  final Function(MovieListItem item) onLongPress;

  final bool isSocial;

  const HomeMediaRow({
    super.key,
    required this.title,
    required this.items,
    required this.onFocus,
    required this.onTap,
    required this.onLongPress,
    this.isSocial = false,
  });

  @override
  Widget build(BuildContext context) {
    if (items == null || items!.isEmpty) return const SizedBox.shrink();
    double s(double v) => ResponsiveUtils.scale(context, v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: s(48),
                fontWeight: FontWeight.w800,
              ),
            ),
            if (isSocial) ...[
              SizedBox(width: s(24)),
              Icon(Icons.trending_up, color: const Color(0xFFE60000), size: s(48)),
            ],
          ],
        ),
        SizedBox(height: s(42)),
        SizedBox(
          height: s(480),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            primary: false,
            itemCount: items!.length,
            itemBuilder: (context, index) {
              final m = items![index];
              return Padding(
                padding: EdgeInsets.only(right: s(36)),
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
                    )
                  : PosterCard(
                      posterPath: m.posterPath,
                      title: m.title ?? '',
                      isSponsored: m.isSponsored,
                      onFocus: () => onFocus(m.id),
                      onLongPress: () => onLongPress(m),
                      onTap: () => onTap(m),
                      quality: QualityUtils.getQualityBadgeSync(
                        releaseDate: m.releaseDate,
                        isMovie: m.mediaType != 'tv',
                      ),
                      mediaId: m.id,
                      isMovie: m.mediaType != 'tv',
                      releaseDate: m.releaseDate,
                    ),
              );
            },
          ),
        ),
      ],
    );
  }
}
