/// «Задания дня» sheet: the three daily quests with progress bars. Purely
/// display — rewards auto-credit server-side at game end and appear in the
/// game-over breakdown as «Задание дня».
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api.dart';
import '../../core/profile.dart';
import '../../shared/theme/tokens.dart';
import '../../shared/widgets/brass_chip.dart';
import 'quests.dart';

Future<void> showQuestsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Tokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Tokens.r20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Consumer(
        builder: (context, ref, _) => QuestsSheetBody(
          quests: ref.watch(profileProvider).value?.quests ?? const [],
        ),
      ),
    ),
  );
}

/// Pure body — testable without providers.
class QuestsSheetBody extends StatelessWidget {
  const QuestsSheetBody({super.key, required this.quests});

  final List<QuestState> quests;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Задания дня', style: Tokens.titleSerif),
          const SizedBox(height: 12),
          if (quests.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Заданий пока нет — сыграйте партию!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Tokens.textSecondary),
              ),
            )
          else
            for (final quest in quests.take(3)) _questCard(quest),
          const SizedBox(height: 8),
          const Text(
            'Новые задания — завтра',
            textAlign: TextAlign.center,
            style: Tokens.caption,
          ),
        ],
      ),
    );
  }

  Widget _questCard(QuestState quest) {
    final done = quest.completed;
    // The profile payload has no reward field — fall back to the mirror.
    final reward = quest.reward > 0 ? quest.reward : questRewards[quest.id] ?? 0;
    final progress = quest.target <= 0
        ? 0.0
        : (quest.progress / quest.target).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Tokens.surfaceHigh,
        borderRadius: BorderRadius.circular(Tokens.r14),
        border: Border.all(
          color: done
              ? Tokens.gold400
              : Tokens.gold600.withValues(alpha: 0.35),
          width: done ? 1.2 : 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  quest.ru,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Tokens.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (reward > 0) BrassChip(text: '+$reward 🥬'),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: done ? 1 : progress,
              minHeight: 5,
              backgroundColor: Tokens.felt900,
              color: Tokens.gold300,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            done ? 'Выполнено ✓' : '${quest.progress}/${quest.target}',
            style: Tokens.caption.copyWith(
              color: done ? Tokens.success : Tokens.textFaint,
            ),
          ),
        ],
      ),
    );
  }
}
