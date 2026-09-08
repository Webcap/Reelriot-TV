package media.webcap.reelriot.tv

import android.content.Context
import android.media.AudioManager
import android.util.Log
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val webViewFocusChannel = "reelriot.tv/webview_focus"
    private val tag = "ReelRiotWebViewFocus"

    // Tracked so dispatchKeyEvent() can forcibly forward keys to it while the
    // embedded-web-player fallback is showing.
    private var embeddedWebView: WebView? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
