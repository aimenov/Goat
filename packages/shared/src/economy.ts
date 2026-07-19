/**
 * Economy catalogs + wire shapes shared by server and client. This file is the
 * single source of truth for ids, RU strings, prices, and thresholds — the
 * client's fallback tables must match it EXACTLY.
 */

/** Soft currency: «капуста» — money slang and goat food at once. */
export const CURRENCY = { code: 'coins', ru: 'капуста', emoji: '🥬' } as const;

/* ------------------------------------------------------------------ *
 * Ranks (rating ladder)                                               *
 * ------------------------------------------------------------------ */

export type RankId =
  | 'kid'
  | 'young'
  | 'common'
  | 'scapegoat'
  | 'trump'
  | 'aristocrat'
  | 'professor'
  | 'seasoned';

export interface RankInfo {
  id: RankId;
  ru: string;
  emoji: string;
  /** Lowest rating that holds this rank (rating starts at 1000, floors at 100). */
  minRating: number;
}

/** Ascending by minRating — rank lookup takes the last entry ≤ rating. */
export const RANKS: RankInfo[] = [
  { id: 'kid', ru: 'Козлёнок', emoji: '🍼', minRating: 0 },
  { id: 'young', ru: 'Молодой козлик', emoji: '🌱', minRating: 900 },
  { id: 'common', ru: 'Козёл обыкновенный', emoji: '🐐', minRating: 1000 },
  { id: 'scapegoat', ru: 'Козёл отпущения', emoji: '🙃', minRating: 1100 },
  { id: 'trump', ru: 'Козырный козёл', emoji: '🃏', minRating: 1250 },
  { id: 'aristocrat', ru: 'Козёл-аристократ', emoji: '🎩', minRating: 1400 },
  { id: 'professor', ru: 'Козёл-профессор', emoji: '🎓', minRating: 1550 },
  { id: 'seasoned', ru: 'Матёрый козёл', emoji: '🔥', minRating: 1750 },
];

/* ------------------------------------------------------------------ *
 * Daily bonus                                                         *
 * ------------------------------------------------------------------ */

/** Streak day 1..7+ → 🥬 amount (day 8 and beyond keep the last value). */
export const DAILY_BONUS = [10, 15, 20, 25, 30, 40, 50] as const;

/* ------------------------------------------------------------------ *
 * Cosmetics                                                           *
 * ------------------------------------------------------------------ */

export type CosmeticSlot = 'cardBack' | 'felt';

export interface CosmeticItem {
  id: string;
  slot: CosmeticSlot;
  ru: string;
  /** 🥬 price; 0 for defaults and premium (IAP-only) items. */
  price: number;
  /** Premium items are never coin-purchasable — IAP grants only. */
  premium: boolean;
  isDefault: boolean;
}

export const COSMETICS: CosmeticItem[] = [
  { id: 'back_classic', slot: 'cardBack', ru: 'Классика', price: 0, premium: false, isDefault: true },
  { id: 'back_cabbage', slot: 'cardBack', ru: 'Капустная грядка', price: 150, premium: false, isDefault: false },
  { id: 'back_burgundy', slot: 'cardBack', ru: 'Бордовый бархат', price: 250, premium: false, isDefault: false },
  { id: 'back_midnight', slot: 'cardBack', ru: 'Полночь', price: 250, premium: false, isDefault: false },
  { id: 'back_ivory', slot: 'cardBack', ru: 'Слоновая кость', price: 250, premium: false, isDefault: false },
  { id: 'back_golden_goat', slot: 'cardBack', ru: 'Золотой козёл', price: 0, premium: true, isDefault: false },
  { id: 'felt_classic', slot: 'felt', ru: 'Классическое сукно', price: 0, premium: false, isDefault: true },
  { id: 'felt_burgundy', slot: 'felt', ru: 'Бордовый бархат', price: 400, premium: false, isDefault: false },
  { id: 'felt_midnight', slot: 'felt', ru: 'Полночь', price: 400, premium: false, isDefault: false },
  { id: 'felt_cabbage', slot: 'felt', ru: 'Капустная грядка', price: 0, premium: true, isDefault: false },
];

