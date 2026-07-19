/// Game-end rewards panel inside the game-over overlay: капуста count-up,
/// the server's RU breakdown verbatim, rating delta, a client-detected
/// rank-up chip and quest ticks. Pure widget — no providers, no network —
/// so it drops straight into widget tests.
library;

import 'package:flutter/material.dart';

import '../../core/game/models.dart';
import '../../shared/theme/tokens.dart';
import '../../shared/widgets/brass_chip.dart';
import '../economy/ranks.dart';
import 'anim/motion_widgets.dart';

class GameRewardsBlock extends StatelessWidget {
  const GameRewardsBlock({super.key, required this.rewards, this.onDoubleAd});

  final GameRewards rewards;

  /// Null hides the ad button (no hook, removeAds bought, or not doublable).
  final VoidCallback? onDoubleAd;

  @override
  Widget build(BuildContext context) {
    if (rewards.anonymous) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 4),
        child: Text('Войдите, чтобы копить капусту', style: Tokens.caption),
      );
    }
    final empty = rewards.coins == 0 &&
        rewards.ratingDelta == 0 &&
        rewards.breakdown.isEmpty &&
        rewards.questProgress.isEmpty;
    if (empty) return const SizedBox.shrink();

    // Client-side band-crossing check: the rank-up chip never depends on the
    // server naming the rank (older payloads may omit it).
    final rankBefore = rankForRating(rewards.rating - rewards.ratingDelta);
    final rankNow = rankForRating(rewards.rating);
    final rankUp = rewards.ratingDelta > 0 && !identical(rankBefore, rankNow);

    // The panel animates for ~2 s; the boundary keeps those repaints off the
    // rest of the game-over overlay.
    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (rewards.coins != 0)
            CountUpText(
              value: rewards.coins,
              prefix: '+',
              suffix: ' 🥬',
              delay: const Duration(milliseconds: 200),
              duration: const Duration(milliseconds: 700),
              style: Tokens.numeric.copyWith(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Tokens.gold200,
              ),
            ),
          if (rewards.breakdown.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final (i, line) in rewards.breakdown.indexed)
              SlideFadeIn(
                delay: Duration(milliseconds: 300 + 90 * i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          line.ru, // server RU shown verbatim
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Tokens.textSecondary,
                          ),
                        ),
                      ),
                      Text(
                        '+${line.amount}',
                        style: Tokens.numeric.copyWith(
                          fontSize: 12,
                          color: Tokens.gold100,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          if (rewards.ratingDelta != 0) ...[
            const SizedBox(height: 8),
            SlideFadeIn(
              delay: const Duration(milliseconds: 500),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Рейтинг: ${rewards.rating}',
                    style: Tokens.numeric.copyWith(
                      fontSize: 13,
                      color: Tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(
                      color: (rewards.ratingDelta > 0
                              ? Tokens.success
                              : Tokens.danger)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      rewards.ratingDelta > 0
                          ? '+${rewards.ratingDelta}'
                          : '−${-rewards.ratingDelta}',
                      style: Tokens.numeric.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: rewards.ratingDelta > 0
                            ? Tokens.success
                            : Tokens.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (rankUp) ...[
            const SizedBox(height: 8),
            PunchIn(
              delay: const Duration(milliseconds: 700),
              // Scale-down: the longest rank names must shrink on narrow
              // panels instead of overflowing the chip row.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: BrassChip(
                  text: 'Новое звание: ${rankNow.emoji} ${rankNow.ru}!',
                ),
              ),
            ),
          ],
          if (rewards.questProgress.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final (i, tick) in rewards.questProgress.take(3).indexed)
              SlideFadeIn(
                delay: Duration(milliseconds: 650 + 90 * i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (tick.completed) ...[
                        const Text(
                          '✓',
                          style: TextStyle(fontSize: 11, color: Tokens.success),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          '${tick.ru} — ${tick.progress}/${tick.target}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Tokens.caption.copyWith(
                            color: tick.completed
                                ? Tokens.success
                                : Tokens.textFaint,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          if (onDoubleAd != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.ondemand_video, size: 18),
              label: const Text('Удвоить 🥬 за рекламу'),
              onPressed: onDoubleAd,
            ),
          ],
        ],
      ),
    );
  }
}
