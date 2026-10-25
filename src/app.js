/**
 * GOG Galaxy Mobile - Application Logic
 * Mobile Store Browser with Wishlist, Real-time Search, and Detail Modal
 */

import { fetchCatalog, SORT_OPTIONS, GENRE_FILTERS } from './api.js';

// Application State
const state = {
  products: [],
  page: 1,
  totalPages: 1,
  totalCount: 0,
  order: 'desc:bestselling',
  onlyDiscounted: false,
  genre: 'all',
  query: '',
  isGridView: true,
  isLoading: false,
  wishlist: JSON.parse(localStorage.getItem('gog_galaxy_wishlist') || '[]'),
  selectedProduct: null,
};

// DOM References
const elements = {
  genresBar: document.getElementById('genresBar'),
  catalogContainer: document.getElementById('catalogContainer'),
  resultsCount: document.getElementById('resultsCount'),
  sortSelect: document.getElementById('sortSelect'),
  dealsToggleBtn: document.getElementById('dealsToggleBtn'),
  viewToggleBtn: document.getElementById('viewToggleBtn'),
  viewGridIcon: document.getElementById('viewGridIcon'),
  viewListIcon: document.getElementById('viewListIcon'),
  searchInput: document.getElementById('searchInput'),
  searchClearBtn: document.getElementById('searchClearBtn'),
  heroCard: document.getElementById('heroCard'),
  heroSection: document.getElementById('heroSection'),
  loadMoreBtn: document.getElementById('loadMoreBtn'),
  wishlistCount: document.getElementById('wishlistCount'),
  bottomNavItems: document.querySelectorAll('.bottom-nav .nav-item'),
  gameModalBackdrop: document.getElementById('gameModalBackdrop'),
  gameModalSheet: document.getElementById('gameModalSheet'),
  modalContent: document.getElementById('modalContent'),
  modalCloseBtn: document.getElementById('modalCloseBtn'),
  infoModalBackdrop: document.getElementById('infoModalBackdrop'),
  infoModalCloseBtn: document.getElementById('infoModalCloseBtn'),
};

/**
 * Initialize Application
 */
function init() {
  renderGenreFilters();
  updateWishlistCount();
  setupEventListeners();
  loadCatalogData(true);
}

/**
 * Setup Event Listeners
 */
function setupEventListeners() {
  // Sort change
  elements.sortSelect.addEventListener('change', (e) => {
    state.order = e.target.value;
    state.page = 1;
    loadCatalogData(true);
  });

  // Deals toggle button
  elements.dealsToggleBtn.addEventListener('click', () => {
    state.onlyDiscounted = !state.onlyDiscounted;
    elements.dealsToggleBtn.classList.toggle('active', state.onlyDiscounted);
    state.page = 1;
    loadCatalogData(true);
  });

  // View mode toggle (Grid vs List)
  elements.viewToggleBtn.addEventListener('click', () => {
    state.isGridView = !state.isGridView;
    if (state.isGridView) {
      elements.catalogContainer.classList.remove('list-view');
      elements.catalogContainer.classList.add('grid-view');
      elements.viewGridIcon.classList.remove('hidden');
      elements.viewListIcon.classList.add('hidden');
    } else {
      elements.catalogContainer.classList.remove('grid-view');
      elements.catalogContainer.classList.add('list-view');
      elements.viewGridIcon.classList.add('hidden');
      elements.viewListIcon.classList.remove('hidden');
    }
  });

  // Search input debounced
  let searchTimeout = null;
  elements.searchInput.addEventListener('input', (e) => {
    const val = e.target.value;
    elements.searchClearBtn.classList.toggle('hidden', val.length === 0);

    clearTimeout(searchTimeout);
    searchTimeout = setTimeout(() => {
      state.query = val;
      state.page = 1;
      loadCatalogData(true);
    }, 350);
  });

  // Search clear
  elements.searchClearBtn.addEventListener('click', () => {
    elements.searchInput.value = '';
    elements.searchClearBtn.classList.add('hidden');
    state.query = '';
    state.page = 1;
    loadCatalogData(true);
  });

  // Load more button
  elements.loadMoreBtn.addEventListener('click', () => {
    if (!state.isLoading && state.page < state.totalPages) {
      state.page += 1;
      loadCatalogData(false);
    }
  });

  // Bottom Navigation tabs
  elements.bottomNavItems.forEach((btn) => {
    btn.addEventListener('click', () => {
      const tab = btn.getAttribute('data-tab');
      setActiveNav(tab);

      if (tab === 'store') {
        state.onlyDiscounted = false;
        elements.dealsToggleBtn.classList.remove('active');
        state.page = 1;
        loadCatalogData(true);
      } else if (tab === 'deals') {
        state.onlyDiscounted = true;
        elements.dealsToggleBtn.classList.add('active');
        state.page = 1;
        loadCatalogData(true);
      } else if (tab === 'wishlist') {
        showWishlist();
      } else if (tab === 'info') {
        openInfoModal();
      }
    });
  });

  // Modals closing
  elements.modalCloseBtn.addEventListener('click', closeModal);
  elements.gameModalBackdrop.addEventListener('click', (e) => {
    if (e.target === elements.gameModalBackdrop) closeModal();
  });

  elements.infoModalCloseBtn.addEventListener('click', closeInfoModal);
  elements.infoModalBackdrop.addEventListener('click', (e) => {
    if (e.target === elements.infoModalBackdrop) closeInfoModal();
  });
}

