package org.casnaval.exercise;

import android.app.Activity;
import android.content.pm.ApplicationInfo;
import android.content.res.AssetManager;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.TextView;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

public final class MainActivity extends Activity {
    private static final String HOST = "appassets.androidplatform.net";
    private static final String HOME = "https://" + HOST + "/index.html";
    private static final int SEA = Color.rgb(9, 25, 35);
    private FrameLayout root;
    private WebView web;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        root = new FrameLayout(this);
        root.setBackgroundColor(SEA);
        setContentView(root);
        immersive();
        root.setOnApplyWindowInsetsListener((view, insets) -> {
            if (Build.VERSION.SDK_INT >= 30) {
                var edges = insets.getInsets(WindowInsets.Type.displayCutout());
                view.setPadding(edges.left, edges.top, edges.right, edges.bottom);
            } else if (Build.VERSION.SDK_INT >= 28 && insets.getDisplayCutout() != null) {
                var cutout = insets.getDisplayCutout();
                view.setPadding(cutout.getSafeInsetLeft(), cutout.getSafeInsetTop(),
                    cutout.getSafeInsetRight(), cutout.getSafeInsetBottom());
            }
            return insets;
        });

        try {
            web = new WebView(this);
            web.setBackgroundColor(SEA);
            root.addView(web, new FrameLayout.LayoutParams(-1, -1));
            WebSettings settings = web.getSettings();
            settings.setJavaScriptEnabled(true);
            settings.setDomStorageEnabled(true);
            settings.setAllowContentAccess(false);
            settings.setAllowFileAccess(false);
            settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
            settings.setBuiltInZoomControls(false);
            settings.setSupportMultipleWindows(false);
            WebView.setWebContentsDebuggingEnabled((getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0);
            web.setWebViewClient(new WebViewClient() {
                @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                    return !HOME.equals(request.getUrl().toString());
                }
                @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                    return assetResponse(request);
                }
                @Override public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                    if (request.isForMainFrame()) showError("演习海图无法打开。请退出应用后重试。");
                }
            });
            web.loadUrl(HOME);
        } catch (RuntimeException error) {
            showError("战术台无法启动。请先安装或更新 Android System WebView。");
        }
    }

    private WebResourceResponse assetResponse(WebResourceRequest request) {
        Uri uri = request.getUrl();
        String path = uri.getPath();
        if (!"GET".equals(request.getMethod()) || !"https".equals(uri.getScheme()) || !HOST.equals(uri.getHost()) ||
            uri.getPort() != -1 || path == null || !path.matches("/[A-Za-z0-9][A-Za-z0-9._/-]*") ||
            path.contains("..") || path.contains("//")) return error(403, "Offline bundle only");
        String filename = path.substring(1);
        // Explicit MIME types are needed by JS modules, Workers and WebAssembly.
        String mime = filename.endsWith(".html") ? "text/html" : filename.endsWith(".js") ? "text/javascript" :
            filename.endsWith(".css") ? "text/css" : filename.endsWith(".wasm") ? "application/wasm" :
            filename.endsWith(".json") ? "application/json" : filename.endsWith(".svg") ? "image/svg+xml" :
            filename.endsWith(".png") ? "image/png" : filename.endsWith(".webp") ? "image/webp" : "application/octet-stream";
        try {
            Map<String, String> headers = new HashMap<>();
            headers.put("Cache-Control", "no-cache");
            headers.put("X-Content-Type-Options", "nosniff");
            return new WebResourceResponse(mime, mime.startsWith("text/") ? "UTF-8" : null, 200, "OK",
                headers,
                getAssets().open(filename, AssetManager.ACCESS_STREAMING));
        } catch (IOException error) { return error(404, "Missing bundle asset"); }
    }

    private static WebResourceResponse error(int status, String text) {
        return new WebResourceResponse("text/plain", "UTF-8", status, text, Collections.emptyMap(),
            new ByteArrayInputStream(text.getBytes(StandardCharsets.UTF_8)));
    }

    private void showError(String message) {
        if (web != null) web.setVisibility(View.GONE);
        TextView note = new TextView(this);
        note.setText(message);
        note.setTextColor(Color.WHITE);
        note.setTextSize(18);
        note.setGravity(Gravity.CENTER);
        root.addView(note, new FrameLayout.LayoutParams(-1, -1));
    }

    @SuppressWarnings("deprecation")
    private void immersive() {
        if (Build.VERSION.SDK_INT >= 30) {
            getWindow().setDecorFitsSystemWindows(false);
            WindowInsetsController insets = getWindow().getInsetsController();
            if (insets != null) {
                insets.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
                insets.hide(WindowInsets.Type.systemBars());
            }
        } else {
            getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY |
                View.SYSTEM_UI_FLAG_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION |
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
        }
    }

    @Override public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) immersive();
    }

    @Override public void onPause() {
        if (web != null) web.onPause();
        super.onPause();
    }

    @Override public void onResume() {
        super.onResume();
        if (web != null) web.onResume();
    }

    @Override public void onDestroy() {
        if (web != null) {
            root.removeView(web);
            web.destroy();
            web = null;
        }
        super.onDestroy();
    }
}
