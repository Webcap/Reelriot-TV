import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Resolves a real HLS (.m3u8) stream URL out of a provider's raw HTML embed
/// page (e.g. vixsrc.to/movie/...) by loading it in an off-screen WebView and
/// sniffing network requests / the page's video player for the stream URL.
///
/// This mirrors the extraction trick the mobile app uses, but only for
/// Android: Tizen (Samsung TV) has no WebView implementation available to
/// Flutter, so [resolve] returns null immediately on any other platform and
/// the caller should treat the provider as failed.
class EmbedStreamResolver {
  EmbedStreamResolver._();

  static Future<String?> resolve(
    BuildContext context,
    String embedUrl, {
    Duration timeout = const Duration(seconds: 7),
  }) async {
    if (!Platform.isAndroid) return null;

    final overlay = Overlay.of(context, rootOverlay: true);
    final completer = Completer<String?>();
    late OverlayEntry entry;
    Timer? timer;

    void finish(String? result) {
      if (!completer.isCompleted) completer.complete(result);
    }

    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -10,
        top: -10,
        width: 320,
        height: 180,
        child: IgnorePointer(
          child: Opacity(
            opacity: 0.0,
            child: _EmbedResolverWebView(url: embedUrl, onResolved: finish),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    timer = Timer(timeout, () => finish(null));

    try {
      final result = await completer.future;
      debugPrint(
        '[EmbedStreamResolver] ${result != null ? "✅ Resolved" : "⏱️ Failed/timed out"} for $embedUrl',
      );
      return result;
    } finally {
      timer.cancel();
      entry.remove();
    }
  }
}

class _EmbedResolverWebView extends StatefulWidget {
  final String url;
  final void Function(String? hls) onResolved;

  const _EmbedResolverWebView({required this.url, required this.onResolved});

  @override
  State<_EmbedResolverWebView> createState() => _EmbedResolverWebViewState();
}

class _EmbedResolverWebViewState extends State<_EmbedResolverWebView> {
  late final WebViewController _controller;
  bool _done = false;

  void _resolve(String? hls) {
    if (_done) return;
    _done = true;
    widget.onResolved(hls);
  }

  void _runJs(String js) {
    if (!mounted || _done) return;
    _controller.runJavaScript(js);
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'HlsExtracted',
        onMessageReceived: (message) {
          final url = message.message.trim();
          if (url.isNotEmpty && url.contains('.m3u8')) {
            debugPrint('[EmbedStreamResolver] HLS extracted: $url');
            _resolve(url);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          // Inject the network sniffer as early as possible (before the
          // page's own scripts run), not on onPageFinished: providers like
          // vixsrc load their actual player inside a nested same-origin
          // iframe that fetches its .m3u8 manifest almost immediately, well
          // before the "page fully loaded" event fires.
          onPageStarted: (_) {
            _runJs(_interceptHlsJs);
          },
          onPageFinished: (_) {
            _runJs(_adBlockJs);
            _runJs(_interceptHlsJs);
            _runJs(_extractHlsJs);
            for (final ms in [500, 1500, 3000, 5000]) {
              Future<void>.delayed(
                Duration(milliseconds: ms),
                () => _runJs(_extractHlsJs),
              );
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));

    // Deliberately left at the default (autoplay requires a user gesture):
    // this probe is invisible, so nothing should be audible or decoding
    // while it looks for a directly extractable stream URL.
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}

/// Blocks popup/redirect ad noise so the real player script can load and
/// start the video without the page navigating away underneath us.
const String _adBlockJs = r'''
  (function() {
    try {
      Object.defineProperty(window, 'open', {
        value: function() { return null; },
        writable: false,
        configurable: false
      });
    } catch(e) {}
    try {
      window.alert = function() {};
      window.confirm = function() { return false; };
      window.prompt = function() { return null; };
    } catch(e) {}
  })();
''';

/// Intercepts fetch/XHR so any .m3u8 request the page makes gets captured
/// even if it never lands on a <video> element we can inspect directly.
///
/// Providers like vixsrc load their real player inside a nested same-origin
/// iframe, which gets its own independent `window`/`fetch`/`XMLHttpRequest`
/// distinct from the top frame's. Patching only `window` here would never
/// see that iframe's manifest request, so a MutationObserver patches every
/// iframe (existing and future) individually as soon as it appears.
const String _interceptHlsJs = r'''
  (function() {
    if (window.__rrHlsInterceptInstalled) return;
    window.__rrHlsInterceptInstalled = true;

    function send(url) {
      if (!url || url.length < 20 || url.indexOf('.m3u8') === -1) return;
      if (url.indexOf('/ad') !== -1 || url.indexOf('ad.') !== -1 || url.indexOf('ads.') !== -1) return;
      try { if (typeof HlsExtracted !== 'undefined') HlsExtracted.postMessage(url); } catch (e) {}
    }

    function patchWindow(win) {
      if (!win || win.__rrPatched) return;
      try {
        win.__rrPatched = true;
        var _fetch = win.fetch;
        if (_fetch) {
          win.fetch = function(input) {
            var url = typeof input === 'string' ? input : (input && input.url);
            if (url) send(url);
            return _fetch.apply(this, arguments);
          };
        }
        var XHR = win.XMLHttpRequest;
        if (XHR) {
          var _open = XHR.prototype.open;
          XHR.prototype.open = function(method, url) {
            this._hlsUrl = url;
            return _open.apply(this, arguments);
          };
          var _send = XHR.prototype.send;
          XHR.prototype.send = function() {
            if (this._hlsUrl) send(this._hlsUrl);
            return _send.apply(this, arguments);
          };
        }
      } catch(e) {}
    }

    function tryPatchFrame(f) {
      try { patchWindow(f.contentWindow); } catch(e) {}
      try { f.addEventListener('load', function() { try { patchWindow(f.contentWindow); } catch(e) {} }); } catch(e) {}
    }

    patchWindow(window);
    try { document.querySelectorAll('iframe').forEach(tryPatchFrame); } catch(e) {}

    try {
      var mo = new MutationObserver(function(muts) {
        muts.forEach(function(m) {
          (m.addedNodes || []).forEach(function(n) {
            if (!n) return;
            if (n.tagName === 'IFRAME') tryPatchFrame(n);
            if (n.querySelectorAll) {
              try { n.querySelectorAll('iframe').forEach(tryPatchFrame); } catch(e) {}
            }
          });
        });
      });
      mo.observe(document, {childList: true, subtree: true});
    } catch(e) {}
  })();
''';

/// Scans the DOM/known player globals for an already-resolved .m3u8 source,
/// recursing into same-origin iframes since the actual player often lives
/// one level down (e.g. vixsrc.to/movie/x wraps vixsrc.to/embed/y).
const String _extractHlsJs = r'''
  (function() {
    function scanDoc(doc, depth) {
      if (!doc || depth > 3) return null;
      try {
        var v = doc.querySelector('video');
        if (v) {
          var s = v.querySelector('source[src*=".m3u8"]');
          if (s && s.src) return s.src;
          if (v.src && v.src.indexOf('.m3u8') !== -1) return v.src;
          if (v.currentSrc && v.currentSrc.indexOf('.m3u8') !== -1) return v.currentSrc;
        }
        var win = doc.defaultView;
        if (win) {
          if (win.Hls && win.Hls.instances && win.Hls.instances.length) {
            for (var i = 0; i < win.Hls.instances.length; i++) {
              var u = win.Hls.instances[i].url || (win.Hls.instances[i].media && win.Hls.instances[i].media.src);
              if (u && u.indexOf('.m3u8') !== -1) return u;
            }
          }
          if (win.hls && win.hls.url) return win.hls.url;
          if (win.videojs) {
            var players = win.videojs.getPlayers ? win.videojs.getPlayers() : {};
            for (var k in players) {
              var p = players[k];
              var src = (p.currentSrc && p.currentSrc()) ? p.currentSrc() : (p.el_ && p.el_().querySelector('source') && p.el_().querySelector('source').src);
              if (src && src.indexOf('.m3u8') !== -1) return src;
            }
          }
          if (typeof win.jwplayer === 'function') {
            try {
              var jp = win.jwplayer();
              if (jp && jp.getPlaylist) {
                var pl = jp.getPlaylist();
                if (pl && pl.length > 0 && pl[0].file && pl[0].file.indexOf('.m3u8') !== -1) {
                  return pl[0].file;
                }
              }
            } catch(e) {}
          }
        }
        var scripts = doc.querySelectorAll('script');
        for (var i = 0; i < scripts.length; i++) {
          var m = (scripts[i].textContent || '').match(/https?:\/\/[^\s"'<>]+\.m3u8[^\s"'<>]*/g);
          if (m) for (var j = 0; j < m.length; j++) if (m[j].indexOf('/ad') === -1 && m[j].indexOf('ad.') === -1) return m[j].replace(/['")}\]]+$/, '');
        }
        var iframes = doc.querySelectorAll('iframe');
        for (var f = 0; f < iframes.length; f++) {
          try {
            var idoc = iframes[f].contentDocument;
            var r = scanDoc(idoc, depth + 1);
            if (r) return r;
          } catch(e) {}
        }
      } catch (e) {}
      return null;
    }
    var u = scanDoc(document, 0);
    if (u && u.length > 20 && u.indexOf('/ad') === -1 && u.indexOf('ad.') === -1 && u.indexOf('ads.') === -1) {
      if (typeof HlsExtracted !== 'undefined') HlsExtracted.postMessage(u);
    }
  })();
''';