function setActiveNav(tabName) {
  elements.bottomNavItems.forEach((btn) => {
    btn.classList.toggle('active', btn.getAttribute('data-tab') === tabName);
  });
}

/**
 * Render Genre Filter Pills
 */
function renderGenreFilters() {
  elements.genresBar.innerHTML = '';
  GENRE_FILTERS.forEach((genre) => {
    const btn = document.createElement('button');
    btn.className = `genre-tab ${state.genre === genre.id ? 'active' : ''}`;
    btn.textContent = genre.label;
    btn.addEventListener('click', () => {
      if (state.genre !== genre.id) {
        state.genre = genre.id;
        document.querySelectorAll('.genre-tab').forEach((el) => el.classList.remove('active'));
        btn.classList.add('active');
        state.page = 1;
        loadCatalogData(true);
      }
    });
    elements.genresBar.appendChild(btn);
  });
}

/**
 * Fetch and Render Catalog Data
 */
async function loadCatalogData(reset = false) {
  if (state.isLoading) return;
  state.isLoading = true;

  if (reset) {
    elements.catalogContainer.innerHTML = '<div class="spinner"></div>';
    elements.resultsCount.textContent = 'Searching GOG Catalog...';
  } else {
    elements.loadMoreBtn.textContent = 'Loading...';
  }

  try {
    const data = await fetchCatalog({
      query: state.query,
      order: state.order,
      onlyDiscounted: state.onlyDiscounted,
      genre: state.genre,
      limit: 20,
      page: state.page,
    });

    state.totalPages = data.pages;
    state.totalCount = data.productCount;

    if (reset) {
      state.products = data.products;
      elements.catalogContainer.innerHTML = '';

      if (data.products.length > 0 && !state.query) {
        renderHero(data.products[0]);
        elements.heroSection.classList.remove('hidden');
      } else {
        elements.heroSection.classList.add('hidden');
      }
    } else {
      state.products = [...state.products, ...data.products];
    }

    elements.resultsCount.textContent = `${data.productCount.toLocaleString()} Games Found`;

    renderCatalogGrid(data.products, reset);

    if (state.page >= data.pages || data.products.length === 0) {
      elements.loadMoreBtn.classList.add('hidden');
    } else {
      elements.loadMoreBtn.classList.remove('hidden');
      elements.loadMoreBtn.textContent = 'Load More Games';
    }
  } catch (error) {
    console.error('Failed to load GOG catalog:', error);
    elements.resultsCount.textContent = 'Error connecting to GOG store';
    if (reset) {
      elements.catalogContainer.innerHTML = `
        <div style="grid-column: span 2; text-align: center; padding: 40px 20px;">
          <p style="color: #ff5c5c; font-weight: 700; margin-bottom: 8px;">Network Error</p>
          <p style="color: #a3a1b0; font-size: 12px; margin-bottom: 16px;">Unable to fetch real-time GOG data. Check connection.</p>
          <button class="load-more-btn" onclick="location.reload()">Retry</button>
        </div>
      `;
    }
  } finally {
    state.isLoading = false;
  }
}

