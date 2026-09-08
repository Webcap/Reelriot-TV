import 'package:caffeine_core/caffeine_core.dart';

class DiscoverySection {
  final String title;
  final List<MovieListItem> items;
  final String type;
  final String mediaType;
  final bool isEnabled;

  DiscoverySection({
    required this.title, 
    required this.items, 
    required this.type, 
    required this.mediaType,
    this.isEnabled = true,
  });

  factory DiscoverySection.fromJson(Map<String, dynamic> json) {
    bool enabled = true;
    if (json.containsKey('enabled')) {
      enabled = json['enabled'] == true;
    } else if (json.containsKey('is_enabled')) {
      enabled = json['is_enabled'] == true;
    } else if (json.containsKey('isActive')) {
      enabled = json['isActive'] == true;
    } else if (json.containsKey('active')) {
      enabled = json['active'] == true;
    }

    return DiscoverySection(
      title: json['title'] ?? '',
      type: json['type'] ?? '',
      mediaType: json['mediaType'] ?? '',
      isEnabled: enabled,
      items: (json['items'] as List).map((i) => MovieListItem.fromJson(i as Map<String, dynamic>)).toList(),
    );
  }
}
