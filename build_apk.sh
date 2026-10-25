#!/bin/bash
set -e

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_DIR="${ANDROID_HOME:-$HOME/Android/Sdk}"
BUILD_TOOLS="${BUILD_TOOLS:-$(ls -d $SDK_DIR/build-tools/* 2>/dev/null | sort -V | tail -n 1)}"
PLATFORM="${PLATFORM:-$(ls $SDK_DIR/platforms/android-*/android.jar 2>/dev/null | sort -V | tail -n 1)}"
BUILD_DIR="$APP_DIR/android_build"

echo "=== Building Lightweight Native Nebula Android APK ==="
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/gen" "$BUILD_DIR/obj" "$BUILD_DIR/bin" "$BUILD_DIR/res/values" "$BUILD_DIR/res/mipmap-xxhdpi" "$BUILD_DIR/assets"

# 1. Prepare Android Manifest
cat << 'MANIFEST' > "$BUILD_DIR/AndroidManifest.xml"
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.nebula.goglauncher"
    android:versionCode="2"
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
        <activity
            android:name=".LoginActivity"
            android:exported="false"
            android:theme="@android:style/Theme.DeviceDefault.NoActionBar"
            android:configChanges="orientation|screenSize|keyboardHidden" />
    </application>
</manifest>
MANIFEST

# 2. Strings & Icon
cat << 'STRINGS' > "$BUILD_DIR/res/values/strings.xml"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">Nebula</string>
</resources>
STRINGS

cp "$APP_DIR/assets/icon-256.png" "$BUILD_DIR/res/mipmap-xxhdpi/ic_launcher.png"

# 3. Copy web assets into APK assets/
cp "$APP_DIR/index.html" "$BUILD_DIR/assets/"
cp "$APP_DIR/style.css" "$BUILD_DIR/assets/"
mkdir -p "$BUILD_DIR/assets/src"
cp "$APP_DIR/src/api.js" "$BUILD_DIR/assets/src/"
cp "$APP_DIR/src/app.js" "$BUILD_DIR/assets/src/"
mkdir -p "$BUILD_DIR/assets/assets"
cp "$APP_DIR/assets/icon-256.png" "$BUILD_DIR/assets/assets/"
cp "$APP_DIR/assets/default-avatar.svg" "$BUILD_DIR/assets/assets/" 2>/dev/null || true
cp "$APP_DIR/bundle.js" "$BUILD_DIR/assets/" 2>/dev/null || true

# 4. Copy Java sources
mkdir -p "$BUILD_DIR/src/com/nebula/goglauncher"
cp "$APP_DIR/android_src/MainActivity.java" "$BUILD_DIR/src/com/nebula/goglauncher/"
cp "$APP_DIR/android_src/LoginActivity.java" "$BUILD_DIR/src/com/nebula/goglauncher/"

# 5. Compile Resources with aapt
"$BUILD_TOOLS/aapt" package -f -m \
    -J "$BUILD_DIR/gen" \
    -M "$BUILD_DIR/AndroidManifest.xml" \
    -S "$BUILD_DIR/res" \
    -I "$PLATFORM"

# 6. Compile Java with javac
javac -source 1.8 -target 1.8 \
    -bootclasspath "$PLATFORM" \
    -d "$BUILD_DIR/obj" \
    "$BUILD_DIR/gen/com/nebula/goglauncher/R.java" \
    "$BUILD_DIR/src/com/nebula/goglauncher/MainActivity.java" \
    "$BUILD_DIR/src/com/nebula/goglauncher/LoginActivity.java"

# 7. Convert bytecode to dex using d8
"$BUILD_TOOLS/d8" --release --min-api 24 \
    --output "$BUILD_DIR/bin" \
    --lib "$PLATFORM" \
    "$BUILD_DIR"/obj/com/nebula/goglauncher/*.class

# 8. Package unaligned APK
"$BUILD_TOOLS/aapt" package -f \
    -M "$BUILD_DIR/AndroidManifest.xml" \
    -S "$BUILD_DIR/res" \
    -A "$BUILD_DIR/assets" \
    -I "$PLATFORM" \
    -F "$BUILD_DIR/bin/app-unaligned.apk"

# Add classes.dex into APK
cd "$BUILD_DIR/bin"
"$BUILD_TOOLS/aapt" add app-unaligned.apk classes.dex
cd "$APP_DIR"

# 9. Zipalign
rm -f "$APP_DIR/Nebula.apk"
"$BUILD_TOOLS/zipalign" -v -p 4 "$BUILD_DIR/bin/app-unaligned.apk" "$APP_DIR/Nebula.apk"

# 10. Generate Debug Keystore if needed and Sign APK
if [ ! -f "$APP_DIR/debug.keystore" ]; then
    keytool -genkeypair -v -keystore "$APP_DIR/debug.keystore" -alias debug -keyalg RSA -keysize 2048 -validity 10000 -storepass android -keypass android -dname "CN=Nebula, OU=Nebula, O=Nebula, C=US"
fi

"$BUILD_TOOLS/apksigner" sign --ks "$APP_DIR/debug.keystore" --ks-pass pass:android --key-pass pass:android "$APP_DIR/Nebula.apk"

echo "=== Successfully built signed APK: $APP_DIR/Nebula.apk ==="
ls -lh "$APP_DIR/Nebula.apk"
rm -rf "$BUILD_DIR"
