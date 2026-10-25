#!/bin/bash
set -e

SDK_DIR="/home/ella/Android/Sdk"
BUILD_TOOLS="$SDK_DIR/build-tools/35.0.0"
PLATFORM="$SDK_DIR/platforms/android-34/android.jar"
APP_DIR="/home/ella/Projects/goggalaxylaunchermobile"
BUILD_DIR="$APP_DIR/android_build"

echo "=== 1. Updating App branding & Web runtime ==="
# Ensure index.html title is Nebula
sed -i 's/<title>.*<\/title>/<title>Nebula - GOG Store<\/title>/' "$APP_DIR/index.html"

echo "=== 2. Re-building Android APK with WebChromeClient console logging & WebView debugging enabled ==="
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/gen" "$BUILD_DIR/obj" "$BUILD_DIR/bin" "$BUILD_DIR/res/values" "$BUILD_DIR/res/mipmap-xxhdpi" "$BUILD_DIR/assets"

cat << 'MANIFEST' > "$BUILD_DIR/AndroidManifest.xml"
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.nebula.goglauncher"
    android:versionCode="1"
    android:versionName="1.0.0">

    <uses-sdk android:minSdkVersion="24" android:targetSdkVersion="34" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

    <application
        android:label="Nebula"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher"
        android:theme="@android:style/Theme.NoTitleBar.Fullscreen"
        android:usesCleartextTraffic="true"
        android:hardwareAccelerated="true">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:configChanges="orientation|screenSize|keyboardHidden">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
MANIFEST

cat << 'STRINGS' > "$BUILD_DIR/res/values/strings.xml"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">Nebula</string>
</resources>
STRINGS

cp "$APP_DIR/assets/icon-256.png" "$BUILD_DIR/res/mipmap-xxhdpi/ic_launcher.png"

# Copy latest assets
cp "$APP_DIR/index.html" "$BUILD_DIR/assets/"
cp "$APP_DIR/style.css" "$BUILD_DIR/assets/"
mkdir -p "$BUILD_DIR/assets/src" "$BUILD_DIR/assets/assets"
cp "$APP_DIR/src/api.js" "$BUILD_DIR/assets/src/"
cp "$APP_DIR/src/app.js" "$BUILD_DIR/assets/src/"
cp "$APP_DIR/assets/icon-256.png" "$BUILD_DIR/assets/assets/"

mkdir -p "$BUILD_DIR/src/com/nebula/goglauncher"
cat << 'JAVA' > "$BUILD_DIR/src/com/nebula/goglauncher/MainActivity.java"
package com.nebula.goglauncher;

import android.app.Activity;
import android.os.Bundle;
import android.os.Build;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.ConsoleMessage;
import android.content.Intent;
import android.net.Uri;
import android.graphics.Color;
import android.util.Log;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;

public class MainActivity extends Activity {
    private static final String TAG = "Nebula";
    private WebView mWebView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        WebView.setWebContentsDebuggingEnabled(true);

        mWebView = new WebView(this);
        mWebView.setBackgroundColor(Color.parseColor("#0e0d13"));

        WebSettings settings = mWebView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setAllowFileAccess(true);
        settings.setAllowContentAccess(true);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        settings.setCacheMode(WebSettings.LOAD_DEFAULT);
        settings.setUseWideViewPort(true);
        settings.setLoadWithOverviewMode(true);

