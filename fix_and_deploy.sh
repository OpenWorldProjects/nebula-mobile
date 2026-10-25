#!/bin/bash
set -e

APP_DIR="/home/ella/Projects/goggalaxylaunchermobile"
SDK_DIR="/home/ella/Android/Sdk"
BUILD_TOOLS="$SDK_DIR/build-tools/35.0.0"
PLATFORM="$SDK_DIR/platforms/android-34/android.jar"
BUILD_DIR="$APP_DIR/android_build"

echo "=== 1. Updating src/api.js endpoint logic ==="
cat << 'JS' > "$APP_DIR/src/api.js"
/**
 * GOG Galaxy Mobile - Catalog API Service
 * Fetches real-time catalog data directly from GOG's official public API
 */

// If on web development server with proxy, use /api/catalog.
// On Android/iOS/native (or file://), hit https://catalog.gog.com/v1/catalog directly.
function getCatalogEndpoint() {
  if (typeof window !== 'undefined' && window.location && window.location.protocol.startsWith('http')) {
    if (window.location.origin.includes('localhost') || window.location.origin.includes('127.0.0.1')) {
      return `${window.location.origin}/api/catalog`;
    }
  }
  return 'https://catalog.gog.com/v1/catalog';
}

export const SORT_OPTIONS = [
  { id: 'desc:bestselling', label: 'Bestselling' },
  { id: 'asc:price', label: 'Lowest Price' },
  { id: 'desc:discount', label: 'Highest Discount' },
  { id: 'desc:releaseDate', label: 'New Releases' },
  { id: 'asc:title', label: 'Title (A-Z)' },
];

export const GENRE_FILTERS = [
  { id: 'all', label: 'All Games' },
  { id: 'action', label: 'Action' },
  { id: 'rpg', label: 'RPG' },
  { id: 'strategy', label: 'Strategy' },
  { id: 'adventure', label: 'Adventure' },
  { id: 'indie', label: 'Indie' },
  { id: 'shooter', label: 'Shooter' },
  { id: 'classic', label: 'Classic (Good Old Game)' },
];

export function formatImageUrl(url, format = '') {
  if (!url) return '';
  if (format) {
    return url.replace('{formatter}', format);
  }
  return url.replace(/_\{formatter\}/g, '');
}

export async function fetchCatalog({
  query = '',
  order = 'desc:bestselling',
  onlyDiscounted = false,
  genre = 'all',
  limit = 20,
  page = 1,
} = {}) {
  const params = new URLSearchParams({
    limit: limit.toString(),
    locale: 'en-US',
    order,
    productType: 'in:game,pack',
    page: page.toString(),
  });

  if (onlyDiscounted) {
    params.append('discounted', 'eq:true');
  }

  if (genre && genre !== 'all') {
    params.append('genres', `in:${genre}`);
  }

  const trimmed = query.trim();
  if (trimmed) {
    params.append('query', `like:${trimmed}`);
  }

  const baseUrl = getCatalogEndpoint();
  const url = `${baseUrl}?${params.toString()}`;

  const response = await fetch(url, {
    headers: {
      'Accept': 'application/json',
    },
  });

  if (!response.ok) {
    throw new Error(`Failed to fetch catalog: ${response.statusText} (${response.status})`);
  }

  const data = await response.json();
  const products = (data.products || []).map((item) => {
    const verticalCover = item.coverVertical ? formatImageUrl(item.coverVertical) : '';
    const horizontalCover = item.coverHorizontal ? formatImageUrl(item.coverHorizontal) : '';
    const banner = item.galaxyBackgroundImage || horizontalCover;

    return {
      id: item.id,
      slug: item.slug,
      title: item.title,
      coverVertical: verticalCover,
      coverHorizontal: horizontalCover,
      bannerImage: banner,
      logo: item.logo || null,
      price: item.price?.final || 'Free',
      basePrice: item.price?.base || '',
      discount: item.price?.discount ? `-${item.price.discount.replace(/^-+/, '')}%` : null,
      isFree: item.price?.final === 'Free' || item.price?.finalMoney?.amount === '0.00',
      rating: item.reviewsRating ? (item.reviewsRating / 10).toFixed(1) : null,
      reviewsCount: item.reviewsCount || 0,
      releaseDate: item.releaseDate || '',
      publishers: item.publishers || [],
      developers: item.developers || [],
      genres: (item.genres || []).map(g => g.name),
      tags: (item.tags || []).map(t => t.name).slice(0, 6),
      operatingSystems: item.operatingSystems || ['windows'],
      features: (item.features || []).map(f => f.name),
      storeUrl: item.storeLink || `https://www.gog.com/en/game/${item.slug}`,
      screenshots: (item.screenshots || []).map(s => formatImageUrl(s, '')),
    };
  });

  return {
    products,
    productCount: data.productCount || 0,
    pages: data.pages || 1,
    currentPage: page,
  };
}
JS

