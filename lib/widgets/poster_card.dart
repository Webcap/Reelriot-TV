import 'package:caffeine_tv/constants.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:caffeine_tv/widgets/long_press_focus.dart';

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
  });

  final String? posterPath;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onFocus;
  final FocusNode? focusNode;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  String get _imageUrl {
    if (widget.posterPath == null || widget.posterPath!.isEmpty) return '';
    return '$tmdbImageBaseUrl/w500${widget.posterPath}';
  }

  @override
  Widget build(BuildContext context) {
    // Read once at the top of build
    final screenWidth = MediaQuery.of(context).size.width;
    final s = (double v) => (v * screenWidth) / 1920;

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
                  child: Column(
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
                ),
            ),
          );
        },
      ),
    );
  }
}
