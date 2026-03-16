import 'package:caffeine_tv/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.posterPath,
    required this.title,
    this.onTap,
    this.onFocus,
    this.focusNode,
  });

  final String? posterPath;
  final String title;
  final VoidCallback? onTap;
  final VoidCallback? onFocus;
  final FocusNode? focusNode;

  String get _imageUrl {
    if (posterPath == null || posterPath!.isEmpty) return '';
    return '$tmdbImageBaseUrl/w500$posterPath';
  }

  double _scale(BuildContext context, double value) {
    final width = MediaQuery.of(context).size.width;
    return (value * width) / 1920;
  }

  @override
  Widget build(BuildContext context) {
    final s = (double v) => _scale(context, v);

    return Focus(
      focusNode: focusNode,
      onFocusChange: (focused) {
        if (focused) onFocus?.call();
      },
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select)) {
          onTap?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.maybeOf(context)?.hasFocus ?? false;
          final cardWidth = s(220); // design.json lg poster width
          final cardHeight = s(330); // 1.5 ratio

          return GestureDetector(
            onTap: onTap,
            child: AnimatedScale(
              scale: hasFocus ? 1.05 : 1.0, // 1.05x focus scaling
              duration: const Duration(milliseconds: 150),
              child: Container(
                width: cardWidth,
                height: cardHeight,
                margin: EdgeInsets.only(right: s(24)),
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
                                color: Colors.white.withOpacity(0.3),
                                blurRadius: s(25),
                                spreadRadius: s(2),
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
                      title,
                      style: TextStyle(
                        color: hasFocus ? Colors.white : Colors.white70,
                        fontSize: s(24),
                        fontWeight: hasFocus ? FontWeight.bold : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
}
