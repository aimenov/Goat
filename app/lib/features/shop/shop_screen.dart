/// The shop («Лавка», route /shop): cosmetic card backs and table felts.
/// [ShopScreen] is the connected shell (profile, dialogs, purchases);
/// [ShopBody] is a pure widget — testable without network or providers.
/// Every grant/spend is server-authoritative; the client only displays.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cosmetics.dart';
import '../../core/monetization.dart';
import '../../core/monetization/hooks.dart';
import '../../core/net/api.dart';
import '../../core/services/ads/ads_service.dart';
import '../../core/profile.dart';
import '../../core/services/sound.dart';
import '../../shared/cards/card_face.dart';
import '../../shared/felt/felt_background.dart';
import '../../shared/theme/cosmetic_styles.dart';
import '../../shared/theme/tokens.dart';
import '../../shared/widgets/brass_chip.dart';
import 'cosmetics_catalog.dart';

class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key});

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Fresh balance/owned set on entry; keeps last good data offline.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(profileProvider.notifier).refresh();
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Confirm dialog → server purchase → snackbar, auto-equip, bell.
  Future<void> _buy(CosmeticItem item) async {
    if (_busy) return;
    final coins =
        ref.read(profileProvider).value?.coins ?? 0;
    final affordable = coins >= item.price;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Купить «${item.ru}»?'),
        content: Text(
          affordable
              ? 'Цена: ${item.price} 🥬'
              : 'Не хватает капусты 🥬 — нужно ${item.price}, у вас $coins',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed:
                affordable ? () => Navigator.pop(dialogContext, true) : null,
            child: Text('Купить за ${item.price} 🥬'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(profileProvider.notifier).purchase(item.id);
      if (!mounted) return;
      if (result == null) {
        _snack('Лавка пока закрыта'); // older server: feature absent
        return;
      }
      ref.read(soundServiceProvider).play(Sfx.achievementBell);
      _snack('Куплено: «${item.ru}»!');
      await ref.read(profileProvider.notifier).equip(item.id); // auto-equip
    } catch (e) {
      if (mounted) _snack('$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _equip(CosmeticItem item) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(profileProvider.notifier).equip(item.id);
    } catch (e) {
      if (mounted) _snack('$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Premium item: store flow when the IAP hook is live, teaser otherwise.
  Future<void> _premium(CosmeticItem item) async {
    if (_busy) return;
    final hook = ref.read(iapHookProvider);
    final productId = item.productId;
    if (hook == null || productId == null) {
      _snack('Скоро в продаже');
      return;
    }
    setState(() => _busy = true);
    try {
      final bought = await hook.purchase(productId);
      // Redemption is server-side: re-fetch the authoritative owned set.
      if (bought) await ref.read(profileProvider.notifier).refresh();
    } catch (_) {
      if (mounted) _snack('Покупка не прошла');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value ?? const PlayerProfile();
    return FeltBackground(
      theme: ref.watch(cosmeticsProvider).felt,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Лавка'),
          actions: [
            // Live balance: rebuilds with every profile merge.
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: BrassChip(text: '🥬 ${profile.coins}', fontSize: 14),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ShopBody(
                profile: profile,
                onBuy: _buy,
                onEquip: _equip,
                onPremiumTap: _premium,
              ),
            ),
            _storeFooter(),
          ],
        ),
      ),
    );
  }

  /// Store-compliance footer, only on platforms with a live store/ads stack:
  /// «Восстановить покупки» (App Store guideline 3.1.1) and the UMP privacy
  /// options re-entry (GDPR consent withdrawal).
  Widget _storeFooter() {
    final iapHook = ref.watch(iapHookProvider);
    final ads = ref.watch(adsServiceProvider);
    if (iapHook == null && !ads.privacyOptionsRequired) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Wrap(
          alignment: WrapAlignment.center,
          children: [
            if (iapHook != null)
              TextButton(
                onPressed: _busy ? null : _restore,
                child: const Text('Восстановить покупки'),
              ),
            if (ads.privacyOptionsRequired)
              TextButton(
                onPressed: () => ads.showPrivacyOptionsForm(),
                child: const Text('Настройки конфиденциальности рекламы'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      await ref.read(monetizationProvider.notifier).restore();
      if (mounted) _snack('Покупки восстановлены');
    } catch (_) {
      if (mounted) _snack('Не удалось восстановить покупки');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// The catalog grids. Pure: state comes from [profile], intents go out
/// through the callbacks.
class ShopBody extends StatelessWidget {
  const ShopBody({
    super.key,
    required this.profile,
    this.onBuy,
    this.onEquip,
    this.onPremiumTap,
  });

  final PlayerProfile profile;
  final void Function(CosmeticItem item)? onBuy;
  final void Function(CosmeticItem item)? onEquip;
  final void Function(CosmeticItem item)? onPremiumTap;

  bool _owned(CosmeticItem item) =>
      item.isDefault || profile.ownedCosmetics.contains(item.id);

  bool _equipped(CosmeticItem item) =>
      profile.equipped.cardBack == item.id || profile.equipped.felt == item.id;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Рубашки карт'),
        const SizedBox(height: 8),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.78,
          children: [
            for (final item in cardBackItems)
              _tile(
                item: item,
                // Real painter preview — exactly what the table will show.
                preview: CardBack(
                  height: 76,
                  style: CardBackStyle.byId(item.id) ?? CardBackStyle.classic,
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        _sectionTitle('Сукно стола'),
        const SizedBox(height: 8),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.45,
          children: [
            for (final item in feltItems)
              _tile(item: item, preview: _feltSwatch(item)),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _sectionTitle(String text) => Text(text, style: Tokens.titleSerif);

  /// Real [FeltPainter] swatch (light pool + vignette). Fixed intrinsic size:
  /// the tile's FittedBox scales it, and an unconstrained expand would blow
  /// up inside it.
  Widget _feltSwatch(CosmeticItem item) => ClipRRect(
        borderRadius: BorderRadius.circular(Tokens.r10),
        child: CustomPaint(
          painter: FeltPainter(
            theme: FeltTheme.byId(item.id) ?? FeltTheme.classic,
          ),
          child: const SizedBox(width: 132, height: 80),
        ),
      );

  Widget _tile({required CosmeticItem item, required Widget preview}) {
    final equipped = _equipped(item);
    final owned = _owned(item);
    final VoidCallback? onTap;
    if (equipped) {
      onTap = null;
    } else if (owned) {
      onTap = onEquip == null ? null : () => onEquip!(item);
    } else if (item.premium) {
      onTap = onPremiumTap == null ? null : () => onPremiumTap!(item);
    } else {
      onTap = onBuy == null ? null : () => onBuy!(item);
    }
    return InkWell(
      borderRadius: BorderRadius.circular(Tokens.r14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Tokens.surfaceHigh.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(Tokens.r14),
          border: Border.all(
            color: equipped
                ? Tokens.gold300
                : Tokens.gold600.withValues(alpha: 0.35),
            width: equipped ? 2 : 0.8,
          ),
        ),
        child: Column(
          children: [
            // Shrinks the fixed-size preview instead of overflowing when the
            // grid tile lands smaller than its natural size.
            Expanded(
              child: Center(
                child: FittedBox(fit: BoxFit.scaleDown, child: preview),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.ru,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, child: _stateChip(item)),
          ],
        ),
      ),
    );
  }

  Widget _stateChip(CosmeticItem item) {
    if (_equipped(item)) {
      return const Text(
        'Выбрано',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Tokens.gold200,
        ),
      );
    }
    if (_owned(item)) {
      return const Text(
        'Куплено',
        style: TextStyle(fontSize: 11, color: Tokens.textSecondary),
      );
    }
    if (item.premium) {
      return Text(
        '👑 ${item.premiumLabel}',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Tokens.gold200,
        ),
      );
    }
    return BrassChip(text: '${item.price} 🥬', fontSize: 11);
  }
}
