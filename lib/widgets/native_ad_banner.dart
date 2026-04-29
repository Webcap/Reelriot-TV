import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:reelriot_tv/widgets/long_press_focus.dart';
import '../models/ad.dart';

class NativeAdBanner extends StatelessWidget {
  final Ad ad;

  const NativeAdBanner({
    super.key,
    required this.ad,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    double s(double v) => (v * screenWidth) / 1920;

    return LongPressFocus(
      onTap: () async {
        final url = Uri.parse(ad.link);
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.maybeOf(context)?.hasFocus ?? false;

          return AnimatedScale(
            scale: hasFocus ? 1.02 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              width: double.infinity,
              margin: EdgeInsets.symmetric(horizontal: s(64), vertical: s(32)),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(s(24)),
                border: Border.all(
                  color: hasFocus ? Colors.white : Colors.white10,
                  width: s(4),
                ),
                boxShadow: hasFocus ? [
                  BoxShadow(
                    color: const Color(0xFFDC2626).withValues(alpha: 0.3),
                    blurRadius: s(40),
                    spreadRadius: s(5),
                  )
                ] : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: AspectRatio(
                aspectRatio: 32 / 9,
                child: Stack(
                  children: [
                    _buildImage(),
                    _buildOverlay(),
                    _buildContent(s),
                    _buildBadge(s),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildImage() {
    Widget image;
    if (ad.imageUrl.startsWith('http')) {
      image = CachedNetworkImage(
        imageUrl: ad.imageUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(color: Colors.grey[900]),
        errorWidget: (context, url, error) => const Icon(Icons.error),
      );
    } else {
      image = Image.asset(
        ad.imageUrl.replaceFirst('/', ''),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(color: Colors.grey[900]),
      );
    }
    return Positioned.fill(child: image);
  }

  Widget _buildOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.black.withValues(alpha: 0.9),
              Colors.black.withValues(alpha: 0.5),
              Colors.transparent,
            ],
            stops: const [0.0, 0.4, 0.8],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(double Function(double) s) {
    return Positioned.fill(
      child: Padding(
        padding: EdgeInsets.all(s(48)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ad.title,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: s(48),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: s(12)),
            SizedBox(
              width: s(800),
              child: Text(
                ad.description,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: s(24),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(height: s(32)),
            _buildCTA(s),
          ],
        ),
      ),
    );
  }

  Widget _buildCTA(double Function(double) s) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: s(32), vertical: s(16)),
      decoration: BoxDecoration(
        color: const Color(0xFFDC2626),
        borderRadius: BorderRadius.circular(s(12)),
      ),
      child: Text(
        ad.cta,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: s(20),
        ),
      ),
    );
  }

  Widget _buildBadge(double Function(double) s) {
    return Positioned(
      top: s(24),
      right: s(24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(s(8)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: s(16), vertical: s(8)),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Icon(Icons.verified_user, size: s(18), color: Colors.white70),
                SizedBox(width: s(8)),
                Text(
                  'SPONSORED',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: s(14),
                    fontWeight: FontWeight.w900,
                    letterSpacing: s(2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
