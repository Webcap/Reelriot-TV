package media.webcap.reelriot.tv

import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val webViewFocusChannel = "reelriot.tv/webview_focus"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Lets the embedded-web-player fallback (used when no provider gives
        // us a directly playable stream) hand real Android input focus to
        // the WebView platform view, so the TV remote's D-pad/media keys
        // reach the page's own player via the browser engine's native input
        // routing instead of being swallowed by Flutter's key handling.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, webViewFocusChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestFocus" -> {
                        val webView = findWebView(window.decorView)
                        if (webView != null) {
                            webView.isFocusable = true
                            webView.isFocusableInTouchMode = true
                            webView.requestFocus()
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    "releaseFocus" -> {
                        flutterRootView()?.requestFocus()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
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