/**
 * Render Hero / Featured Game
 */
function renderHero(game) {
  const bg = game.bannerImage || game.coverHorizontal || game.coverVertical;
  const isWishlisted = state.wishlist.some((w) => w.id === game.id);

  elements.heroCard.innerHTML = `
    <img class="hero-bg-img" src="${bg}" alt="${game.title}" loading="lazy" />
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
          <span class="price-current ${game.isFree ? 'price-free' : ''}">${game.price}</span>
        </div>
      </div>
    </div>
  `;

  elements.heroCard.onclick = () => openGameModal(game);
}

/**
 * Render Product Cards into Catalog View
 */
function renderCatalogGrid(products, reset) {
  if (products.length === 0 && reset) {
    elements.catalogContainer.innerHTML = `
      <div style="grid-column: span 2; text-align: center; padding: 50px 20px;">
        <p style="color: #fff; font-size: 15px; font-weight: 700;">No Games Found</p>
        <p style="color: #888; font-size: 12px; margin-top: 6px;">Try searching for another title or clear filters</p>
      </div>
    `;
    return;
  }

  const fragment = document.createDocumentFragment();

  products.forEach((game) => {
    const card = document.createElement('div');
    card.className = 'game-card';

    const isWishlisted = state.wishlist.some((w) => w.id === game.id);
    const cover = game.coverVertical || game.coverHorizontal || 'assets/placeholder.jpg';

    card.innerHTML = `
      <div class="card-media-wrap">
        <img class="card-cover-img" src="${cover}" alt="${game.title}" loading="lazy" />
        <button class="wishlist-heart-btn ${isWishlisted ? 'active' : ''}" title="Wishlist" data-id="${game.id}">
          <svg viewBox="0 0 24 24" width="16" height="16" stroke="currentColor" stroke-width="2" fill="none"><path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"></path></svg>
        </button>
        ${game.discount ? `<span class="card-discount-badge">${game.discount}</span>` : ''}
      </div>
      <div class="card-info">
        <div>
          <div class="card-title" title="${game.title}">${game.title}</div>
          <div class="card-genres">${game.genres.length ? game.genres.slice(0, 2).join(' • ') : 'Game'}</div>
        </div>
        <div class="card-pricing-row">
          ${game.discount && game.basePrice ? `<span class="price-original">${game.basePrice}</span>` : ''}
          <span class="price-current ${game.isFree ? 'price-free' : ''}">${game.price}</span>
        </div>
      </div>
    `;

    // Heart click (Wishlist toggle)
    const heartBtn = card.querySelector('.wishlist-heart-btn');
    heartBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      toggleWishlist(game, heartBtn);
    });

    // Card click (Detail view)
    card.addEventListener('click', () => openGameModal(game));

    fragment.appendChild(card);
  });

  elements.catalogContainer.appendChild(fragment);
}

/**
 * Wishlist Handling
 */
function toggleWishlist(game, buttonEl) {
  const index = state.wishlist.findIndex((w) => w.id === game.id);
  if (index >= 0) {
    state.wishlist.splice(index, 1);
    buttonEl.classList.remove('active');
  } else {
    state.wishlist.push(game);
    buttonEl.classList.add('active');
  }

  localStorage.setItem('gog_galaxy_wishlist', JSON.stringify(state.wishlist));
  updateWishlistCount();
}

function updateWishlistCount() {
  elements.wishlistCount.textContent = state.wishlist.length.toString();
}

function showWishlist() {
  elements.heroSection.classList.add('hidden');
  elements.resultsCount.textContent = `Wishlist (${state.wishlist.length} games)`;
  elements.catalogContainer.innerHTML = '';
  elements.loadMoreBtn.classList.add('hidden');

  if (state.wishlist.length === 0) {
    elements.catalogContainer.innerHTML = `
      <div style="grid-column: span 2; text-align: center; padding: 60px 20px;">
        <svg viewBox="0 0 24 24" width="48" height="48" stroke="#6e6b7d" stroke-width="1.5" fill="none" style="margin-bottom: 12px;"><path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"></path></svg>
        <p style="color: #fff; font-size: 16px; font-weight: 700;">Your Wishlist is Empty</p>
        <p style="color: #888; font-size: 12px; margin-top: 6px;">Tap the heart icon on any game to track deals here!</p>
      </div>
    `;
    return;
  }

  renderCatalogGrid(state.wishlist, true);
}

