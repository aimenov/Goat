/// The shop catalog — a display mirror of the canonical cosmetics list in
/// packages/shared economy.ts (ids, RU names, 🥬 prices). Prices here are for
/// DISPLAY only: the server is the authority on every purchase; a mismatch
/// costs a rejected confirm dialog, never капусту.
library;

/// One purchasable (or default) cosmetic.
class CosmeticItem {
  final String id;
  final String ru;

  /// 🥬 price; 0 = default item (always owned, never bought).
  final int price;

  /// Real-money item: bought through the store, never for капусту.
  final bool premium;

  /// Display price for premium items («199 ₽»); null otherwise.
  final String? premiumLabel;

  /// Store product id for premium items (goat.cardback.golden / …).
  final String? productId;

  const CosmeticItem({
    required this.id,
    required this.ru,
    this.price = 0,
    this.premium = false,
    this.premiumLabel,
    this.productId,
  });

  bool get isDefault => price == 0 && !premium;
}

/// Card backs, catalog order (matches [CardBackStyle.all]).
const List<CosmeticItem> cardBackItems = [
  CosmeticItem(id: 'back_classic', ru: 'Классика'),
  CosmeticItem(id: 'back_cabbage', ru: 'Капустная грядка', price: 150),
  CosmeticItem(id: 'back_burgundy', ru: 'Бордовый бархат', price: 250),
  CosmeticItem(id: 'back_midnight', ru: 'Полночь', price: 250),
  CosmeticItem(id: 'back_ivory', ru: 'Слоновая кость', price: 250),
  CosmeticItem(
    id: 'back_golden_goat',
    ru: 'Золотой козёл',
    premium: true,
    premiumLabel: '149 ₽',
    productId: 'goat.cardback.golden',
  ),
];

/// Table felts, catalog order (matches [FeltTheme.all]).
const List<CosmeticItem> feltItems = [
  CosmeticItem(id: 'felt_classic', ru: 'Классическое сукно'),
  CosmeticItem(id: 'felt_burgundy', ru: 'Бордовый бархат', price: 400),
  CosmeticItem(id: 'felt_midnight', ru: 'Полночь', price: 400),
  CosmeticItem(
    id: 'felt_cabbage',
    ru: 'Капустная грядка',
    premium: true,
    premiumLabel: '149 ₽',
    productId: 'goat.table.cabbage',
  ),
];
