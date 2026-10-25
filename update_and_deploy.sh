#!/bin/bash
set -e

APP_DIR="/home/ella/Projects/goggalaxylaunchermobile"
SDK_DIR="/home/ella/Android/Sdk"
BUILD_TOOLS="$SDK_DIR/build-tools/35.0.0"
PLATFORM="$SDK_DIR/platforms/android-34/android.jar"
BUILD_DIR="$APP_DIR/android_build"

echo "=== Building Nebula with Generic Avatar Fallback ==="
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/gen" "$BUILD_DIR/obj" "$BUILD_DIR/bin" "$BUILD_DIR/res/values" "$BUILD_DIR/res/mipmap-xxhdpi" "$BUILD_DIR/assets"

cat << 'MANIFEST' > "$BUILD_DIR/AndroidManifest.xml"
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.nebula.goglauncher"
    android:versionCode="3"
    android:versionName="1.1.1">

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
        <activity
            android:name=".LoginActivity"
            android:exported="false"
            android:theme="@android:style/Theme.DeviceDefault.NoActionBar"
            android:configChanges="orientation|screenSize|keyboardHidden" />
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

# Copy assets
cp "$APP_DIR/index.html" "$BUILD_DIR/assets/"
cp "$APP_DIR/style.css" "$BUILD_DIR/assets/"
cp "$APP_DIR/bundle.js" "$BUILD_DIR/assets/"
mkdir -p "$BUILD_DIR/assets/assets"
cp "$APP_DIR/assets/icon-256.png" "$BUILD_DIR/assets/assets/"
cp "$APP_DIR/assets/default-avatar.svg" "$BUILD_DIR/assets/assets/"
cp "$APP_DIR/assets/nebula-logo.svg" "$BUILD_DIR/assets/assets/"

mkdir -p "$BUILD_DIR/src/com/nebula/goglauncher"
cp "$APP_DIR/android_src/LoginActivity.java" "$BUILD_DIR/src/com/nebula/goglauncher/"

# Copy MainActivity
cat << 'JAVA' > "$BUILD_DIR/src/com/nebula/goglauncher/MainActivity.java"
package com.nebula.goglauncher;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.util.Log;
import android.webkit.ConsoleMessage;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import org.json.JSONObject;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;

public class MainActivity extends Activity {
    private static final String TAG = "Nebula";
    private static final int REQ_LOGIN = 101;
    private static final String PREFS_NAME = "NebulaPrefs";
    private static final String CLIENT_ID = "46899977096215655";
    private static final String CLIENT_SECRET = "9d85c43b1482497dbbce61f6e4aa173a433796eeae2ca8c5f6129f2dc4de46d9";
    private static final String REDIRECT_URI = "https://embed.gog.com/on_login_success?origin=client";

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
        settings.setAllowFileAccessFromFileURLs(true);
        settings.setAllowUniversalAccessFromFileURLs(true);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        settings.setCacheMode(WebSettings.LOAD_DEFAULT);
        settings.setUseWideViewPort(true);
        settings.setLoadWithOverviewMode(true);

        mWebView.addJavascriptInterface(new NebulaNativeBridge(), "NebulaNative");

