/// The player's economy profile (капуста, rating, quests, cosmetics) as an
/// app-wide [AsyncNotifier]. All grants are server-authoritative; this
/// controller only fetches, merges server responses and applies optimistic
/// updates that the next refresh reconciles.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'game/models.dart';
import 'net/api.dart';
import 'session.dart';

class ProfileController extends AsyncNotifier<PlayerProfile> {
  @override
  Future<PlayerProfile> build() async {
    final identity = await ref.watch(identityProvider.future);
    if (identity == null) return const PlayerProfile();
    try {
      return await ref.read(apiProvider).profile(identity.playerId);
    } catch (_) {
      // Server unreachable: an empty profile keeps every economy surface
      // dormant instead of erroring the lobby.
      return const PlayerProfile();
    }
  }

  PlayerProfile get _current => state.value ?? const PlayerProfile();

  /// Re-fetches; a failed fetch keeps the last good data on screen.
  Future<void> refresh() async {
    final identity = ref.read(identityProvider).value;
    if (identity == null) {
      state = const AsyncData(PlayerProfile());
      return;
    }
    final next = await AsyncValue.guard(
      () => ref.read(apiProvider).profile(identity.playerId),
    );
    if (next.hasError && state.hasValue) return;
    state = next;
  }

  /// Claims today's daily bonus and merges the result. Null when signed out
  /// or the server predates the economy.
  Future<DailyClaimResult?> claimDaily() async {
    final identity = ref.read(identityProvider).value;
    if (identity == null) return null;
    final result = await ref.read(apiProvider).claimDaily(identity.token);
    if (result == null) return null;
    state = AsyncData(_current.copyWith(
      coins: result.coins,
      dailyStreak: result.streak,
      dailyClaimable: false,
    ));
    return result;
  }

  /// Buys a cosmetic; the server answers with the new balance + owned set.
  /// Null when signed out or the server predates the economy.
  Future<PurchaseResult?> purchase(String itemId) async {
    final identity = ref.read(identityProvider).value;
    if (identity == null) return null;
    final result = await ref.read(apiProvider).purchase(identity.token, itemId);
    if (result == null) return null;
    state = AsyncData(_current.copyWith(
      coins: result.coins,
      ownedCosmetics: result.owned.isEmpty ? null : result.owned,
    ));
    return result;
  }

  /// Equips a cosmetic optimistically (instant re-skin); reverts on error.
  Future<void> equip(String itemId) async {
    final identity = ref.read(identityProvider).value;
    if (identity == null) return;
    final before = _current.equipped;
    final optimistic = itemId.startsWith('felt_')
        ? before.copyWith(felt: itemId)
        : before.copyWith(cardBack: itemId);
    state = AsyncData(_current.copyWith(equipped: optimistic));
    try {
      final result = await ref.read(apiProvider).equip(identity.token, itemId);
      if (result != null) state = AsyncData(_current.copyWith(equipped: result));
    } catch (_) {
      state = AsyncData(_current.copyWith(equipped: before));
      rethrow;
    }
  }

  /// Redeems a watched rewarded ad ([kind]: 'doubleGame' | 'doubleDaily');
  /// merges the granted coins. Returns whether the double was granted.
  Future<bool> doubleReward(String kind) async {
    final identity = ref.read(identityProvider).value;
    if (identity == null) return false;
    final result = await ref.read(apiProvider).adReward(identity.token, kind);
    if (result == null || result.granted <= 0) return false;
    state = AsyncData(_current.copyWith(coins: result.coins));
    return true;
  }

  /// Optimistic merge of a `gameRewards` event: coins add up, rating is the
  /// server's new absolute value, quest ticks merge by id. The next
  /// [refresh] reconciles with the authoritative profile.
  void applyGameRewards(GameRewards rewards) {
    if (rewards.anonymous) return;
    final p = _current;
    final quests = [...p.quests];
    for (final tick in rewards.questProgress) {
      final i = quests.indexWhere((q) => q.id == tick.id);
      final updated = QuestState(
        id: tick.id,
        ru: tick.ru.isNotEmpty ? tick.ru : (i >= 0 ? quests[i].ru : ''),
        progress: tick.progress,
        target: tick.target,
        reward: i >= 0 ? quests[i].reward : 0,
        claimed: tick.completed,
      );
      if (i >= 0) {
        quests[i] = updated;
      } else {
        quests.add(updated);
      }
    }
    state = AsyncData(p.copyWith(
      coins: p.coins + rewards.coins,
      rating: rewards.rating,
      rankId: rewards.rankId ?? p.rankId,
      quests: quests,
    ));
  }
}

final profileProvider =
    AsyncNotifierProvider<ProfileController, PlayerProfile>(ProfileController.new);
