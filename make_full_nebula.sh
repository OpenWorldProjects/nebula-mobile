#!/bin/bash
set -e

APP_DIR="/home/ella/Projects/goggalaxylaunchermobile"
SDK_DIR="/home/ella/Android/Sdk"
BUILD_TOOLS="$SDK_DIR/build-tools/35.0.0"
PLATFORM="$SDK_DIR/platforms/android-34/android.jar"
BUILD_DIR="$APP_DIR/android_build"

echo "=== 1. Writing Native Android App with Login Activity & Library Support ==="
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/gen" "$BUILD_DIR/obj" "$BUILD_DIR/bin" "$BUILD_DIR/res/values" "$BUILD_DIR/res/mipmap-xxhdpi" "$BUILD_DIR/assets"

cat << 'MANIFEST' > "$BUILD_DIR/AndroidManifest.xml"
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.nebula.goglauncher"
    android:versionCode="2"
    android:versionName="1.1.0">

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

mkdir -p "$BUILD_DIR/src/com/nebula/goglauncher"

# Write LoginActivity.java: Handles official GOG Galaxy OAuth login via webview
cp "$APP_DIR/android_src/LoginActivity.java" "$BUILD_DIR/src/com/nebula/goglauncher/LoginActivity.java"

# Write MainActivity.java: Houses the full Nebula app and provides Native JS bridge
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
import java.io.InputStream;
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

                    // Fetch user details & username
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

echo "=== 2. Updating Web Application with Library & Login UI ==="

