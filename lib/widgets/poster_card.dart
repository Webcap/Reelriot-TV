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
    this.focusNode,
  });

  final String? posterPath;
  final String title;
  final VoidCallback? onTap;
  final FocusNode? focusNode;

  String get _imageUrl {
    if (posterPath == null || posterPath!.isEmpty) return '';
    return '$tmdbImageBaseUrl/w500$posterPath';
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
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
          return GestureDetector(
            onTap: onTap,
            child: AnimatedScale(
              scale: hasFocus ? 1.08 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: Container(
                width: 140,
                height: 230,
                margin: const EdgeInsets.only(right: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 140,
                          decoration: BoxDecoration(
                            color: Colors.grey[900],
                            border: Border.all(
                              color: hasFocus ? const Color(0xFFDC2626) : Colors.transparent,
                              width: 3,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: _imageUrl.isEmpty
                              ? const Center(child: Icon(Icons.movie, color: Colors.white38, size: 48))
                              : CachedNetworkImage(
                                  imageUrl: _imageUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                                  errorWidget: (context, url, error) => const Icon(Icons.broken_image, color: Colors.white38),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      maxLines: 2,
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
