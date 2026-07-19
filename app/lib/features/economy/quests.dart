/// Quest reward mirror — packages/shared/src/economy.ts QUESTS, id → 🥬.
/// The profile payload sends quest ru/progress/target but not the reward
/// (it auto-credits server-side); the sheet looks the price tag up here.
library;

const Map<String, int> questRewards = {
  'play_3': 20,
  'win_1': 20,
  'play_4p': 25,
  'clean_win': 30,
  'win_2': 35,
  'play_5': 35,
  'no_goat_3': 35,
  'streak_2': 40,
  'triple_deal': 40,
  'comeback_win': 40,
  'take_120': 50,
  'shoha_ace': 50,
};
