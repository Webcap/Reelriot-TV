import 'package:reelriot_tv/constants.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:reelriot_tv/widgets/long_press_focus.dart';
import 'package:reelriot_tv/utils/quality_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    required this.posterPath,
    required this.title,
    this.subtitle,
    this.onTap,
    this.onLongPress,
    this.onFocus,
    this.focusNode,
    this.isSponsored = false,
    this.quality,
    this.mediaId,
    this.isMovie,
    this.releaseDate,
  });

  final String? posterPath;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onFocus;
  final FocusNode? focusNode;
  final bool isSponsored;
  final String? quality;
  final int? mediaId;
  final bool? isMovie;
  final String? releaseDate;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  String? _overrideQuality;

  @override
  void initState() {
    super.initState();
    _checkQualityOverride();
  }

  Future<void> _checkQualityOverride() async {
    // Only check if we have the necessary info and it's not already a fixed quality
    // We only care about movies as TV shows are HD by default
    if (widget.mediaId != null && widget.isMovie == true) {
      try {
        final badge = await QualityUtils.getQualityBadgeAsync(
          mediaId: widget.mediaId!,
          releaseDate: widget.releaseDate,
          isMovie: true,
        );
        
        if (badge != null && badge != widget.quality && mounted) {
          setState(() {
            _overrideQuality = badge;
          });
        }
      } catch (e) {
        // Silent fail for overrides
      }
    }
  }

  String get _imageUrl {
    if (widget.posterPath == null || widget.posterPath!.isEmpty) return '';
    if (widget.isSponsored) return widget.posterPath!; // Direct URL for ads
    return '$tmdbImageBaseUrl/w500${widget.posterPath}';
  }

  @override
  Widget build(BuildContext context) {
    // Read once at the top of build
    final screenWidth = MediaQuery.of(context).size.width;
    double s(double v) => (v * screenWidth) / 1920;

    return LongPressFocus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) {
        if (focused) widget.onFocus?.call();
      },
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.maybeOf(context)?.hasFocus ?? false;
          final cardWidth = s(220); // design.json lg poster width
          final cardHeight = s(330); // 1.5 ratio

          return AnimatedScale(
            scale: hasFocus ? 1.05 : 1.0, // 1.05x focus scaling
            duration: const Duration(milliseconds: 200),
            child: Container(
              width: cardWidth,
              height: cardHeight,
              margin: EdgeInsets.only(right: s(24)),
                child: RepaintBoundary(
                  child: Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(s(20)), // rounded-xl
                              child: Container(
                                width: cardWidth,
                                decoration: BoxDecoration(
                                  color: Colors.grey[900],
                                  border: Border.all(
                                    color: hasFocus ? Colors.white : Colors.transparent,
                                    width: s(4), // 4px focus ring
                                  ),
                                  boxShadow: hasFocus ? [
                                    BoxShadow(
                                      color: const Color(0xFFEC1D24).withValues(alpha: 0.45),
                                      blurRadius: s(28),
                                      spreadRadius: s(3),
                                    )
                                  ] : null,
                                ),
                                child: _imageUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: _imageUrl,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(color: Colors.grey[900]),
                                      errorWidget: (context, url, error) => const Icon(Icons.error),
                                    )
                                  : Container(color: Colors.grey[900]),
                              ),
                            ),
                          ),
                          SizedBox(height: s(12)),
                          Text(
                            widget.title,
                            style: TextStyle(
                              color: hasFocus ? Colors.white : Colors.white70,
                              fontSize: s(24),
                              fontWeight: hasFocus ? FontWeight.bold : FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (widget.subtitle != null) ...[
                            SizedBox(height: s(4)),
                            Text(
                              widget.subtitle!,
                              style: TextStyle(
                                color: hasFocus ? Colors.white70 : Colors.white38,
                                fontSize: s(18),
                                fontWeight: FontWeight.w400,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                      if (widget.isSponsored)
                        Positioned(
                          top: s(12),
                          left: s(12),
                          child: _buildSponsoredBadge(),
                        ),
                      if ((_overrideQuality ?? widget.quality) != null && !widget.isSponsored)
                        Positioned(
                          top: s(12),
                          right: s(12),
                          child: _buildQualityBadge(_overrideQuality ?? widget.quality!),
                        ),
                    ],
                  ),
                ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSponsoredBadge() {
    final screenWidth = MediaQuery.of(context).size.width;
    double s(double v) => (v * screenWidth) / 1920;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: s(12), vertical: s(4)),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(s(8)),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        'SPONSORED',
        style: TextStyle(
          color: Colors.white,
          fontSize: s(14),
          fontWeight: FontWeight.w900,
          letterSpacing: s(1),
        ),
      ),
    );
  }

  Widget _buildQualityBadge(String quality) {
    final screenWidth = MediaQuery.of(context).size.width;
    double s(double v) => (v * screenWidth) / 1920;

    Color bgColor = Colors.black.withValues(alpha: 0.75);
    Color borderColor = Colors.white24;
    final q = quality.toUpperCase();

    if (q == 'CAM') {
      bgColor = const Color(0xFFE60000).withValues(alpha: 0.9);
      borderColor = Colors.redAccent.withValues(alpha: 0.5);
    } else if (q == 'SOON') {
      bgColor = Colors.amber.withValues(alpha: 0.9);
      borderColor = Colors.amberAccent.withValues(alpha: 0.5);
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: s(10), vertical: s(4)),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(s(8)),
        border: Border.all(color: borderColor),
        boxShadow: q == 'CAM' || q == 'SOON'
            ? [
                BoxShadow(
                  color: bgColor.withValues(alpha: 0.3),
                  blurRadius: s(8),
                  spreadRadius: s(1),
                )
              ]
            : null,
      ),
      child: Text(
        q,
        style: TextStyle(
          color: Colors.white,
          fontSize: s(14),
          fontWeight: FontWeight.w900,
          letterSpacing: s(0.5),
        ),
      ),
    );
  }
}
