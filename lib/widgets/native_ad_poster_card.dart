import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:reelriot_tv/widgets/long_press_focus.dart';
import 'package:reelriot_tv/theme/dashboard_theme.dart';
import '../models/ad.dart';

class NativeAdPosterCard extends StatelessWidget {
  final Ad ad;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;

  const NativeAdPosterCard({
    super.key,
    required this.ad,
    this.onKeyEvent,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    double s(double v) => (v * screenWidth) / 1920;

    final cardWidth = s(140);
    final cardHeight = s(210);

    return LongPressFocus(
      onKeyEvent: onKeyEvent,
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
            scale: hasFocus ? 1.08 : 1.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: Container(
              width: cardWidth,
              height: cardHeight,
              decoration: BoxDecoration(
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
                        color: DashboardTheme.signalRed,
                      )
                    : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  _buildImage(),
                  _buildGradient(),
                  _buildBadge(s),
                  _buildInfo(s, hasFocus),
                ],
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

  Widget _buildGradient() {
    return Positioned.fill(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black87],
            stops: [0.6, 1.0],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(double Function(double) s) {
    return Positioned(
      top: s(12),
      left: s(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(s(8)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: s(10), vertical: s(4)),
            decoration: BoxDecoration(
              color: const Color(0xFFDC2626).withValues(alpha: 0.8),
              border: Border.all(color: Colors.white24),
            ),
            child: Text(
              'SPONSORED',
              style: TextStyle(
                color: Colors.white,
                fontSize: s(12),
                fontWeight: FontWeight.w900,
                letterSpacing: s(1),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfo(double Function(double) s, bool hasFocus) {
    return Positioned(
      bottom: s(16),
      left: s(16),
      right: s(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ad.title,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: s(22),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: s(4)),
          Text(
            ad.cta,
            style: TextStyle(
              color: const Color(0xFFDC2626),
              fontWeight: FontWeight.w800,
              fontSize: s(16),
            ),
          ),
        ],
      ),
    );
  }
}