        mWebView.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onConsoleMessage(ConsoleMessage consoleMessage) {
                Log.d(TAG, "[JS] " + consoleMessage.message() + " -- From line "
                        + consoleMessage.lineNumber() + " of " + consoleMessage.sourceId());
                return true;
            }
        });

        mWebView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                String url = uri.toString();
                if (url.contains("gog.com/en/game/") || url.contains("checkout") || url.startsWith("https://www.gog.com") || url.startsWith("http://") || url.startsWith("https://")) {
                    if (!url.contains("/api/catalog")) {
                        try {
                            Intent intent = new Intent(Intent.ACTION_VIEW, uri);
                            startActivity(intent);
                            return true;
                        } catch (Exception e) {
                            Log.e(TAG, "Failed to launch external browser: " + e.getMessage());
                        }
                    }
                }
                return false;
            }

            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                String path = uri.getPath();
                if (path != null && (path.startsWith("/api/catalog") || uri.toString().contains("catalog.gog.com/v1/catalog"))) {
                    try {
                        String query = uri.getQuery();
                        String targetUrl = "https://catalog.gog.com/v1/catalog" + (query != null && !query.isEmpty() ? "?" + query : "");
                        Log.d(TAG, "Proxying catalog request: " + targetUrl);
                        URL url = new URL(targetUrl);
                        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
                        conn.setRequestMethod("GET");
                        conn.setRequestProperty("User-Agent", "Nebula/0.1 Mobile (Android)");
                        conn.setRequestProperty("Accept", "application/json");
                        conn.setConnectTimeout(15000);
                        conn.setReadTimeout(15000);
                        conn.connect();

                        int status = conn.getResponseCode();
                        InputStream stream = (status >= 200 && status < 400) ? conn.getInputStream() : conn.getErrorStream();
                        WebResourceResponse response = new WebResourceResponse("application/json", "UTF-8", stream);
                        response.setStatusCodeAndReasonPhrase(status, conn.getResponseMessage() != null ? conn.getResponseMessage() : "OK");
                        return response;
                    } catch (Exception e) {
                        Log.e(TAG, "Error intercepting catalog request: " + e.getMessage(), e);
                    }
                }
                return super.shouldInterceptRequest(view, request);
            }
        });

        mWebView.loadUrl("file:///android_asset/index.html");
        setContentView(mWebView);
    }

    @Override
    public void onBackPressed() {
        if (mWebView != null && mWebView.canGoBack()) {
            mWebView.goBack();
        } else {
            super.onBackPressed();
        }
    }
}
JAVA

# Compile resources
"$BUILD_TOOLS/aapt" package -f -m \
    -J "$BUILD_DIR/gen" \
    -M "$BUILD_DIR/AndroidManifest.xml" \
    -S "$BUILD_DIR/res" \
    -I "$PLATFORM"

# Compile Java
javac -source 1.8 -target 1.8 \
    -bootclasspath "$PLATFORM" \
    -d "$BUILD_DIR/obj" \
    "$BUILD_DIR/gen/com/nebula/goglauncher/R.java" \
    "$BUILD_DIR/src/com/nebula/goglauncher/MainActivity.java"

# Dex
"$BUILD_TOOLS/d8" --release --min-api 24 \
    --output "$BUILD_DIR/bin" \
    --lib "$PLATFORM" \
    "$BUILD_DIR"/obj/com/nebula/goglauncher/*.class

# Package
"$BUILD_TOOLS/aapt" package -f \
    -M "$BUILD_DIR/AndroidManifest.xml" \
    -S "$BUILD_DIR/res" \
    -A "$BUILD_DIR/assets" \
    -I "$PLATFORM" \
    -F "$BUILD_DIR/bin/app-unaligned.apk"

cd "$BUILD_DIR/bin"
"$BUILD_TOOLS/aapt" add app-unaligned.apk classes.dex
cd "$APP_DIR"

# Zipalign
rm -f "$APP_DIR/Nebula.apk"
"$BUILD_TOOLS/zipalign" -v -p 4 "$BUILD_DIR/bin/app-unaligned.apk" "$APP_DIR/Nebula.apk"

# Sign
"$BUILD_TOOLS/apksigner" sign --ks "$APP_DIR/debug.keystore" --ks-pass pass:android --key-pass pass:android "$APP_DIR/Nebula.apk"

echo "=== 3. Installing and launching on Pixel 3 XL ==="
adb install -r "$APP_DIR/Nebula.apk"
adb shell am force-stop com.nebula.goglauncher
adb shell am start -n com.nebula.goglauncher/.MainActivity

echo "=== Done! Nebula is installed and active on device. ==="
rm -rf "$BUILD_DIR"
