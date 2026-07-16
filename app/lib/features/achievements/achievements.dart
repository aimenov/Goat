/// The 12 achievement definitions — a Dart mirror of the server's
/// packages/server/src/meta/achievements.ts. Ids must match the server;
/// titles/descriptions are the client-side RU presentation.
library;

class AchievementDef {
  final String id;
  final String emoji;
  final String title;
  final String description;

  const AchievementDef({
    required this.id,
    required this.emoji,
    required this.title,
    required this.description,
  });
}

const List<AchievementDef> achievementDefs = [
  AchievementDef(
    id: 'first_win',
    emoji: '🎉',
    title: 'Сегодня не козёл',
    description: 'Выиграйте первую партию — пусть козлом будет кто-то другой',
  ),
  AchievementDef(
    id: 'wins_10',
    emoji: '🐐',
    title: 'Вожак стада',
    description: 'Одержите 10 побед',
  ),
  AchievementDef(
    id: 'wins_100',
    emoji: '👑',
    title: 'Крёстный козёл',
    description: 'Одержите 100 побед',
  ),
  AchievementDef(
    id: 'shoha_ace',
    emoji: '♣️',
    title: 'Шоха всему голова',
    description: 'Побейте козырного туза шохой — шестёркой треф',
  ),
  AchievementDef(
    id: 'full_120',
    emoji: '💰',
    title: 'Гребёт копытами',
    description: 'Заберите все 120 очков за одну раздачу',
  ),
  AchievementDef(
    id: 'triple_win',
    emoji: '⚡',
    title: 'Три шкуры',
    description: 'Возьмите раздачу с множителем ×3 и выиграйте партию',
  ),
  AchievementDef(
    id: 'exact_limit',
    emoji: '🎓',
    title: 'Дипломированный козёл',
    description: 'Станьте козлом, набрав ровно лимит очков — ни больше ни меньше',
  ),
  AchievementDef(
    id: 'instant_goat',
    emoji: '🏁',
    title: 'Козёл-экспресс',
    description: 'Проиграйте мгновенно по правилу 12:0',
  ),
  AchievementDef(
    id: 'comeback_win',
    emoji: '🔌',
    title: 'Блудный козёл',
    description: 'Переподключитесь посреди партии и всё равно победите',
  ),
  AchievementDef(
    id: 'games_100',
    emoji: '🛖',
    title: 'Завсегдатай хлева',
    description: 'Сыграйте 100 партий',
  ),
  AchievementDef(
    id: 'streak_5',
    emoji: '🔥',
    title: 'Горячие копыта',
    description: 'Выиграйте 5 партий подряд',
  ),
  AchievementDef(
    id: 'zero_hero',
    emoji: '🫥',
    title: 'Рожки да ножки',
    description: 'Станьте козлом, не взяв ни одной взятки за всю партию',
  ),
];

AchievementDef? achievementById(String id) {
  for (final def in achievementDefs) {
    if (def.id == id) return def;
  }
  return null;
}
