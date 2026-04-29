import 'package:flutter/foundation.dart';

class Ad {
  final String id;
  final String title;
  final String description;
  final String imageUrl;
  final String cta;
  final String link;
  final String placement;
  final String? externalHtml;
  final bool isActive;
  final int priority;

  Ad({
    required this.id,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.cta,
    required this.link,
    required this.placement,
    this.externalHtml,
    this.isActive = true,
    this.priority = 0,
  });

  factory Ad.fromJson(Map<String, dynamic> json) {
    return Ad(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      imageUrl: json['image_url'] ?? '',
      cta: json['cta'] ?? 'Learn More',
      link: json['link'] ?? '',
      placement: json['placement'] ?? 'banner',
      externalHtml: json['external_html'],
      isActive: json['is_active'] ?? true,
      priority: json['priority'] ?? 0,
    );
  }

  static List<Ad> getSimulatedAds() {
    return [
      Ad(
        id: 'sim-hero',
        title: 'Aurora Performance Gear',
        description: 'Elevate your setup with premium peripherals designed for elite performance. Get the Aurora edge today.',
        imageUrl: '/assets/images/simulated/hero_ad.png',
        cta: 'View Collection',
        link: 'https://reelriot.app',
        placement: 'hero',
      ),
      Ad(
        id: 'sim-banner',
        title: 'Stream in 4K with Reelriot+',
        description: 'Upgrade your experience with zero ads and exclusive content.',
        imageUrl: '/assets/images/simulated/banner_ad.png',
        cta: 'Go Premium',
        link: 'https://reelriot.app/premium',
        placement: 'banner',
      ),
      Ad(
        id: 'sim-poster',
        title: 'Project Omega',
        description: 'The thriller of the year. Now streaming.',
        imageUrl: '/assets/images/simulated/poster_ad.png',
        cta: 'Watch Now',
        link: 'https://reelriot.app/title/movie/omega',
        placement: 'poster',
      ),
    ];
  }

  bool matchesPlacement(String target) {
    if (placement == 'both') return true;
    return placement.toLowerCase().contains(target.toLowerCase());
  }
}
