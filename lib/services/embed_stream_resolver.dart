import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

/// Resolved stream URL plus the exact request headers the native WebView
/// sent for it (Referer/Origin/User-Agent/cookies) — these are the real
/// headers that succeeded in fetching the manifest, not a guess, so they
/// should be used as-is for subsequent playback requests.
class ResolvedEmbedStream {
  final String url;
  final Map<String, String> headers;

  ResolvedEmbedStream(this.url, this.headers);
}

/// Resolves a real HLS/DASH manifest URL out of a provider's raw HTML embed
/// page (e.g. vixsrc.to/movie/...) by loading it in a native, fully-owned
/// Android WebView and watching every network request it makes — including
/// ones made by cross-origin iframes the page embeds.
///
/// That last part is why this is native (see `MainActivity.kt`'s
/// `reelriot.tv/stream_sniffer` channel) rather than injected JavaScript:
/// browser security permanently blocks injected JS from reaching into a
/// cross-origin iframe (e.g. vixsrc's actual player lives one origin away
/// from the page we load), but Android's `shouldInterceptRequest` callback
/// sees that traffic anyway, since it fires at the native WebView/Chromium
/// layer before any same-origin/CORS restriction applies.
///
/// Android-only: Tizen (Samsung TV) has no WebView implementation available,
/// so [resolve] returns null immediately on any other platform and the
/// caller should treat the provider as failed.
class EmbedStreamResolver {
  EmbedStreamResolver._();

  static const MethodChannel _channel = MethodChannel(
    'reelriot.tv/stream_sniffer',
  );

  static Future<ResolvedEmbedStream?> resolve(
    String embedUrl, {
    Duration timeout = const Duration(seconds: 7),
  }) async {
    if (!Platform.isAndroid) return null;

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'resolveStream',
        {'url': embedUrl, 'timeoutMs': timeout.inMilliseconds},
      );

      if (result == null) {
        debugPrint('[EmbedStreamResolver] ⏱️ Failed/timed out for $embedUrl');
        return null;
      }

      final url = result['url'] as String?;
      if (url == null || url.isEmpty) {
        debugPrint('[EmbedStreamResolver] ⏱️ Failed/timed out for $embedUrl');
        return null;
      }

      final rawHeaders = result['headers'];
      final headers = <String, String>{};
      if (rawHeaders is Map) {
        rawHeaders.forEach((key, value) {
          if (key != null && value != null) {
            headers[key.toString()] = value.toString();
          }
        });
      }

      debugPrint('[EmbedStreamResolver] ✅ Resolved for $embedUrl -> $url');
      return ResolvedEmbedStream(url, headers);
    } on PlatformException catch (e) {
      debugPrint(
        '[EmbedStreamResolver] ❌ Platform error resolving $embedUrl: ${e.message}',
      );
      return null;
    }
  }
}