        mWebView.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onConsoleMessage(ConsoleMessage consoleMessage) {
                Log.d(TAG, "[JS " + consoleMessage.messageLevel() + "] " + consoleMessage.message());
                return true;
            }
        });

        mWebView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, String url) {
                if (url.startsWith("https://www.gog.com") || url.contains("checkout") || url.contains("gog.com/en/game/")) {
                    try {
                        Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
                        startActivity(intent);
                        return true;
                    } catch (Exception e) {
                        Log.e(TAG, "External browse error: " + e.getMessage());
                    }
                }
                return false;
            }
        });

        mWebView.loadUrl("file:///android_asset/index.html");
        setContentView(mWebView);
    }

    public class NebulaNativeBridge {
        @JavascriptInterface
        public void startLogin() {
            Intent intent = new Intent(MainActivity.this, LoginActivity.class);
            startActivityForResult(intent, REQ_LOGIN);
        }

        @JavascriptInterface
        public void logout() {
            SharedPreferences prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
            prefs.edit().clear().apply();
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    mWebView.evaluateJavascript("window.onNebulaAuthUpdated && window.onNebulaAuthUpdated(null);", null);
                }
            });
        }

        @JavascriptInterface
        public String getSavedSession() {
            SharedPreferences prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
            return prefs.getString("session_json", "");
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == REQ_LOGIN && resultCode == RESULT_OK && data != null) {
            final String code = data.getStringExtra("auth_code");
            if (code != null) {
                exchangeTokenAsync(code);
            }
        }
        super.onActivityResult(requestCode, resultCode, data);
    }

    private void exchangeTokenAsync(final String code) {
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    String tokenUrl = "https://auth.gog.com/token?client_id=" + CLIENT_ID
                            + "&client_secret=" + CLIENT_SECRET
                            + "&grant_type=authorization_code"
                            + "&code=" + code
                            + "&redirect_uri=" + Uri.encode(REDIRECT_URI);

                    URL url = new URL(tokenUrl);
                    HttpURLConnection conn = (HttpURLConnection) url.openConnection();
                    conn.setRequestMethod("GET");
                    conn.setRequestProperty("User-Agent", "Nebula/0.1 Mobile");

                    BufferedReader reader = new BufferedReader(new InputStreamReader(conn.getInputStream()));
                    StringBuilder sb = new StringBuilder();
                    String line;
                    while ((line = reader.readLine()) != null) sb.append(line);
                    reader.close();

                    JSONObject tokenObj = new JSONObject(sb.toString());
                    final String accessToken = tokenObj.getString("access_token");
                    final String refreshToken = tokenObj.getString("refresh_token");
                    final String userId = tokenObj.getString("user_id");

                    String username = "GOG Gamer";
                    String avatarUrl = "";
                    try {
                        URL userUrl = new URL("https://embed.gog.com/userData.json");
                        HttpURLConnection uConn = (HttpURLConnection) userUrl.openConnection();
                        uConn.setRequestProperty("Authorization", "Bearer " + accessToken);
                        uConn.setRequestProperty("User-Agent", "Nebula/0.1 Mobile");
                        BufferedReader uReader = new BufferedReader(new InputStreamReader(uConn.getInputStream()));
                        StringBuilder uSb = new StringBuilder();
                        while ((line = uReader.readLine()) != null) uSb.append(line);
                        uReader.close();

                        JSONObject uObj = new JSONObject(uSb.toString());
                        if (uObj.has("username")) username = uObj.getString("username");
                        if (uObj.has("avatar")) {
                            Object av = uObj.get("avatar");
                            if (av instanceof String) avatarUrl = (String) av;
                            else if (av instanceof JSONObject) {
                                JSONObject avObj = (JSONObject) av;
                                if (avObj.has("large")) avatarUrl = avObj.getString("large");
                                else if (avObj.has("big")) avatarUrl = avObj.getString("big");
                                else if (avObj.has("medium")) avatarUrl = avObj.getString("medium");
                            }
                        }
                    } catch (Exception ex) {
                        Log.e(TAG, "Error fetching userData: " + ex.getMessage());
                    }

                    JSONObject session = new JSONObject();
                    session.put("access_token", accessToken);
                    session.put("refresh_token", refreshToken);
                    session.put("user_id", userId);
                    session.put("username", username);
                    session.put("avatar", avatarUrl);

                    final String sessionStr = session.toString();
                    getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit()
                            .putString("session_json", sessionStr).apply();

                    runOnUiThread(new Runnable() {
                        @Override
                        public void run() {
                            String escaped = sessionStr.replace("'", "\\'");
                            mWebView.evaluateJavascript("window.onNebulaAuthUpdated && window.onNebulaAuthUpdated('" + escaped + "');", null);
                        }
                    });

                } catch (Exception e) {
                    Log.e(TAG, "Auth exchange failed: " + e.getMessage(), e);
                }
            }
        }).start();
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

"$BUILD_TOOLS/aapt" package -f -m \
    -J "$BUILD_DIR/gen" \
    -M "$BUILD_DIR/AndroidManifest.xml" \
    -S "$BUILD_DIR/res" \
    -I "$PLATFORM"

javac -source 1.8 -target 1.8 \
    -bootclasspath "$PLATFORM" \
    -d "$BUILD_DIR/obj" \
    "$BUILD_DIR/gen/com/nebula/goglauncher/R.java" \
    "$BUILD_DIR"/src/com/nebula/goglauncher/*.java

"$BUILD_TOOLS/d8" --release --min-api 24 \
    --output "$BUILD_DIR/bin" \
    --lib "$PLATFORM" \
    "$BUILD_DIR"/obj/com/nebula/goglauncher/*.class

"$BUILD_TOOLS/aapt" package -f \
    -M "$BUILD_DIR/AndroidManifest.xml" \
    -S "$BUILD_DIR/res" \
    -A "$BUILD_DIR/assets" \
    -I "$PLATFORM" \
    -F "$BUILD_DIR/bin/app-unaligned.apk"

cd "$BUILD_DIR/bin"
"$BUILD_TOOLS/aapt" add app-unaligned.apk classes.dex
cd "$APP_DIR"

rm -f "$APP_DIR/Nebula.apk"
"$BUILD_TOOLS/zipalign" -v -p 4 "$BUILD_DIR/bin/app-unaligned.apk" "$APP_DIR/Nebula.apk"
"$BUILD_TOOLS/apksigner" sign --ks "$APP_DIR/debug.keystore" --ks-pass pass:android --key-pass pass:android "$APP_DIR/Nebula.apk"

echo "=== Deploying to phone ==="
adb install -r "$APP_DIR/Nebula.apk"
adb shell am force-stop com.nebula.goglauncher
adb shell am start -n com.nebula.goglauncher/.MainActivity

rm -rf "$BUILD_DIR"
echo "=== Deployed with generic profile avatar fallback! ==="