/* ------------------------------------------------------------------ *
 * IAP products                                                        *
 * ------------------------------------------------------------------ */

export interface IapGrants {
  coins?: number;
  removeAds?: boolean;
  cosmeticId?: string;
}

export interface IapProduct {
  productId: string;
  grants: IapGrants;
}

export const IAP_PRODUCTS: IapProduct[] = [
  { productId: 'goat.remove_ads', grants: { removeAds: true } },
  { productId: 'goat.coins.small', grants: { coins: 500 } },
  { productId: 'goat.coins.medium', grants: { coins: 1500 } },
  { productId: 'goat.coins.large', grants: { coins: 4000 } },
  { productId: 'goat.cardback.golden', grants: { cosmeticId: 'back_golden_goat' } },
  { productId: 'goat.table.cabbage', grants: { cosmeticId: 'felt_cabbage' } },
];

/* ------------------------------------------------------------------ *
 * Daily quests («Задания дня»)                                        *
 * ------------------------------------------------------------------ */

export type QuestId =
  | 'play_3'
  | 'play_5'
  | 'win_1'
  | 'win_2'
  | 'streak_2'
  | 'triple_deal'
  | 'take_120'
  | 'shoha_ace'
  | 'comeback_win'
  | 'clean_win'
  | 'play_4p'
  | 'no_goat_3';

export interface QuestDef {
  id: QuestId;
  ru: string;
  target: number;
  /** 🥬 auto-credited the moment the quest completes (no claim step). */
  reward: number;
}

export const QUESTS: Record<QuestId, QuestDef> = {
  play_3: { id: 'play_3', ru: 'Сыграй 3 партии', target: 3, reward: 20 },
  win_1: { id: 'win_1', ru: 'Выиграй партию', target: 1, reward: 20 },
  play_4p: { id: 'play_4p', ru: 'Сыграй партию вчетвером или больше', target: 1, reward: 25 },
  clean_win: { id: 'clean_win', ru: 'Выиграй, не набрав ни одного очка', target: 1, reward: 30 },
  win_2: { id: 'win_2', ru: 'Выиграй 2 партии', target: 2, reward: 35 },
  play_5: { id: 'play_5', ru: 'Сыграй 5 партий', target: 5, reward: 35 },
  no_goat_3: { id: 'no_goat_3', ru: '3 партии подряд не козёл', target: 3, reward: 35 },
  streak_2: { id: 'streak_2', ru: 'Выиграй 2 партии подряд', target: 2, reward: 40 },
  triple_deal: { id: 'triple_deal', ru: 'Выиграй тройную раздачу', target: 1, reward: 40 },
  comeback_win: { id: 'comeback_win', ru: 'Переподключись и выиграй', target: 1, reward: 40 },
  take_120: { id: 'take_120', ru: 'Забери все 120 очков в раздаче', target: 1, reward: 50 },
  shoha_ace: { id: 'shoha_ace', ru: 'Убей козырного туза шохой', target: 1, reward: 50 },
};

/* ------------------------------------------------------------------ *
 * Wire shapes                                                         *
 * ------------------------------------------------------------------ */

/** Per-game 🥬 earnings, itemized for the rewards block. */
export interface CoinBreakdown {
  base: number;
  margin: number;
  flagBonus: number;
  streakBonus: number;
  questBonus: number;
  total: number;
}

/** One rendered line of the rewards breakdown — the client shows `ru` verbatim. */
export interface RewardLine {
  ru: string;
  amount: number;
}

export interface QuestProgressView {
  id: QuestId;
  ru: string;
  progress: number;
  target: number;
  completed: boolean;
}