/**
 * Open Game Detail Modal (Readonly view + Official Safe Store Redirect)
 */
function openGameModal(game) {
  state.selectedProduct = game;
  const banner = game.bannerImage || game.coverHorizontal || game.coverVertical;

  elements.modalContent.innerHTML = `
    <div class="modal-banner">
      <img src="${banner}" alt="${game.title}" />
      <div class="modal-banner-gradient"></div>
    </div>
    <div class="modal-body">
      <h2 class="modal-game-title">${game.title}</h2>
      
      <div class="modal-meta-row">
        <span>🏢 ${game.developers[0] || 'GOG'}</span>
        ${game.rating ? `<span>★ ${game.rating}/5.0 (${game.reviewsCount})</span>` : ''}
        <span>🛡️ 100% DRM-Free</span>
      </div>

      <div class="modal-price-row">
        <div class="price-wrap">
          ${game.discount ? `<span class="discount-pill-small">${game.discount}</span>` : ''}
          ${game.discount && game.basePrice ? `<span class="price-original">${game.basePrice}</span>` : ''}
          <span class="price-current" style="font-size: 18px;">${game.price}</span>
        </div>
        <a href="${game.storeUrl}" target="_blank" rel="noopener noreferrer" class="action-buy-btn">
          View in GOG Store
          <svg viewBox="0 0 24 24" width="16" height="16" stroke="currentColor" stroke-width="2" fill="none"><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"></path><polyline points="15 3 21 3 21 9"></polyline><line x1="10" y1="14" x2="21" y2="3"></line></svg>
        </a>
      </div>

      <div class="security-note">
        <svg viewBox="0 0 24 24" width="14" height="14" stroke="#00e676" stroke-width="2" fill="none"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"></path></svg>
        Safe checkout: Redirects to official GOG.com website outside mobile app.
      </div>

      ${
        game.genres && game.genres.length > 0
          ? `
        <div style="margin-top: 16px;">
          <h4 style="font-size: 12px; color: var(--text-muted); margin-bottom: 6px; text-transform: uppercase; letter-spacing: 0.5px;">Genres & Tags</h4>
          <div style="display: flex; flex-wrap: wrap; gap: 6px;">
            ${game.genres.concat(game.tags || []).slice(0, 8).map((t) => `<span class="badge-tag">${t}</span>`).join('')}
          </div>
        </div>
      `
          : ''
      }

      ${
        game.screenshots && game.screenshots.length > 0
          ? `
        <div style="margin-top: 18px;">
          <h4 style="font-size: 12px; color: var(--text-muted); margin-bottom: 8px; text-transform: uppercase; letter-spacing: 0.5px;">Gallery</h4>
          <div class="screenshots-carousel">
            ${game.screenshots.slice(0, 6).map((img) => `<img src="${img}" alt="Screenshot" loading="lazy" />`).join('')}
          </div>
        </div>
      `
          : ''
      }

      <div style="margin-top: 20px; padding: 12px; background: var(--bg-card); border-radius: 8px; font-size: 11px; color: var(--text-secondary); line-height: 1.5;">
        <strong>Platforms:</strong> ${game.operatingSystems.map((os) => os.toUpperCase()).join(', ')}<br>
        <strong>Release Date:</strong> ${game.releaseDate || 'N/A'}<br>
        <strong>Publisher:</strong> ${game.publishers.join(', ') || 'N/A'}
      </div>
    </div>
  `;

  elements.gameModalBackdrop.classList.remove('hidden');
}

function closeModal() {
  elements.gameModalBackdrop.classList.add('hidden');
}

function openInfoModal() {
  elements.infoModalBackdrop.classList.remove('hidden');
}

function closeInfoModal() {
  elements.infoModalBackdrop.classList.add('hidden');
}

// Start app
document.addEventListener('DOMContentLoaded', init);
