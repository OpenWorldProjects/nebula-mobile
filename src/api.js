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
