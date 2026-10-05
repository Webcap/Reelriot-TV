package media.webcap.reelriot.tv

import android.content.Context
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.util.Log
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val webViewFocusChannel = "reelriot.tv/webview_focus"
    private val packageInstallerChannel = "reelriot.tv/package_installer"
    private val streamSnifferChannel = "reelriot.tv/stream_sniffer"
    private val tag = "ReelRiotWebViewFocus"
    private val snifferTag = "ReelRiotStreamSniffer"

    // Tracked so dispatchKeyEvent() can forcibly forward keys to it while the
    // embedded-web-player fallback is showing.
    private var embeddedWebView: WebView? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    // Keyed so multiple provider resolutions can sniff concurrently (the Dart
    // side may kick off several at once while racing providers) without one
    // call's cleanup tearing down another's in-flight WebView.
    private class SniffSession(
        val webView: WebView,
        val result: MethodChannel.Result,
        val timeoutRunnable: Runnable,
    )
    private val sniffSessions = mutableMapOf<Int, SniffSession>()
    private var nextSniffId = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, packageInstallerChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val filePath = call.argument<String>("filePath")
                        if (filePath.isNullOrEmpty()) {
                            result.error("INVALID_PATH", "File path cannot be null or empty", null)
                            return@setMethodCallHandler
                        }

                        val file = File(filePath)
                        if (!file.exists()) {
                            result.error("FILE_NOT_FOUND", "APK file does not exist at $filePath", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val uri: Uri = FileProvider.getUriForFile(
                                this,
                                "${applicationContext.packageName}.fileprovider",
                                file
                            )

                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e("ReelRiotPackageInstaller", "Failed to launch package installer: ${e.message}", e)
                            result.error("INSTALL_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, webViewFocusChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestFocus" -> {
                        val webView = findWebView(window.decorView)
                        embeddedWebView = webView
                        if (webView != null) {
                            webView.isFocusable = true
                            webView.isFocusableInTouchMode = true
                            webView.requestFocus()
                            Log.d(tag, "requestFocus: found WebView, isFocused=${webView.isFocused}")
                        } else {
                            Log.w(tag, "requestFocus: no WebView found in view hierarchy")
                        }
                        result.success(webView != null)
                    }
                    "releaseFocus" -> {
                        embeddedWebView = null
                        flutterRootView()?.requestFocus()
                        Log.d(tag, "releaseFocus: cleared embedded WebView reference")
                        result.success(true)
                    }
                    "isAudioActive" -> {
                        // Device-wide check (not scoped to this app's own
                        // audio session — Android doesn't expose the
                        // WebView's specific audio focus request to us), but
                        // on a TV this app effectively owns, it's a cheap and
                        // fairly reliable proxy for "the embedded video is
                        // actually playing right now" vs. still
                        // buffering/loading or paused.
                        val audioManager =
                            getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                        result.success(audioManager?.isMusicActive ?: false)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, streamSnifferChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "resolveStream" -> {
                        val url = call.argument<String>("url")
                        val timeoutMs = (call.argument<Int>("timeoutMs") ?: 7000).toLong()
                        if (url.isNullOrEmpty()) {
                            result.error("INVALID_URL", "URL cannot be null or empty", null)
                        } else {
                            startStreamSniff(url, timeoutMs, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Loads `url` in a dedicated, fully-owned WebView (not the one
    // webview_flutter manages) and watches every sub-resource request it
    // makes — including ones from cross-origin iframes the page embeds,
    // which injected JS can never see — for a direct HLS/DASH manifest URL.
    // This is the only way to reach that traffic: Android's
    // shouldInterceptRequest fires at the native WebView/Chromium layer
    // before any same-origin/CORS restriction applies, unlike JS fetch/XHR
    // patching. We only observe (always return null) so the provider's page
    // keeps loading normally; we never alter or replace its traffic.
    private fun startStreamSniff(url: String, timeoutMs: Long, result: MethodChannel.Result) {
        val sessionId = nextSniffId++
        val webView = WebView(this)

        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.mediaPlaybackRequiresUserGesture = false
        webView.settings.setSupportMultipleWindows(false)
        webView.settings.javaScriptCanOpenWindowsAutomatically = false

        // Native popup/ad-redirect blocking: refuse to create any new window.
        webView.webChromeClient = object : WebChromeClient() {
            override fun onCreateWindow(
                view: WebView?,
                isDialog: Boolean,
                isUserGesture: Boolean,
                resultMsg: Message?,
            ): Boolean = false
        }

        webView.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(
                view: WebView,
                request: WebResourceRequest,
            ): WebResourceResponse? {
                val reqUrl = request.url.toString()
                if (isLikelyManifestUrl(reqUrl)) {
                    val headers = HashMap<String, Any?>(request.requestHeaders)
                    Log.d(snifferTag, "Sniffed manifest for session $sessionId: $reqUrl")
                    mainHandler.post {
                        finishSniffSession(sessionId, mapOf("url" to reqUrl, "headers" to headers))
                    }
                }
                // Never alter/replace the real request — just observe it.
                return null
            }
        }

        // Attached off-screen (not fully detached): some OEM Android TV
        // WebView implementations throttle JS timers/network activity on a
        // WebView that was never added to a window.
        val content = window.decorView.findViewById<ViewGroup>(android.R.id.content)
        webView.alpha = 0f
        webView.translationX = -10000f
        content?.addView(webView, ViewGroup.LayoutParams(1, 1))

        val timeoutRunnable = Runnable {
            Log.d(snifferTag, "Sniff session $sessionId timed out with no match")
            finishSniffSession(sessionId, null)
        }
        sniffSessions[sessionId] = SniffSession(webView, result, timeoutRunnable)
        mainHandler.postDelayed(timeoutRunnable, timeoutMs)

        webView.loadUrl(url)
    }

    private fun finishSniffSession(sessionId: Int, payload: Map<String, Any?>?) {
        val session = sniffSessions.remove(sessionId) ?: return
        mainHandler.removeCallbacks(session.timeoutRunnable)
        (session.webView.parent as? ViewGroup)?.removeView(session.webView)
        session.webView.stopLoading()
        session.webView.destroy()
        session.result.success(payload)
    }

    private fun isLikelyManifestUrl(url: String): Boolean {
        val lower = url.lowercase()
        if (lower.length < 20) return false
        if (lower.contains("/ad") || lower.contains("ad.") || lower.contains("ads.")) return false

        // Classic extension-based manifests.
        if (lower.contains(".m3u8") || lower.contains(".mpd")) return true

        // Some providers (e.g. vixsrc) serve a token-signed HLS master
        // playlist with no file extension at all — specifically evading
        // naive ".m3u8" string matching. Confirmed via that provider's own
        // JWPlayer telemetry, which labels this exact URL shape as "mu"
        // (manifest url). Its per-rendition sub-playlists additionally carry
        // a "type=" query param (type=video/type=audio) and are fetched
        // immediately after — excluding them here means we resolve on the
        // master request, which arrives first and is what a player should
        // actually be given (it references the renditions itself).
        if (lower.contains("/playlist/") && lower.contains("token=") && !lower.contains("type=")) {
            return true
        }

        return false
    }

    // Forcibly hands D-pad/media/select keys straight to the embedded
    // WebView's own key handling, bypassing Flutter's key event channel
    // entirely, rather than relying on plain Android view-focus delegation
    // (webView.requestFocus() alone) — FlutterView can claim key events at
    // the top of this window's dispatch chain regardless of which native
    // child currently holds Android focus, so requestFocus() by itself isn't
    // guaranteed to change where events actually land. BACK/ESCAPE are
    // intentionally excluded so Flutter's own PopScope/TvKeys handling keeps
    // working normally (including as a fallback if the WebView doesn't
    // consume everything else).
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val webView = embeddedWebView
        if (webView != null &&
            event.keyCode != KeyEvent.KEYCODE_BACK &&
            event.keyCode != KeyEvent.KEYCODE_ESCAPE
        ) {
            val consumed = webView.dispatchKeyEvent(event)
            Log.d(tag, "dispatchKeyEvent: forwarded keyCode=${event.keyCode} to WebView, consumed=$consumed")
            if (consumed) return true
        }
        return super.dispatchKeyEvent(event)
    }

    private fun flutterRootView(): View? {
        val content = window.decorView.findViewById<ViewGroup>(android.R.id.content)
        return content?.getChildAt(0)
    }

    private fun findWebView(view: View): WebView? {
        if (view is WebView) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                val found = findWebView(view.getChildAt(i))
                if (found != null) return found
            }
        }
        return null
    }
}