# Write updated HTML
cat << 'HTML' > "$APP_DIR/index.html"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
  <title>Nebula - GOG Store & Library</title>
  <link rel="icon" type="image/png" href="assets/icon-256.png">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <div class="device-viewport">
    
    <!-- Top System & App Navigation Bar -->
    <header class="app-header">
      <div class="status-bar-spacer"></div>
      <div class="header-content">
        <div class="brand">
          <div class="galaxy-logo">
            <img src="assets/icon-256.png" alt="Nebula" width="30" height="30" style="border-radius: 8px;" />
          </div>
          <div class="brand-text">
            <span class="brand-title">NEBULA</span>
            <span class="brand-badge" id="subBrandBadge">GOG STORE</span>
          </div>
        </div>
        <div class="header-actions">
          <button id="authBtn" class="pill-btn auth-pill">
            <span id="authBtnIcon">👤</span> <span id="authBtnText">LOGIN</span>
          </button>
          <button id="viewToggleBtn" class="icon-btn" title="Toggle Grid/List">
            <svg id="viewGridIcon" viewBox="0 0 24 24" width="20" height="20" stroke="currentColor" stroke-width="2" fill="none"><rect x="3" y="3" width="7" height="7"></rect><rect x="14" y="3" width="7" height="7"></rect><rect x="14" y="14" width="7" height="7"></rect><rect x="3" y="14" width="7" height="7"></rect></svg>
            <svg id="viewListIcon" class="hidden" viewBox="0 0 24 24" width="20" height="20" stroke="currentColor" stroke-width="2" fill="none"><line x1="8" y1="6" x2="21" y2="6"></line><line x1="8" y1="12" x2="21" y2="12"></line><line x1="8" y1="18" x2="21" y2="18"></line><line x1="3" y1="6" x2="3.01" y2="6"></line><line x1="3" y1="12" x2="3.01" y2="12"></line><line x1="3" y1="18" x2="3.01" y2="18"></line></svg>
          </button>
        </div>
      </div>

      <!-- Quick Search Bar -->
      <div class="search-container">
        <div class="search-input-wrap">
          <svg class="search-icon" viewBox="0 0 24 24" width="18" height="18" stroke="currentColor" stroke-width="2" fill="none"><circle cx="11" cy="11" r="8"></circle><line x1="21" y1="21" x2="16.65" y2="16.65"></line></svg>
          <input type="search" id="searchInput" placeholder="Search store, deals, library..." autocomplete="off" />
          <button id="searchClearBtn" class="clear-search hidden">&times;</button>
        </div>
      </div>

      <!-- Category Filter Pills (Horizontal Scroll) -->
      <nav class="genres-bar" id="genresBar"></nav>
    </header>

    <!-- Main Scrollable Content -->
    <main class="store-scroll-view" id="storeScrollView">
      
      <!-- User Profile Banner (Visible when logged in on Library view) -->
      <div class="user-profile-banner hidden" id="userProfileBanner">
        <div class="avatar-ring">
          <img id="userAvatarImg" src="assets/icon-256.png" alt="Avatar" />
        </div>
        <div class="user-meta">
          <h3 id="userGreeting">GOG Gamer</h3>
          <span class="user-sub" id="userGameCount">0 Owned Games</span>
        </div>
        <button id="logoutBtn" class="pill-btn logout-pill">LOGOUT</button>
      </div>

      <!-- Featured Highlight Carousel (Hero) -->
      <section class="hero-section" id="heroSection">
        <div class="section-header-compact">
          <span class="sub-heading">SPOTLIGHT</span>
          <span class="live-indicator"><span class="dot"></span> DRM-FREE</span>
        </div>
        <div class="hero-card" id="heroCard">
          <div class="hero-loader">
            <div class="spinner"></div>
          </div>
        </div>
      </section>

      <!-- Sort & Filter Bar -->
      <div class="sort-bar">
        <div class="results-count" id="resultsCount">Loading Games...</div>
        <div class="sort-dropdown-wrap" id="sortDropdownWrap">
          <label for="sortSelect">SORT:</label>
          <select id="sortSelect">
            <option value="desc:bestselling">Bestselling</option>
            <option value="asc:price">Lowest Price</option>
            <option value="desc:discount">Highest Discount</option>
            <option value="desc:releaseDate">New Releases</option>
            <option value="asc:title">Title (A-Z)</option>
          </select>
        </div>
      </div>

      <!-- Dynamic Grid / List -->
      <div class="catalog-container grid-view" id="catalogContainer">
        <!-- Cards injected dynamically -->
      </div>

      <!-- Load More Button -->
      <div class="load-more-section" id="loadMoreSection">
        <button id="loadMoreBtn" class="load-more-btn">Load More Games</button>
      </div>

    </main>

    <!-- Bottom Mobile Navigation Bar (Steam Mobile Style: Store, Library, Deals, Wishlist) -->
    <nav class="bottom-nav">
      <button class="nav-item active" data-tab="store">
        <svg viewBox="0 0 24 24" width="22" height="22" stroke="currentColor" stroke-width="2" fill="none"><path d="M6 2L3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z"></path><line x1="3" y1="6" x2="21" y2="6"></line><path d="M16 10a4 4 0 0 1-8 0"></path></svg>
        <span>Store</span>
      </button>
      <button class="nav-item" data-tab="library">
        <svg viewBox="0 0 24 24" width="22" height="22" stroke="currentColor" stroke-width="2" fill="none"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"></path><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"></path></svg>
        <span>Library</span>
        <span class="badge hidden" id="libraryCountBadge">0</span>
      </button>
      <button class="nav-item" data-tab="deals">
        <svg viewBox="0 0 24 24" width="22" height="22" stroke="currentColor" stroke-width="2" fill="none"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"></polygon></svg>
        <span>Deals</span>
      </button>
      <button class="nav-item" data-tab="wishlist">
        <svg viewBox="0 0 24 24" width="22" height="22" stroke="currentColor" stroke-width="2" fill="none"><path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"></path></svg>
        <span>Wishlist</span>
        <span class="badge" id="wishlistCount">0</span>
      </button>
    </nav>

    <!-- Modal: Game Detail Sheet -->
    <div class="modal-backdrop hidden" id="gameModalBackdrop">
      <div class="modal-sheet" id="gameModalSheet">
        <button class="modal-close-btn" id="modalCloseBtn">&times;</button>
        <div class="modal-content" id="modalContent"></div>
      </div>
    </div>

  </div>

  <script src="bundle.js"></script>
