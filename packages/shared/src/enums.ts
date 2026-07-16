/** Engine decision-point phases (auto phases never persist). */
export type Phase = 'TRICK_LEAD' | 'TRICK_RESPOND' | 'TRICK_LEADER_DECISION' | 'GAME_OVER';

export type ErrorCode =
  | 'NOT_YOUR_TURN'
  | 'WRONG_PHASE'
  | 'CARD_NOT_IN_HAND'
  | 'ILLEGAL_LEAD_SHAPE' // not all same rank / same suit
  | 'ILLEGAL_BEAT' // pairing invalid or a card fails to beat its target
  | 'WRONG_CARD_COUNT' // beat/discard must use exactly k cards
  | 'GAME_ALREADY_OVER'
  | 'RATE_LIMITED'
  | 'INVALID_PAYLOAD';

export const EMOJI_IDS = [
  'thumbs_up',
  'laugh',
  'shock',
  'goat',
  'fire',
  'cry',
  'thinking',
  'clap',
  'sleepy',
  'melt',
  'party',
  'devil',
] as const;
export type EmojiId = (typeof EMOJI_IDS)[number];

export const ACHIEVEMENT_IDS = [
  'first_win',
  'wins_10',
  'wins_100',
  'shoha_ace',
  'full_120',
  'triple_win',
  'exact_limit',
  'instant_goat',
  'comeback_win',
  'games_100',
  'streak_5',
  'zero_hero',
] as const;
export type AchievementId = (typeof ACHIEVEMENT_IDS)[number];
