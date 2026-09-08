import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:reelriot_tv/constants.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import 'package:reelriot_tv/utils/quality_utils.dart';
import 'package:reelriot_tv/widgets/long_press_focus.dart';

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
    this.showTitle = false,
    this.onKeyEvent,
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
  final bool showTitle;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;

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

  @override
  void didUpdateWidget(covariant PosterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaId != widget.mediaId ||
        oldWidget.isMovie != widget.isMovie ||
        oldWidget.releaseDate != widget.releaseDate ||
        oldWidget.quality != widget.quality) {
      _overrideQuality = null;
      _checkQualityOverride();
    }
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

        if (mounted && badge != null && badge != (_overrideQuality ?? widget.quality)) {
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
    final screenWidth = MediaQuery.of(context).size.width;
    double s(double v) => (v * screenWidth) / 1920;

    final cardWidth = s(140);
    final cardHeight = s(210); // 2:3 aspect ratio

    return LongPressFocus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) {
        if (focused) widget.onFocus?.call();
      },
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onKeyEvent: widget.onKeyEvent,
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.maybeOf(context)?.hasFocus ?? false;

          return Semantics(
            label: widget.title,
            button: true,
            child: AnimatedScale(
              scale: hasFocus ? 1.08 : 1.0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: SizedBox(
                width: cardWidth,
                height: widget.showTitle ? cardHeight + s(40) : cardHeight,
                child: RepaintBoundary(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Poster Art Container
                      Container(
                        width: cardWidth,
                        height: cardHeight,
                        decoration: BoxDecoration(
                          color: DashboardTheme.surface,
                          borderRadius: BorderRadius.circular(s(8)),
                          border: Border.all(
                            color: hasFocus
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.08),
                            width: hasFocus ? s(2.5) : s(1),
                          ),
                          boxShadow: hasFocus
                              ? DashboardDecorations.focusGlow(
                                  context,
                                  strength: 0.8,
                                )
                              : null,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(s(7)),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (_imageUrl.isNotEmpty)
                                CachedNetworkImage(
                                  imageUrl: _imageUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    color: DashboardTheme.surface,
                                  ),
                                  errorWidget: (context, url, error) => Center(
                                    child: Icon(
                                      Icons.movie_outlined,
                                      color: Colors.white24,
                                      size: s(40),
                                    ),
                                  ),
                                )
                              else
                                Container(color: DashboardTheme.surface),

                              // Sponsored badge
                              if (widget.isSponsored)
                                Positioned(
                                  top: s(10),
                                  left: s(10),
                                  child: _buildSponsoredBadge(s),
                                ),

                              // Quality badge
                              if ((_overrideQuality ?? widget.quality) !=
                                      null &&
                                  !widget.isSponsored)
                                Positioned(
                                  top: s(10),
                                  right: s(10),
                                  child: _buildQualityBadge(
                                    s,
                                    _overrideQuality ?? widget.quality!,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                      // Optional Title row (used only when showTitle is true)
                      if (widget.showTitle) ...[
                        SizedBox(height: s(10)),
                        Text(
                          widget.title,
                          style: TextStyle(
                            color: hasFocus ? Colors.white : Colors.white70,
                            fontSize: s(20),
                            fontWeight: hasFocus
                                ? FontWeight.bold
                                : FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.subtitle != null) ...[
                          SizedBox(height: s(2)),
                          Text(
                            widget.subtitle!,
                            style: TextStyle(
                              color: hasFocus
                                  ? Colors.white70
                                  : Colors.white38,
                              fontSize: s(16),
                              fontWeight: FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSponsoredBadge(double Function(double) s) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(s(6)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: s(8), sigmaY: s(8)),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: s(8), vertical: s(3)),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(s(6)),
            border: Border.all(color: DashboardTheme.divider),
          ),
          child: Text(
            'SPONSORED',
            style: TextStyle(
              color: Colors.white,
              fontSize: s(12),
              fontWeight: FontWeight.w800,
              letterSpacing: s(0.8),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQualityBadge(double Function(double) s, String quality) {
    Color bgColor = Colors.black.withValues(alpha: 0.8);
    Color borderColor = DashboardTheme.divider;
    final q = quality.toUpperCase();

    if (q == 'CAM') {
      bgColor = DashboardTheme.signalRed.withValues(alpha: 0.9);
      borderColor = DashboardTheme.signalRed.withValues(alpha: 0.5);
    } else if (q == 'SOON') {
      bgColor = DashboardTheme.warningAmber.withValues(alpha: 0.9);
      borderColor = DashboardTheme.warningAmber.withValues(alpha: 0.5);
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: s(8), vertical: s(3)),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(s(6)),
        border: Border.all(color: borderColor),
        boxShadow: q == 'CAM' || q == 'SOON'
            ? [
                BoxShadow(
                  color: bgColor.withValues(alpha: 0.3),
                  blurRadius: s(6),
                  spreadRadius: s(1),
                ),
              ]
            : null,
      ),
      child: Text(
        q,
        style: TextStyle(
          color: Colors.white,
          fontSize: s(12),
          fontWeight: FontWeight.w800,
          letterSpacing: s(0.5),
        ),
      ),
    );
  }
}
