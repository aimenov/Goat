/// Daily bonus sheet («Ежедневная капуста»): a 7-pill streak calendar with
/// the canonical amounts, a gold claim button and — after a claim the server
/// marks doublable — an optional rewarded-ad double slot.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/monetization/hooks.dart';
import '../../core/net/api.dart';
import '../../core/profile.dart';
import '../../core/services/sound.dart';
import '../../shared/theme/tokens.dart';
import '../../shared/widgets/gold_button.dart';

/// Canonical day-1..7+ amounts (packages/shared economy.ts mirror).
const List<int> dailyBonusAmounts = [10, 15, 20, 25, 30, 40, 50];

Future<void> showDailyBonusSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Tokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Tokens.r20)),
    ),
    builder: (sheetContext) => const SafeArea(child: DailyBonusSheet()),
  );
}

class DailyBonusSheet extends ConsumerStatefulWidget {
  const DailyBonusSheet({super.key});

  @override
  ConsumerState<DailyBonusSheet> createState() => _DailyBonusSheetState();
}

class _DailyBonusSheetState extends ConsumerState<DailyBonusSheet> {
  bool _busy = false;

  /// Set after a successful claim when the server allows an ad double —
  /// the sheet stays open showing the double slot instead of popping.
  DailyClaimResult? _claimed;

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _claim() async {
    setState(() => _busy = true);
    try {
      final result = await ref.read(profileProvider.notifier).claimDaily();
      if (!mounted) return;
      if (result == null) {
        Navigator.pop(context); // older server: feature absent
        return;
      }
      ref.read(soundServiceProvider).play(Sfx.achievementBell);
      final hook = ref.read(rewardedAdHookProvider);
      if (hook != null && result.canDouble) {
        setState(() => _claimed = result); // offer the double before closing
      } else {
        Navigator.pop(context);
        _snack('+${result.amount} 🥬');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _snack('$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _watchAd(DailyClaimResult claimed) async {
    final hook = ref.read(rewardedAdHookProvider);
    if (hook == null) return;
    setState(() => _busy = true);
    try {
      final watched = await hook.show('doubleDaily');
      if (!watched || !mounted) return;
      final granted =
          await ref.read(profileProvider.notifier).doubleReward('doubleDaily');
      if (!mounted) return;
      Navigator.pop(context);
      _snack(granted ? '+${claimed.amount} 🥬' : 'Не получилось удвоить');
    } catch (_) {
      if (!mounted) return;
      Navigator.pop(context);
      _snack('Не получилось удвоить');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value ?? const PlayerProfile();
    final claimed = _claimed;
    // Today's pill. The server's nextClaimStreak is authoritative — it knows
    // a lapsed streak resets to day 1, which dailyStreak alone over-promises.
    // Fallbacks (older server / after claiming): derive from dailyStreak.
    final todayIndex = claimed != null
        ? (claimed.streak - 1).clamp(0, dailyBonusAmounts.length - 1)
        : profile.dailyClaimable
            ? (profile.nextClaimStreak > 0
                    ? profile.nextClaimStreak - 1
                    : profile.dailyStreak)
                .clamp(0, dailyBonusAmounts.length - 1)
            : (profile.dailyStreak - 1).clamp(0, dailyBonusAmounts.length - 1);
    final amount = dailyBonusAmounts[todayIndex];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Ежедневная капуста', style: Tokens.titleSerif),
          const SizedBox(height: 4),
          const Text(
            'Заходите каждый день — капусты будет больше',
            style: TextStyle(fontSize: 12, color: Tokens.textSecondary),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (final (i, pillAmount) in dailyBonusAmounts.indexed)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _pill(
                      day: i + 1,
                      amount: pillAmount,
                      passed: i < todayIndex,
                      today: i == todayIndex,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (claimed == null)
            GoldButton(
              onPressed: _busy || !profile.dailyClaimable ? null : _claim,
              child: Text(
                profile.dailyClaimable
                    ? 'Забрать $amount 🥬'
                    : 'Уже получено сегодня',
              ),
            )
          else ...[
            Text(
              '+${claimed.amount} 🥬 получено!',
              textAlign: TextAlign.center,
              style: Tokens.numeric.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Tokens.gold200,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.ondemand_video, size: 18),
              label: Text('Удвоить: ещё +${claimed.amount} 🥬 за рекламу'),
              onPressed: _busy ? null : () => _watchAd(claimed),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      Navigator.pop(context);
                      _snack('+${claimed.amount} 🥬');
                    },
              child: const Text('Закрыть'),
            ),
          ],
        ],
      ),
    );
  }

  /// One calendar pill: day label + amount; today glows gold, passed days
  /// show a check, future days stay faint.
  Widget _pill({
    required int day,
    required int amount,
    required bool passed,
    required bool today,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: today
            ? Tokens.gold400.withValues(alpha: 0.18)
            : Tokens.felt900.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(Tokens.r10),
        border: Border.all(
          color: today
              ? Tokens.gold300
              : Tokens.gold600.withValues(alpha: passed ? 0.5 : 0.25),
          width: today ? 1.4 : 0.8,
        ),
      ),
      child: Column(
        children: [
          Text(
            day >= dailyBonusAmounts.length ? '$day+' : '$day',
            style: TextStyle(
              fontSize: 10,
              color: today ? Tokens.gold200 : Tokens.textFaint,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: passed
                ? const Text(
                    '✓',
                    style: TextStyle(fontSize: 12, color: Tokens.success),
                  )
                : Text(
                    '$amount',
                    style: Tokens.numeric.copyWith(
                      fontSize: 12,
                      color: today ? Tokens.gold100 : Tokens.textSecondary,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
