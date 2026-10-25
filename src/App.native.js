import React, { useState, useEffect, useCallback } from 'react';
import {
  StyleSheet,
  Text,
  View,
  FlatList,
  Image,
  TouchableOpacity,
  TextInput,
  ScrollView,
  SafeAreaView,
  StatusBar,
  Linking,
  ActivityIndicator,
  Modal,
  Dimensions,
} from 'react-native';

const GOG_CATALOG_BASE = 'https://catalog.gog.com/v1/catalog';

const GENRES = [
  { id: 'all', label: 'All Games' },
  { id: 'action', label: 'Action' },
  { id: 'rpg', label: 'RPG' },
  { id: 'strategy', label: 'Strategy' },
  { id: 'adventure', label: 'Adventure' },
  { id: 'indie', label: 'Indie' },
  { id: 'shooter', label: 'Shooter' },
];

export default function App() {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [page, setPage] = useState(1);
  const [query, setQuery] = useState('');
  const [selectedGenre, setSelectedGenre] = useState('all');
  const [onlyDeals, setOnlyDeals] = useState(false);
  const [wishlist, setWishlist] = useState([]);
  const [activeTab, setActiveTab] = useState('store'); // 'store', 'deals', 'wishlist'
  const [selectedGame, setSelectedGame] = useState(null);

  // Fetch GOG Catalog data
  const loadData = useCallback(async (pageNum = 1, isFresh = false) => {
    try {
      if (pageNum === 1) setLoading(true);
      else setLoadingMore(true);

      const params = new URLSearchParams({
        limit: '20',
        locale: 'en-US',
        order: 'desc:bestselling',
        productType: 'in:game,pack',
        page: pageNum.toString(),
      });

      if (onlyDeals) params.append('discounted', 'eq:true');
      if (selectedGenre !== 'all') params.append('genres', `in:${selectedGenre}`);
      if (query.trim()) params.append('query', `like:${query.trim()}`);

      const resp = await fetch(`${GOG_CATALOG_BASE}?${params.toString()}`);
      const data = await resp.json();

      const items = (data.products || []).map((item) => ({
        id: item.id,
        slug: item.slug,
        title: item.title,
        cover: item.coverVertical ? item.coverVertical.replace('{formatter}', 'glx_vertical_cover') : '',
        banner: item.galaxyBackgroundImage || item.coverHorizontal?.replace('{formatter}', 'glx_bg_fullscreen') || '',
        price: item.price?.final || 'Free',
        basePrice: item.price?.base || '',
        discount: item.price?.discount ? `-${item.price.discount}%` : null,
        genres: (item.genres || []).map((g) => g.name),
        storeUrl: item.storeLink || `https://www.gog.com/en/game/${item.slug}`,
      }));

      setProducts((prev) => (isFresh || pageNum === 1 ? items : [...prev, ...items]));
      setPage(pageNum);
    } catch (err) {
      console.error('Error fetching GOG catalog:', err);
    } finally {
      setLoading(false);
      setLoadingMore(false);
    }
  }, [query, selectedGenre, onlyDeals]);

  useEffect(() => {
    loadData(1, true);
  }, [loadData]);

  const toggleWishlist = (game) => {
    if (wishlist.some((w) => w.id === game.id)) {
      setWishlist(wishlist.filter((w) => w.id !== game.id));
    } else {
      setWishlist([...wishlist, game]);
    }
  };

  const displayedList = activeTab === 'wishlist' ? wishlist : products;

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" backgroundColor="#0e0d13" />

      {/* Header */}
      <View style={styles.header}>
        <View style={styles.brandContainer}>
          <View style={styles.logoCircle}>
            <Text style={styles.logoText}>G</Text>
          </View>
          <View>
            <Text style={styles.headerTitle}>GOG GALAXY</Text>
            <Text style={styles.headerSubtitle}>STORE</Text>
          </View>
        </View>

        <TouchableOpacity
          style={[styles.dealsBtn, onlyDeals && styles.dealsBtnActive]}
          onPress={() => setOnlyDeals(!onlyDeals)}
        >
          <Text style={[styles.dealsBtnText, onlyDeals && styles.dealsBtnTextActive]}>% DEALS</Text>
        </TouchableOpacity>
      </View>

      {/* Search Input */}
      <View style={styles.searchContainer}>
        <TextInput
          style={styles.searchInput}
          placeholder="Search games, deals..."
          placeholderTextColor="#6e6b7d"
          value={query}
          onChangeText={setQuery}
          onSubmitEditing={() => loadData(1, true)}
        />
      </View>

      {/* Genre Pills */}
      {activeTab !== 'wishlist' && (
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.genreBar}>
          {GENRES.map((g) => (
            <TouchableOpacity
              key={g.id}
              style={[styles.genrePill, selectedGenre === g.id && styles.genrePillActive]}
              onPress={() => setSelectedGenre(g.id)}
            >
              <Text style={[styles.genreText, selectedGenre === g.id && styles.genreTextActive]}>
                {g.label}
              </Text>
            </TouchableOpacity>
          ))}
        </ScrollView>
      )}

      {/* Game Catalog Grid */}
      {loading ? (
        <View style={styles.center}>
          <ActivityIndicator size="large" color="#8a3ffc" />
        </View>
      ) : (
        <FlatList
          data={displayedList}
          numColumns={2}
          keyExtractor={(item) => item.id}
          contentContainerStyle={styles.listContent}
          onEndReached={() => {
            if (!loadingMore && activeTab !== 'wishlist') {
              loadData(page + 1, false);
            }
          }}
          onEndReachedThreshold={0.5}
          ListFooterComponent={loadingMore ? <ActivityIndicator color="#8a3ffc" style={{ margin: 16 }} /> : null}
          renderItem={({ item }) => {
            const isWish = wishlist.some((w) => w.id === item.id);
            return (
              <TouchableOpacity
                style={styles.card}
                activeOpacity={0.8}
                onPress={() => setSelectedGame(item)}
              >
                <View style={styles.coverWrapper}>
                  {item.cover ? (
                    <Image source={{ uri: item.cover }} style={styles.coverImg} />
                  ) : (
                    <View style={styles.placeholderCover} />
                  )}
                  {item.discount && (
                    <View style={styles.discountBadge}>
                      <Text style={styles.discountText}>{item.discount}</Text>
                    </View>
                  )}
                  <TouchableOpacity
                    style={[styles.heartBtn, isWish && styles.heartBtnActive]}
                    onPress={() => toggleWishlist(item)}
                  >
                    <Text style={styles.heartIcon}>{isWish ? '♥' : '♡'}</Text>
                  </TouchableOpacity>
                </View>
                <View style={styles.cardInfo}>
                  <Text style={styles.cardTitle} numberOfLines={2}>
                    {item.title}
                  </Text>
                  <Text style={styles.cardGenres} numberOfLines={1}>
                    {item.genres.join(' • ')}
                  </Text>
                  <View style={styles.priceRow}>
                    {item.discount && <Text style={styles.basePrice}>{item.basePrice}</Text>}
                    <Text style={styles.finalPrice}>{item.price}</Text>
                  </View>
                </View>
              </TouchableOpacity>
            );
          }}
        />
      )}

      {/* Bottom Navigation */}
      <View style={styles.bottomNav}>
        <TouchableOpacity
          style={[styles.navBtn, activeTab === 'store' && styles.navBtnActive]}
          onPress={() => {
            setActiveTab('store');
            setOnlyDeals(false);
          }}
        >
          <Text style={[styles.navText, activeTab === 'store' && styles.navTextActive]}>Store</Text>
        </TouchableOpacity>

        <TouchableOpacity
          style={[styles.navBtn, activeTab === 'deals' && styles.navBtnActive]}
          onPress={() => {
            setActiveTab('deals');
            setOnlyDeals(true);
          }}
        >
          <Text style={[styles.navText, activeTab === 'deals' && styles.navTextActive]}>Deals</Text>
        </TouchableOpacity>

        <TouchableOpacity
          style={[styles.navBtn, activeTab === 'wishlist' && styles.navBtnActive]}
          onPress={() => setActiveTab('wishlist')}
        >
          <Text style={[styles.navText, activeTab === 'wishlist' && styles.navTextActive]}>
            Wishlist ({wishlist.length})
          </Text>
        </TouchableOpacity>
      </View>

      {/* Detail Modal */}
      {selectedGame && (
        <Modal visible={true} transparent={true} animationType="slide">
          <View style={styles.modalOverlay}>
            <View style={styles.modalContent}>
              <TouchableOpacity style={styles.closeBtn} onPress={() => setSelectedGame(null)}>
                <Text style={styles.closeBtnText}>✕</Text>
              </TouchableOpacity>

              {selectedGame.banner ? (
                <Image source={{ uri: selectedGame.banner }} style={styles.modalBanner} />
              ) : null}

              <ScrollView style={styles.modalScroll}>
                <Text style={styles.modalTitle}>{selectedGame.title}</Text>
                <Text style={styles.drmFreeBadge}>🛡️ 100% DRM-Free Game</Text>

                <View style={styles.modalPriceBox}>
                  <View>
                    <Text style={styles.modalPriceLabel}>Store Price</Text>
                    <Text style={styles.modalPriceVal}>{selectedGame.price}</Text>
                  </View>
                  <TouchableOpacity
                    style={styles.buyBtn}
                    onPress={() => {
                      // Safe browser checkout outside app for security
                      Linking.openURL(selectedGame.storeUrl);
                    }}
                  >
                    <Text style={styles.buyBtnText}>View in GOG Store ↗</Text>
                  </TouchableOpacity>
                </View>

                <Text style={styles.securityNotice}>
                  🔒 Safe Checkout Notice: For account security and anti-phishing protection, purchases and payments take place securely in your mobile browser on official gog.com.
                </Text>
              </ScrollView>
            </View>
          </View>
        </Modal>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0e0d13',
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingTop: 12,
    paddingBottom: 8,
  },
  brandContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  logoCircle: {
    width: 28,
    height: 28,
    borderRadius: 14,
    backgroundColor: '#8a3ffc',
    justifyContent: 'center',
    alignItems: 'center',
  },
  logoText: {
    color: '#fff',
    fontWeight: '900',
    fontSize: 16,
  },
  headerTitle: {
    color: '#fff',
    fontWeight: '800',
    fontSize: 14,
    letterSpacing: 0.5,
  },
  headerSubtitle: {
    color: '#00d2ff',
    fontWeight: '700',
    fontSize: 9,
    letterSpacing: 1.2,
  },
  dealsBtn: {
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderRadius: 12,
    backgroundColor: '#211e2f',
  },
  dealsBtnActive: {
    backgroundColor: '#e02424',
  },
  dealsBtnText: {
    color: '#ff8a8a',
    fontSize: 11,
    fontWeight: '700',
  },
  dealsBtnTextActive: {
    color: '#fff',
  },
  searchContainer: {
    paddingHorizontal: 16,
    marginVertical: 6,
  },
  searchInput: {
    backgroundColor: '#171520',
    borderRadius: 20,
    paddingHorizontal: 16,
    paddingVertical: 8,
    color: '#fff',
    fontSize: 13,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
  },
  genreBar: {
    paddingHorizontal: 16,
    maxHeight: 38,
    marginBottom: 6,
  },
  genrePill: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 16,
    backgroundColor: '#171520',
    marginRight: 8,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.06)',
  },
  genrePillActive: {
    backgroundColor: '#8a3ffc',
    borderColor: '#9f54ff',
  },
  genreText: {
    color: '#a3a1b0',
    fontSize: 12,
  },
  genreTextActive: {
    color: '#fff',
    fontWeight: '700',
  },
  listContent: {
    paddingHorizontal: 10,
    paddingBottom: 70,
  },
  card: {
    flex: 1,
    margin: 6,
    backgroundColor: '#1c1926',
    borderRadius: 10,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.06)',
  },
  coverWrapper: {
    width: '100%',
    aspectRatio: 3 / 4,
    position: 'relative',
    backgroundColor: '#211e2f',
  },
  coverImg: {
    width: '100%',
    height: '100%',
  },
  placeholderCover: {
    width: '100%',
    height: '100%',
    backgroundColor: '#211e2f',
  },
  discountBadge: {
    position: 'absolute',
    bottom: 6,
    left: 6,
    backgroundColor: '#e02424',
    paddingHorizontal: 5,
    paddingVertical: 2,
    borderRadius: 4,
  },
  discountText: {
    color: '#fff',
    fontWeight: '800',
    fontSize: 10,
  },
  heartBtn: {
    position: 'absolute',
    top: 6,
    right: 6,
    width: 26,
    height: 26,
    borderRadius: 13,
    backgroundColor: 'rgba(14, 13, 19, 0.7)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  heartBtnActive: {
    backgroundColor: '#ff3366',
  },
  heartIcon: {
    color: '#fff',
    fontSize: 14,
  },
  cardInfo: {
    padding: 8,
  },
  cardTitle: {
    color: '#fff',
    fontSize: 12,
    fontWeight: '700',
    lineHeight: 16,
  },
  cardGenres: {
    color: '#6e6b7d',
    fontSize: 10,
    marginTop: 2,
  },
  priceRow: {
    flexDirection: 'row',
    alignItems: 'baseline',
    gap: 4,
    marginTop: 6,
  },
  basePrice: {
    color: '#6e6b7d',
    fontSize: 10,
    textDecorationLine: 'line-through',
  },
  finalPrice: {
    color: '#fff',
    fontSize: 12,
    fontWeight: '800',
  },
  bottomNav: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    height: 56,
    backgroundColor: '#13111b',
    borderTopWidth: 1,
    borderTopColor: 'rgba(255,255,255,0.08)',
    flexDirection: 'row',
    justifyContent: 'space-around',
    alignItems: 'center',
  },
  navBtn: {
    padding: 8,
  },
  navBtnActive: {},
  navText: {
    color: '#6e6b7d',
    fontSize: 12,
    fontWeight: '600',
  },
  navTextActive: {
    color: '#8a3ffc',
    fontWeight: '800',
  },
  center: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.7)',
    justifyContent: 'flex-end',
  },
  modalContent: {
    backgroundColor: '#171520',
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    maxHeight: '80%',
    overflow: 'hidden',
  },
  modalBanner: {
    width: '100%',
    height: 160,
  },
  closeBtn: {
    position: 'absolute',
    top: 12,
    right: 12,
    zIndex: 10,
    backgroundColor: 'rgba(0,0,0,0.6)',
    width: 28,
    height: 28,
    borderRadius: 14,
    justifyContent: 'center',
    alignItems: 'center',
  },
  closeBtnText: {
    color: '#fff',
    fontWeight: '700',
  },
  modalScroll: {
    padding: 16,
  },
  modalTitle: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '800',
    marginBottom: 6,
  },
  drmFreeBadge: {
    color: '#00e676',
    fontSize: 11,
    fontWeight: '700',
    marginBottom: 16,
  },
  modalPriceBox: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    backgroundColor: '#1c1926',
    padding: 12,
    borderRadius: 8,
    marginBottom: 12,
  },
  modalPriceLabel: {
    color: '#a3a1b0',
    fontSize: 10,
  },
  modalPriceVal: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '800',
  },
  buyBtn: {
    backgroundColor: '#8a3ffc',
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 20,
  },
  buyBtnText: {
    color: '#fff',
    fontWeight: '700',
    fontSize: 12,
  },
  securityNotice: {
    color: '#6e6b7d',
    fontSize: 11,
    lineHeight: 16,
    marginTop: 8,
  },
});
