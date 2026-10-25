# GOG Galaxy Mobile - Readonly Store & Catalog App

An ultra-lightweight React Native mobile store viewer for **GOG Galaxy**, crafted to provide an optimized, dead-simple mobile store experience inspired by Steam Mobile and Epic Games Mobile.

## Key Features

1. **Simple & Ultra-Lightweight (2.1 MB total project footprint)**
   - Zero heavy local databases or bulky multi-gigabyte build artifacts.
   - Preserves system disk space while providing a high-performance native-feel experience.

2. **Live GOG Store Integration**
   - Connects directly to GOG's official catalog API (`https://catalog.gog.com/v1/catalog`), mirroring the query structure used in the Linux desktop client (`goggalaxylinux`).
   - Real-time catalog browsing, bestselling sorting, price filters, category chips (Action, RPG, Strategy, Indie, etc.), and instant live search.

3. **Security-First Architecture (Steam & GOG Standard)**
   - Per your recommendation, browsing is completely readonly within the mobile launcher.
   - Tapping "View in GOG Store" opens official `gog.com` checkout in the user's mobile browser, avoiding sensitive credential handling or in-app payment security liabilities.

4. **Wishlist & Deal Tracker**
   - Save favorite games with the tap of a heart icon.
   - Dedicated **% DEALS** toggle to spotlight discounts and sales.

## Running the App

To preview the mobile store immediately:

```bash
# Start the lightweight server with CORS-safe catalog proxy
python3 server.py
```

Then open `http://localhost:8085/` in your browser or mobile browser emulator.

## React Native Architecture

- `src/App.native.js`: Native React Native component targeting Android (`.apk`) and iOS.
- `src/api.js`: Reusable GOG catalog API fetcher.
- `index.html & style.css`: Mobile web presentation layer.