echo "=== 2. Re-generating bundle.js ==="
python3 -c "
with open('$APP_DIR/src/api.js') as f:
    api_code = f.read()
with open('$APP_DIR/src/app.js') as f:
    app_code = f.read()

api_clean = api_code.replace('export const ', 'const ')
api_clean = api_clean.replace('export function ', 'function ')
api_clean = api_clean.replace('export async function ', 'async function ')

lines = [l for l in app_code.splitlines() if not l.startswith('import ')]
app_clean = '\n'.join(lines)

bundle = f'''// Nebula App Bundle - Self Contained
(function() {{
{api_clean}

{app_clean}
}})();
'''

with open('$APP_DIR/bundle.js', 'w') as f:
    f.write(bundle)
print('bundle.js re-bundled.')
"

echo "=== 3. Compiling & Signing APK ==="
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
cp "$APP_DIR/index.html" "$BUILD_DIR/assets/"
cp "$APP_DIR/style.css" "$BUILD_DIR/assets/"
cp "$APP_DIR/bundle.js" "$BUILD_DIR/assets/"
mkdir -p "$BUILD_DIR/assets/assets"
cp "$APP_DIR/assets/icon-256.png" "$BUILD_DIR/assets/assets/"

mkdir -p "$BUILD_DIR/src/com/nebula/goglauncher"
cat << 'JAVA' > "$BUILD_DIR/src/com/nebula/goglauncher/MainActivity.java"
package com.nebula.goglauncher;

import android.app.Activity;
import android.os.Bundle;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.ConsoleMessage;
import android.content.Intent;
import android.net.Uri;
import android.graphics.Color;
import android.util.Log;

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
        settings.setAllowFileAccessFromFileURLs(true);
        settings.setAllowUniversalAccessFromFileURLs(true);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        settings.setCacheMode(WebSettings.LOAD_DEFAULT);
        settings.setUseWideViewPort(true);
        settings.setLoadWithOverviewMode(true);

        mWebView.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onConsoleMessage(ConsoleMessage consoleMessage) {
                Log.d(TAG, "[JS " + consoleMessage.messageLevel() + "] " + consoleMessage.message()
                        + " (" + consoleMessage.sourceId() + ":" + consoleMessage.lineNumber() + ")");
                return true;
            }
        });

        mWebView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                String url = uri.toString();
                // Safe checkout in official browser
                if (url.startsWith("https://www.gog.com") || url.contains("checkout") || url.contains("gog.com/en/game/")) {
                    try {
                        Intent intent = new Intent(Intent.ACTION_VIEW, uri);
                        startActivity(intent);
                        return true;
                    } catch (Exception e) {
                        Log.e(TAG, "Failed to launch browser: " + e.getMessage());
                    }
                }
                return false;
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

"$BUILD_TOOLS/aapt" package -f -m \
    -J "$BUILD_DIR/gen" \
    -M "$BUILD_DIR/AndroidManifest.xml" \
    -S "$BUILD_DIR/res" \
    -I "$PLATFORM"

javac -source 1.8 -target 1.8 \
    -bootclasspath "$PLATFORM" \
    -d "$BUILD_DIR/obj" \
    "$BUILD_DIR/gen/com/nebula/goglauncher/R.java" \
    "$BUILD_DIR/src/com/nebula/goglauncher/MainActivity.java"

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

echo "=== 4. Installing to phone & launching ==="
adb install -r "$APP_DIR/Nebula.apk"
adb shell am force-stop com.nebula.goglauncher
adb shell am start -n com.nebula.goglauncher/.MainActivity

rm -rf "$BUILD_DIR"
echo "=== Nebula is live on device! ==="
