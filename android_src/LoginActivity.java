package com.nebula.goglauncher;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.Bundle;
import android.os.Message;
import android.util.Log;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.CookieManager;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.ProgressBar;
import android.widget.RelativeLayout;

public class LoginActivity extends Activity {
    private static final String TAG = "NebulaLogin";
    public static final String LOGIN_URL = "https://auth.gog.com/auth?client_id=46899977096215655&redirect_uri=https%3A%2F%2Fembed.gog.com%2Fon_login_success%3Forigin%3Dclient&response_type=code&layout=galaxy";
    public static final String REDIRECT_PREFIX = "https://embed.gog.com/on_login_success";

    // Desktop/Full Chrome User-Agent so Google OAuth doesn't block embedded WebView (disallowed_useragent)
    private static final String CHROME_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36";

    private FrameLayout mContainer;
    private ProgressBar mProgressBar;
    private WebView mMainWebView;
    private boolean mCompleted = false;

    private boolean checkSuccess(String url) {
        if (mCompleted || url == null) return false;
        Log.d(TAG, "Navigating to: " + url);
        if (url.startsWith(REDIRECT_PREFIX)) {
            String code = Uri.parse(url).getQueryParameter("code");
            if (code != null && !code.isEmpty()) {
                mCompleted = true;
                Log.d(TAG, "Auth code captured: " + code);
                Intent result = new Intent();
                result.putExtra("auth_code", code);
                setResult(RESULT_OK, result);
                finish();
                return true;
            }
        }
        return false;
    }

    private void configureSettings(WebSettings s) {
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setSupportMultipleWindows(true);
        s.setJavaScriptCanOpenWindowsAutomatically(true);
        s.setUserAgentString(CHROME_UA);
        s.setAllowFileAccess(true);
        s.setAllowContentAccess(true);
        s.setLoadWithOverviewMode(true);
        s.setUseWideViewPort(true);
    }

    private WebView createWebView() {
        final WebView wv = new WebView(this);
        wv.setBackgroundColor(0xFF0E0D13);
        configureSettings(wv.getSettings());

        CookieManager cm = CookieManager.getInstance();
        cm.setAcceptCookie(true);
        cm.setAcceptThirdPartyCookies(wv, true);

        wv.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageStarted(WebView view, String url, Bitmap favicon) {
                if (checkSuccess(url)) return;
                mProgressBar.setVisibility(View.VISIBLE);
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                checkSuccess(url);
                mProgressBar.setVisibility(View.GONE);
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                String url = request.getUrl().toString();
                if (checkSuccess(url)) return true;
                return false;
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, String url) {
                if (checkSuccess(url)) return true;
                return false;
            }
        });

        wv.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onProgressChanged(WebView view, int newProgress) {
                mProgressBar.setProgress(newProgress);
                if (newProgress >= 100) {
                    mProgressBar.setVisibility(View.GONE);
                }
            }

            @Override
            public boolean onCreateWindow(WebView view, boolean isDialog, boolean isUserGesture, Message resultMsg) {
                Log.d(TAG, "Creating popup window for OAuth provider (Google/Steam/Xbox)");
                final WebView popupWebView = createWebView();
                popupWebView.setLayoutParams(new FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
                mContainer.addView(popupWebView);

                WebView.WebViewTransport transport = (WebView.WebViewTransport) resultMsg.obj;
                transport.setWebView(popupWebView);
                resultMsg.sendToTarget();
                return true;
            }

            @Override
            public void onCloseWindow(WebView window) {
                Log.d(TAG, "Closing popup window");
                mContainer.removeView(window);
                window.destroy();
            }
        });

        return wv;
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        RelativeLayout root = new RelativeLayout(this);
        root.setBackgroundColor(0xFF0E0D13);

        mContainer = new FrameLayout(this);
        RelativeLayout.LayoutParams containerParams = new RelativeLayout.LayoutParams(
                RelativeLayout.LayoutParams.MATCH_PARENT, RelativeLayout.LayoutParams.MATCH_PARENT);
        mContainer.setLayoutParams(containerParams);

        mProgressBar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        mProgressBar.setMax(100);
        mProgressBar.setIndeterminate(false);
        RelativeLayout.LayoutParams pbParams = new RelativeLayout.LayoutParams(
                RelativeLayout.LayoutParams.MATCH_PARENT, 8);
        pbParams.addRule(RelativeLayout.ALIGN_PARENT_TOP);
        mProgressBar.setLayoutParams(pbParams);

        root.addView(mContainer);
        root.addView(mProgressBar);
        setContentView(root);

        mMainWebView = createWebView();
        mMainWebView.setLayoutParams(new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        mContainer.addView(mMainWebView);

        mMainWebView.loadUrl(LOGIN_URL);
    }

    @Override
    public void onBackPressed() {
        if (mContainer.getChildCount() > 1) {
            WebView top = (WebView) mContainer.getChildAt(mContainer.getChildCount() - 1);
            if (top.canGoBack()) {
                top.goBack();
            } else {
                mContainer.removeView(top);
                top.destroy();
            }
        } else if (mMainWebView.canGoBack()) {
            mMainWebView.goBack();
        } else {
            setResult(RESULT_CANCELED);
            super.onBackPressed();
        }
    }
}
