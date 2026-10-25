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
    if (state.session.avatar && typeof state.session.avatar === 'string' && state.session.avatar.trim() !== '') {
      const av = state.session.avatar.startsWith('//') ? 'https:' + state.session.avatar : state.session.avatar;
      elements.userAvatarImg.src = av;
    } else {
      elements.userAvatarImg.src = 'assets/default-avatar.svg';
    }
  } else {
    elements.authBtnText.textContent = 'LOGIN';
    elements.userAvatarImg.src = 'assets/default-avatar.svg';
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
    let allGames = [];
    let page = 1;
    let totalPages = 1;

    do {
      const url = `${GOG_ACCOUNT_BASE}?mediaType=1&sortBy=date_purchased&page=${page}`;
      const resp = await fetch(url, {
        headers: {
          'Authorization': `Bearer ${state.session.access_token}`,
          'Accept': 'application/json'
        }
      });
      if (!resp.ok) break;

      const data = await resp.json();
      totalPages = data.totalPages || 1;

      const pageProducts = (data.products || []).filter((p) => p.isGame !== false).map((p) => {
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

      allGames.push(...pageProducts);
      page++;
    } while (page <= totalPages);

    state.ownedGames = allGames;
    elements.libraryCountBadge.textContent = state.ownedGames.length;
    elements.libraryCountBadge.classList.remove('hidden');
    elements.userGameCount.textContent = `${state.ownedGames.length} Owned Games`;

    if (state.currentTab === 'library') {
      renderFilteredLibrary();
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
    card.className = `game-card ${game.isOwned ? 'library-card' : ''}`;
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
