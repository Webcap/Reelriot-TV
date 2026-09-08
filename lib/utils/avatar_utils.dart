class AvatarUtils {
  /// Base URL for avatar assets.
  /// Hosted on the main web application to ensure ecosystem-wide availability.
  static const String _baseUrl = 'https://reelriot.app/assets/images/profiles';
  
  /// Default avatar placeholder.
  static const String defaultAvatar = 'https://reelriot.app/assets/images/Default_pfp.svg';

  /// Resolves an avatar ID or partial path to a full URL.
  static String getAvatarUrl(dynamic avatar) {
    if (avatar == null || avatar.toString().isEmpty) {
      return defaultAvatarUrl;
    }

    final avatarStr = avatar.toString();

    // If it's already a full URL, return it
    if (avatarStr.startsWith('http')) {
      return avatarStr;
    }

    // If it's a numeric ID or a simple filename, construct the URL
    // Extension defaults to .png if not present
    final hasExtension = avatarStr.contains('.');
    final fileName = hasExtension ? avatarStr : '$avatarStr.png';

    return '$_baseUrl/$fileName';
  }

  static String get defaultAvatarUrl => 'https://reelriot.app/assets/images/profiles/0.png';
}