</body>
</html>
HTML

# Add styles for library & profile banner
cat << 'CSS' >> "$APP_DIR/style.css"

/* User Profile & Library Banner */
.user-profile-banner {
  background: linear-gradient(135deg, #1f1b2e 0%, #171522 100%);
  border: 1px solid var(--border-subtle);
  border-radius: var(--radius-md);
  padding: 12px 16px;
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 14px;
}

.avatar-ring img {
  width: 44px;
  height: 44px;
  border-radius: 50%;
  border: 2px solid var(--accent-primary);
  object-fit: cover;
}

.user-meta {
  flex: 1;
}

.user-meta h3 {
  font-size: 15px;
  font-weight: 800;
  color: #fff;
}

.user-sub {
  font-size: 11px;
  color: var(--accent-cyan);
  font-weight: 600;
}

.auth-pill {
  background: var(--accent-primary);
  color: #fff;
  border: 1px solid var(--accent-hover);
}

.logout-pill {
  background: rgba(255, 255, 255, 0.08);
  color: var(--text-muted);
  border: 1px solid var(--border-subtle);
  font-size: 10px;
}
CSS

# Write comprehensive bundle.js including library fetching and OAuth integration
cat << 'JS' > "$APP_DIR/bundle.js"
// Nebula Unified Mobile App Bundle
(function() {

const GOG_CATALOG_BASE = 'https://catalog.gog.com/v1/catalog';
const GOG_ACCOUNT_BASE = 'https://embed.gog.com/account/getFilteredProducts';

const GENRE_FILTERS = [
  { id: 'all', label: 'All Games' },
  { id: 'action', label: 'Action' },
  { id: 'rpg', label: 'RPG' },
  { id: 'strategy', label: 'Strategy' },
  { id: 'adventure', label: 'Adventure' },
  { id: 'indie', label: 'Indie' },
  { id: 'shooter', label: 'Shooter' },
  { id: 'classic', label: 'Classic' },
];

function formatImageUrl(url, format = '') {
  if (!url) return '';
  if (format) return url.replace('{formatter}', format);
  return url.replace(/_\{formatter\}/g, '');
}

// App State
const state = {
  currentTab: 'store', // 'store', 'library', 'deals', 'wishlist'
  products: [],
  ownedGames: [],
  page: 1,
  totalPages: 1,
  totalCount: 0,
  order: 'desc:bestselling',
  genre: 'all',
  query: '',
  isGridView: true,
  isLoading: false,
  wishlist: JSON.parse(localStorage.getItem('nebula_wishlist') || '[]'),
  session: null,
};

// DOM references
const elements = {
  subBrandBadge: document.getElementById('subBrandBadge'),
  authBtn: document.getElementById('authBtn'),
  authBtnText: document.getElementById('authBtnText'),
  userProfileBanner: document.getElementById('userProfileBanner'),
  userAvatarImg: document.getElementById('userAvatarImg'),
  userGreeting: document.getElementById('userGreeting'),
  userGameCount: document.getElementById('userGameCount'),
  logoutBtn: document.getElementById('logoutBtn'),
  genresBar: document.getElementById('genresBar'),
  catalogContainer: document.getElementById('catalogContainer'),
  resultsCount: document.getElementById('resultsCount'),
  sortSelect: document.getElementById('sortSelect'),
  sortDropdownWrap: document.getElementById('sortDropdownWrap'),
  viewToggleBtn: document.getElementById('viewToggleBtn'),
  viewGridIcon: document.getElementById('viewGridIcon'),
  viewListIcon: document.getElementById('viewListIcon'),
  searchInput: document.getElementById('searchInput'),
  searchClearBtn: document.getElementById('searchClearBtn'),
  heroCard: document.getElementById('heroCard'),
  heroSection: document.getElementById('heroSection'),
  loadMoreBtn: document.getElementById('loadMoreBtn'),
  wishlistCount: document.getElementById('wishlistCount'),
  libraryCountBadge: document.getElementById('libraryCountBadge'),
  bottomNavItems: document.querySelectorAll('.bottom-nav .nav-item'),
  gameModalBackdrop: document.getElementById('gameModalBackdrop'),
  modalContent: document.getElementById('modalContent'),
  modalCloseBtn: document.getElementById('modalCloseBtn'),
};

function init() {
  loadSavedSession();
  renderGenreFilters();
  updateWishlistCount();
  setupEventListeners();
  loadCatalogData(true);
}

function loadSavedSession() {
  try {
    if (window.NebulaNative && window.NebulaNative.getSavedSession) {
      const saved = window.NebulaNative.getSavedSession();
      if (saved) {
        state.session = JSON.parse(saved);
        updateAuthUI();
        fetchOwnedGames();
      }
    }
  } catch (e) {
    console.error('Session load error:', e);
  }
}

// Called by Android Native Java Bridge after OAuth completion
window.onNebulaAuthUpdated = function(sessionJsonStr) {
  if (sessionJsonStr) {
    try {
      state.session = JSON.parse(sessionJsonStr);
      updateAuthUI();
      fetchOwnedGames();
      if (state.currentTab === 'library') {
        showLibrary();
      }
    } catch (e) {
      console.error('Parse session error:', e);
    }
  } else {
    state.session = null;
    state.ownedGames = [];
    updateAuthUI();
    if (state.currentTab === 'library') {
      showLibrary();
    }
  }
};

function updateAuthUI() {
  if (state.session && state.session.username) {
    elements.authBtnText.textContent = state.session.username.toUpperCase();
    elements.userGreeting.textContent = state.session.username;
    if (state.session.avatar) {
      const av = state.session.avatar.startsWith('//') ? 'https:' + state.session.avatar : state.session.avatar;
      elements.userAvatarImg.src = av;
    }
  } else {
    elements.authBtnText.textContent = 'LOGIN';
    elements.userProfileBanner.classList.add('hidden');
  }
}

function setupEventListeners() {
  // Login / Logout
  elements.authBtn.addEventListener('click', () => {
    if (state.session) {
      // If already logged in, navigate to library
      setActiveTab('library');
      showLibrary();
    } else {
      if (window.NebulaNative && window.NebulaNative.startLogin) {
        window.NebulaNative.startLogin();
      } else {
        alert('GOG Login is available in the Nebula Android app.');
      }
    }
  });

  elements.logoutBtn.addEventListener('click', () => {
    if (window.NebulaNative && window.NebulaNative.logout) {
      window.NebulaNative.logout();
    }
  });

  // Sort
  elements.sortSelect.addEventListener('change', (e) => {
    state.order = e.target.value;
    state.page = 1;
    loadCatalogData(true);
  });

  // Toggle View
  elements.viewToggleBtn.addEventListener('click', () => {
    state.isGridView = !state.isGridView;
    elements.catalogContainer.className = `catalog-container ${state.isGridView ? 'grid-view' : 'list-view'}`;
    elements.viewGridIcon.classList.toggle('hidden', !state.isGridView);
    elements.viewListIcon.classList.toggle('hidden', state.isGridView);
  });

  // Search
  let searchTimeout = null;
  elements.searchInput.addEventListener('input', (e) => {
    const val = e.target.value;
    elements.searchClearBtn.classList.toggle('hidden', !val);
    clearTimeout(searchTimeout);
    searchTimeout = setTimeout(() => {
      state.query = val;
      if (state.currentTab === 'library') {
        renderFilteredLibrary();
      } else if (state.currentTab === 'wishlist') {
        renderFilteredWishlist();
      } else {
        state.page = 1;
        loadCatalogData(true);
      }
    }, 300);
  });

  elements.searchClearBtn.addEventListener('click', () => {
    elements.searchInput.value = '';
    elements.searchClearBtn.classList.add('hidden');
    state.query = '';
    if (state.currentTab === 'library') renderFilteredLibrary();
    else if (state.currentTab === 'wishlist') renderFilteredWishlist();
    else {
      state.page = 1;
      loadCatalogData(true);
    }
  });

  // Load More
  elements.loadMoreBtn.addEventListener('click', () => {
    if (!state.isLoading && state.page < state.totalPages) {
      state.page += 1;
      loadCatalogData(false);
    }
  });

  // Navigation Tabs (Store, Library, Deals, Wishlist)
  elements.bottomNavItems.forEach((btn) => {
    btn.addEventListener('click', () => {
      const tab = btn.getAttribute('data-tab');
      setActiveTab(tab);

      if (tab === 'store') {
        elements.subBrandBadge.textContent = 'GOG STORE';
        elements.genresBar.classList.remove('hidden');
        elements.sortDropdownWrap.classList.remove('hidden');
        elements.userProfileBanner.classList.add('hidden');
        state.order = 'desc:bestselling';
        state.page = 1;
        loadCatalogData(true);
      } else if (tab === 'deals') {
        elements.subBrandBadge.textContent = 'DEALS & SPECIALS';
        elements.genresBar.classList.remove('hidden');
        elements.sortDropdownWrap.classList.remove('hidden');
        elements.userProfileBanner.classList.add('hidden');
        state.page = 1;
        loadCatalogData(true, true);
      } else if (tab === 'library') {
        showLibrary();
      } else if (tab === 'wishlist') {
        showWishlist();
      }
    });
  });

  elements.modalCloseBtn.addEventListener('click', () => {
    elements.gameModalBackdrop.classList.add('hidden');
  });

  elements.gameModalBackdrop.addEventListener('click', (e) => {
    if (e.target === elements.gameModalBackdrop) {
      elements.gameModalBackdrop.classList.add('hidden');
    }
  });
}

function setActiveTab(tabName) {
  state.currentTab = tabName;
  elements.bottomNavItems.forEach((btn) => {
    btn.classList.toggle('active', btn.getAttribute('data-tab') === tabName);
  });
}

function renderGenreFilters() {
  elements.genresBar.innerHTML = '';
  GENRE_FILTERS.forEach((genre) => {
    const btn = document.createElement('button');
    btn.className = `genre-tab ${state.genre === genre.id ? 'active' : ''}`;
    btn.textContent = genre.label;
    btn.addEventListener('click', () => {
      state.genre = genre.id;
      document.querySelectorAll('.genre-tab').forEach((el) => el.classList.remove('active'));
      btn.classList.add('active');
      state.page = 1;
      loadCatalogData(true, state.currentTab === 'deals');
    });
    elements.genresBar.appendChild(btn);
  });
}

async function fetchOwnedGames() {
  if (!state.session || !state.session.access_token) return;
  try {
    const url = `${GOG_ACCOUNT_BASE}?mediaType=1&sortBy=date_purchased&page=1`;
    const resp = await fetch(url, {
      headers: {
        'Authorization': `Bearer ${state.session.access_token}`,
        'Accept': 'application/json'
      }
    });
    if (resp.ok) {
      const data = await resp.json();
      state.ownedGames = (data.products || []).map((p) => {
        const coverBase = p.image ? (p.image.startsWith('//') ? 'https:' + p.image : p.image) : '';
        return {
          id: p.id,
          title: p.title,
          slug: p.slug,
          coverVertical: coverBase ? `${coverBase}.jpg` : '',
          coverHorizontal: coverBase ? `${coverBase}.jpg` : '',
          bannerImage: coverBase ? `${coverBase}.jpg` : '',
          isOwned: true,
          price: 'Owned',
          genres: [p.category || 'Game'],
          platforms: p.worksOn || {},
          storeUrl: `https://www.gog.com/en/game/${p.slug}`,
          screenshots: [],
        };
      });

      elements.libraryCountBadge.textContent = state.ownedGames.length;
      elements.libraryCountBadge.classList.remove('hidden');
      elements.userGameCount.textContent = `${state.ownedGames.length} Owned Games`;

      if (state.currentTab === 'library') {
        renderFilteredLibrary();
      }
    }
  } catch (e) {
    console.error('Failed to fetch library:', e);
  }
}

function showLibrary() {
  elements.subBrandBadge.textContent = 'YOUR LIBRARY';
  elements.heroSection.classList.add('hidden');
  elements.genresBar.classList.add('hidden');
  elements.sortDropdownWrap.classList.add('hidden');
  elements.loadMoreBtn.classList.add('hidden');

  if (!state.session) {
    elements.userProfileBanner.classList.add('hidden');
    elements.resultsCount.textContent = 'Log in to view your library';
    elements.catalogContainer.innerHTML = `
      <div style="grid-column: span 2; text-align: center; padding: 50px 20px;">
        <div style="font-size: 40px; margin-bottom: 12px;">🎮</div>
        <h3 style="color: #fff; font-size: 18px; margin-bottom: 8px;">Connect Your GOG Account</h3>
        <p style="color: #888; font-size: 12px; margin-bottom: 20px; line-height: 1.5;">
          Log in with your official GOG account to view your game library, achievements, and cloud saves on your phone — just like Steam Mobile.
        </p>
        <button id="ctaLoginBtn" class="action-buy-btn" style="margin: 0 auto; display: inline-flex;">
          Log in with GOG
        </button>
      </div>
    `;
    const cta = document.getElementById('ctaLoginBtn');
    if (cta) {
      cta.addEventListener('click', () => {
        if (window.NebulaNative && window.NebulaNative.startLogin) {
          window.NebulaNative.startLogin();
        }
      });
    }
    return;
  }

  elements.userProfileBanner.classList.remove('hidden');
  renderFilteredLibrary();
}

function renderFilteredLibrary() {
  let list = state.ownedGames;
  if (state.query) {
    const q = state.query.toLowerCase();
    list = list.filter((g) => g.title.toLowerCase().includes(q));
  }

  elements.resultsCount.textContent = `${list.length} Games in Library`;
  elements.catalogContainer.innerHTML = '';

  if (list.length === 0) {
    elements.catalogContainer.innerHTML = `
      <div style="grid-column: span 2; text-align: center; padding: 40px 20px;">
        <p style="color: #fff; font-size: 15px; font-weight: 700;">No Games Found</p>
        <p style="color: #888; font-size: 12px; margin-top: 6px;">Check your search filter or library on gog.com</p>
      </div>
    `;
    return;
  }

  renderCards(list);
}

async function loadCatalogData(reset = false, dealsOnly = false) {
  if (state.isLoading) return;
  state.isLoading = true;

  if (reset) {
    elements.catalogContainer.innerHTML = '<div class="spinner"></div>';
    elements.resultsCount.textContent = 'Searching GOG Catalog...';
  }

  try {
    const params = new URLSearchParams({
      limit: '20',
      locale: 'en-US',
      order: state.order,
      productType: 'in:game,pack',
      page: state.page.toString(),
    });

    if (dealsOnly) params.append('discounted', 'eq:true');
    if (state.genre && state.genre !== 'all') params.append('genres', `in:${state.genre}`);
    if (state.query.trim()) params.append('query', `like:${state.query.trim()}`);

    const resp = await fetch(`${GOG_CATALOG_BASE}?${params.toString()}`);
    const data = await resp.json();

    state.totalPages = data.pages || 1;
    state.totalCount = data.productCount || 0;

    const products = (data.products || []).map((item) => ({
      id: item.id,
      slug: item.slug,
      title: item.title,
      coverVertical: item.coverVertical ? formatImageUrl(item.coverVertical) : '',
      coverHorizontal: item.coverHorizontal ? formatImageUrl(item.coverHorizontal) : '',
      bannerImage: item.galaxyBackgroundImage || (item.coverHorizontal ? formatImageUrl(item.coverHorizontal) : ''),
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
      storeUrl: item.storeLink || `https://www.gog.com/en/game/${item.slug}`,
      screenshots: (item.screenshots || []).map(s => formatImageUrl(s, '')),
    }));

    if (reset) {
      state.products = products;
      elements.catalogContainer.innerHTML = '';
      if (products.length > 0 && !state.query && !dealsOnly) {
        renderHero(products[0]);
        elements.heroSection.classList.remove('hidden');
      } else {
        elements.heroSection.classList.add('hidden');
      }
    } else {
      state.products = [...state.products, ...products];
    }

    elements.resultsCount.textContent = `${data.productCount.toLocaleString()} Games Available`;
    renderCards(products);

    if (state.page >= state.totalPages) elements.loadMoreBtn.classList.add('hidden');
    else elements.loadMoreBtn.classList.remove('hidden');

  } catch (err) {
    console.error('Catalog error:', err);
    elements.resultsCount.textContent = 'Network error reaching GOG';
  } finally {
    state.isLoading = false;
  }
}

function renderHero(game) {
  const bg = game.bannerImage || game.coverHorizontal || game.coverVertical;
  elements.heroCard.innerHTML = `
    <img class="hero-bg-img" src="${bg}" alt="${game.title}" />
    <div class="hero-overlay">
      <div class="hero-title">${game.title}</div>
      <div class="hero-meta">
        <div class="hero-tags">
          ${game.genres.slice(0, 2).map((g) => `<span class="badge-tag">${g}</span>`).join('')}
          <span class="badge-tag">DRM-Free</span>
        </div>
        <div class="price-wrap">
          ${game.discount ? `<span class="discount-pill-small">${game.discount}</span>` : ''}
          ${game.discount && game.basePrice ? `<span class="price-original">${game.basePrice}</span>` : ''}
          <span class="price-current">${game.price}</span>
        </div>
      </div>
    </div>
  `;
  elements.heroCard.onclick = () => openGameModal(game);
}

function renderCards(games) {
  const fragment = document.createDocumentFragment();
  games.forEach((game) => {
    const card = document.createElement('div');
    card.className = 'game-card';
    const isWish = state.wishlist.some((w) => w.id === game.id);
    const cover = game.coverVertical || game.coverHorizontal || 'assets/icon-256.png';

    card.innerHTML = `
      <div class="card-media-wrap">
        <img class="card-cover-img" src="${cover}" alt="${game.title}" loading="lazy" />
        <button class="wishlist-heart-btn ${isWish ? 'active' : ''}">
          <svg viewBox="0 0 24 24" width="16" height="16" stroke="currentColor" stroke-width="2" fill="none"><path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"></path></svg>
        </button>
        ${game.discount ? `<span class="card-discount-badge">${game.discount}</span>` : ''}
        ${game.isOwned ? `<span class="card-discount-badge" style="background: #00d2ff; color: #000;">OWNED</span>` : ''}
      </div>
      <div class="card-info">
        <div>
          <div class="card-title">${game.title}</div>
          <div class="card-genres">${game.genres.slice(0, 2).join(' • ')}</div>
        </div>
        <div class="card-pricing-row">
          ${game.discount && game.basePrice ? `<span class="price-original">${game.basePrice}</span>` : ''}
          <span class="price-current ${game.isOwned ? 'price-free' : ''}">${game.price}</span>
        </div>
      </div>
    `;

    card.querySelector('.wishlist-heart-btn').addEventListener('click', (e) => {
      e.stopPropagation();
      toggleWishlist(game, e.currentTarget);
    });

    card.addEventListener('click', () => openGameModal(game));
    fragment.appendChild(card);
  });
  elements.catalogContainer.appendChild(fragment);
}

function toggleWishlist(game, btn) {
  const idx = state.wishlist.findIndex((w) => w.id === game.id);
  if (idx >= 0) {
    state.wishlist.splice(idx, 1);
    btn.classList.remove('active');
  } else {
    state.wishlist.push(game);
    btn.classList.add('active');
  }
  localStorage.setItem('nebula_wishlist', JSON.stringify(state.wishlist));
  updateWishlistCount();
}

function updateWishlistCount() {
  elements.wishlistCount.textContent = state.wishlist.length.toString();
}

function showWishlist() {
  elements.subBrandBadge.textContent = 'YOUR WISHLIST';
  elements.heroSection.classList.add('hidden');
  elements.genresBar.classList.add('hidden');
  elements.sortDropdownWrap.classList.add('hidden');
  elements.userProfileBanner.classList.add('hidden');
  elements.loadMoreBtn.classList.add('hidden');
  renderFilteredWishlist();
}

function renderFilteredWishlist() {
  let list = state.wishlist;
  if (state.query) {
    const q = state.query.toLowerCase();
    list = list.filter((g) => g.title.toLowerCase().includes(q));
  }
  elements.resultsCount.textContent = `Wishlist (${list.length} games)`;
  elements.catalogContainer.innerHTML = '';
  if (list.length === 0) {
    elements.catalogContainer.innerHTML = `
      <div style="grid-column: span 2; text-align: center; padding: 50px 20px;">
        <p style="color: #fff; font-size: 15px; font-weight: 700;">No Wishlisted Games</p>
        <p style="color: #888; font-size: 12px; margin-top: 6px;">Tap the heart on any store game to track deals here!</p>
      </div>
    `;
    return;
  }
  renderCards(list);
}

function openGameModal(game) {
  const banner = game.bannerImage || game.coverHorizontal || game.coverVertical;
  elements.modalContent.innerHTML = `
    <div class="modal-banner">
      <img src="${banner}" alt="${game.title}" />
      <div class="modal-banner-gradient"></div>
    </div>
    <div class="modal-body">
      <h2 class="modal-game-title">${game.title}</h2>
      <div class="modal-meta-row">
        <span>🏢 ${game.developers && game.developers[0] ? game.developers[0] : 'GOG'}</span>
        ${game.rating ? `<span>★ ${game.rating}/5.0</span>` : ''}
        <span>🛡️ 100% DRM-Free</span>
      </div>
      <div class="modal-price-row">
        <div class="price-wrap">
          ${game.discount ? `<span class="discount-pill-small">${game.discount}</span>` : ''}
          ${game.discount && game.basePrice ? `<span class="price-original">${game.basePrice}</span>` : ''}
          <span class="price-current" style="font-size: 18px;">${game.price}</span>
        </div>
        <a href="${game.storeUrl}" target="_blank" class="action-buy-btn">
          ${game.isOwned ? 'View Game Page ↗' : 'View in GOG Store ↗'}
        </a>
      </div>
      ${game.screenshots && game.screenshots.length > 0 ? `
        <div style="margin-top: 14px;">
          <h4 style="font-size: 11px; color: var(--text-muted); margin-bottom: 6px;">GALLERY</h4>
          <div class="screenshots-carousel">
            ${game.screenshots.slice(0, 6).map((img) => `<img src="${img}" alt="Screenshot" loading="lazy" />`).join('')}
          </div>
        </div>
      ` : ''}
    </div>
  `;
  elements.gameModalBackdrop.classList.remove('hidden');
}

document.addEventListener('DOMContentLoaded', init);
})();
JS

# Copy into assets/
cp "$APP_DIR/index.html" "$BUILD_DIR/assets/"
cp "$APP_DIR/style.css" "$BUILD_DIR/assets/"
cp "$APP_DIR/bundle.js" "$BUILD_DIR/assets/"
mkdir -p "$BUILD_DIR/assets/assets"
cp "$APP_DIR/assets/icon-256.png" "$BUILD_DIR/assets/assets/"

echo "=== 3. Compiling and Signing APK ==="
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

echo "=== 4. Installing and launching on phone ==="
adb install -r "$APP_DIR/Nebula.apk"
adb shell am force-stop com.nebula.goglauncher
adb shell am start -n com.nebula.goglauncher/.MainActivity

rm -rf "$BUILD_DIR"
echo "=== Nebula with GOG Login & Library successfully installed! ==="
