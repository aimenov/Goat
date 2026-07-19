/// Lobby profile header — a brass plaque above the room list: rank disc,
/// nickname, rating, капуста, daily streak and the quests counter. Pure
/// widget: the lobby supplies the profile and tap callbacks.
library;

import 'package:flutter/material.dart';

import '../../core/net/api.dart';
import '../../shared/theme/tokens.dart';
import '../../shared/widgets/brass_chip.dart';
import '../economy/ranks.dart';

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.nickname,
    required this.profile,
    this.onCoins,
    this.onRating,
    this.onQuests,
  });

  final String nickname;
  final PlayerProfile profile;

  /// Taps: 🥬 chip → shop, rating chip → leaderboard, «Задания» → sheet.
  final VoidCallback? onCoins;
  final VoidCallback? onRating;
  final VoidCallback? onQuests;

  @override
  Widget build(BuildContext context) {
    final rank = rankForRating(profile.rating);
    final questsDone = profile.quests.where((q) => q.completed).length;
    final questsTotal = profile.quests.isEmpty ? 3 : profile.quests.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      // Brass plaque: raised surface with a double gold hairline (matches
      // the achievements stats plaque).
      child: Container(
        decoration: BoxDecoration(
          color: Tokens.surfaceHigh,
          borderRadius: BorderRadius.circular(Tokens.r14),
          border: Border.all(
            color: Tokens.gold400.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.all(2),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Tokens.r14 - 2),
            border: Border.all(
              color: Tokens.gold600.withValues(alpha: 0.4),
              width: 0.8,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Rank disc: felt circle with the rank emoji.
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Tokens.felt600,
                      border: Border.all(
                        color: Tokens.gold400.withValues(alpha: 0.7),
                        width: 1.2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      rank.emoji,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: Tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          rank.ru,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Tokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _tappable(
                    onTap: onRating,
                    child: BrassChip(text: '⭐ ${profile.rating}'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Scale-down instead of overflowing on very narrow viewports.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _tappable(
                      onTap: onCoins,
                      child: BrassChip(text: '🥬 ${profile.coins}'),
                    ),
                    const SizedBox(width: 8),
                    // Streak dims to a faint chip at zero.
                    Opacity(
                      opacity: profile.dailyStreak > 0 ? 1 : 0.45,
                      child: BrassChip(text: '🔥 ${profile.dailyStreak}'),
                    ),
                    const SizedBox(width: 8),
                    _tappable(
                      onTap: onQuests,
                      child: BrassChip(text: 'Задания $questsDone/$questsTotal'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tappable({required VoidCallback? onTap, required Widget child}) =>
      InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: child,
      );
}
