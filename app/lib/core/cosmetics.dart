/// Which cosmetics are actually painted right now. Resolution order:
/// classic synchronously (first frame never waits), then the SharedPreferences
/// id cache (last session's look before the profile loads), then the
/// server-authoritative `profile.equipped` — which also refreshes the cache.
/// Unknown ids are ignored, so a newer server never breaks an older client.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/theme/cosmetic_styles.dart';
import 'profile.dart';

class SelectedCosmetics {
  final CardBackStyle cardBack;
  final FeltTheme felt;

  const SelectedCosmetics({
    this.cardBack = CardBackStyle.classic,
    this.felt = FeltTheme.classic,
  });
}

class CosmeticsController extends Notifier<SelectedCosmetics> {
  static const _backKey = 'cosmetic.back';
  static const _feltKey = 'cosmetic.felt';

  /// Set once anything authoritative lands (profile adoption or an explicit
  /// [select]); the async prefs cache then keeps its hands off.
  bool _touched = false;

  @override
  SelectedCosmetics build() {
    ref.listen(profileProvider, (_, next) {
      final equipped = next.value?.equipped;
      if (equipped != null) {
        _adopt(equipped.cardBack, equipped.felt, authoritative: true);
      }
    });
    // Profile already loaded (provider rebuilt late): adopt synchronously.
    final equipped = ref.read(profileProvider).value?.equipped;
    _loadCache();
    if (equipped != null) {
      _touched = true;
      return SelectedCosmetics(
        cardBack: CardBackStyle.byId(equipped.cardBack) ?? CardBackStyle.classic,
        felt: FeltTheme.byId(equipped.felt) ?? FeltTheme.classic,
      );
    }
    return const SelectedCosmetics();
  }

  /// Applies a catalog item immediately (shop equip taps go through the
  /// profile, whose update loops back here — this is the direct entry for
  /// callers without a server). Unknown ids are ignored.
  void select(String itemId) =>
      _adopt(itemId, itemId, authoritative: true);

  /// Adopts whichever of the two ids resolve; unresolved slots keep their
  /// current style. Authoritative adoptions also refresh the prefs cache.
  void _adopt(String backId, String feltId, {required bool authoritative}) {
    if (authoritative) _touched = true;
    final next = SelectedCosmetics(
      cardBack: CardBackStyle.byId(backId) ?? state.cardBack,
      felt: FeltTheme.byId(feltId) ?? state.felt,
    );
    if (identical(next.cardBack, state.cardBack) &&
        identical(next.felt, state.felt)) {
      return;
    }
    state = next;
    if (authoritative) _cache(next);
  }

  /// Async cache adoption; loses to any authoritative adoption that landed
  /// first. Failures are swallowed — cosmetics must never break startup.
  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final back = prefs.getString(_backKey);
      final felt = prefs.getString(_feltKey);
      if (_touched || (back == null && felt == null)) return;
      _adopt(back ?? '', felt ?? '', authoritative: false);
    } catch (_) {
      // No prefs (tests, exotic platforms): stay on the current styles.
    }
  }

  Future<void> _cache(SelectedCosmetics value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_backKey, value.cardBack.id);
      await prefs.setString(_feltKey, value.felt.id);
    } catch (_) {
      // Cache miss only costs the next launch its pre-profile skin.
    }
  }
}

final cosmeticsProvider =
    NotifierProvider<CosmeticsController, SelectedCosmetics>(
        CosmeticsController.new);
