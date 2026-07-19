/// Pure-widget tests for the shop grids: tile states (Выбрано / Куплено /
/// price / premium), tap routing to the right callback, and — critically —
/// that every preview paints with its OWN catalog style, not the equipped one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:goat_app/core/net/api.dart';
import 'package:goat_app/features/shop/cosmetics_catalog.dart';
import 'package:goat_app/features/shop/shop_screen.dart';
import 'package:goat_app/shared/cards/card_face.dart';
import 'package:goat_app/shared/felt/felt_background.dart';

Future<void> pumpShop(
  WidgetTester tester, {
  required PlayerProfile profile,
  void Function(CosmeticItem)? onBuy,
  void Function(CosmeticItem)? onEquip,
  void Function(CosmeticItem)? onPremiumTap,
}) async {
  // Tall viewport: both grids (6 backs + 4 felts) must actually build —
  // ListView builds lazily and the felt section sits below the fold at 600.
  tester.view.physicalSize = const Size(1000, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ShopBody(
          profile: profile,
          onBuy: onBuy,
          onEquip: onEquip,
          onPremiumTap: onPremiumTap,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('fresh profile: defaults equipped, prices and premium labels',
      (tester) async {
    await pumpShop(tester, profile: const PlayerProfile());

    // Both defaults (back_classic + felt_classic) read as equipped.
    expect(find.text('Выбрано'), findsNWidgets(2));
    expect(find.text('Куплено'), findsNothing);
    expect(find.text('150 🥬'), findsOneWidget); // back_cabbage
    expect(find.text('250 🥬'), findsNWidgets(3)); // burgundy/midnight/ivory
    expect(find.text('400 🥬'), findsNWidgets(2)); // felt burgundy/midnight
    // Both premium items are $1.49-tier products → same ₽ teaser label.
    expect(find.text('👑 149 ₽'), findsNWidgets(2)); // back_golden_goat + felt_cabbage
  });

  testWidgets('owned + equipped states follow the profile', (tester) async {
    await pumpShop(
      tester,
      profile: const PlayerProfile(
        ownedCosmetics: {'back_burgundy', 'felt_midnight'},
        equipped: EquippedCosmetics(cardBack: 'back_burgundy'),
      ),
    );

    // Equipped: burgundy back + the default felt (still classic).
    expect(find.text('Выбрано'), findsNWidgets(2));
    // Owned but not equipped: back_classic (default), felt_midnight (bought).
    expect(find.text('Куплено'), findsNWidgets(2));
    // felt_midnight no longer shows its price; felt_burgundy still does.
    expect(find.text('400 🥬'), findsOneWidget);
  });

  testWidgets('taps route to buy / equip / premium by tile state',
      (tester) async {
    final bought = <String>[];
    final equipped = <String>[];
    final premium = <String>[];
    await pumpShop(
      tester,
      profile: const PlayerProfile(ownedCosmetics: {'back_midnight'}),
      onBuy: (item) => bought.add(item.id),
      onEquip: (item) => equipped.add(item.id),
      onPremiumTap: (item) => premium.add(item.id),
    );

    await tester.tap(find.text('150 🥬')); // priced → buy
    await tester.tap(find.text('Куплено')); // owned → equip (back_midnight)
    await tester.tap(find.text('👑 149 ₽').first); // premium → store flow
    await tester.tap(find.text('Выбрано').first); // equipped → no-op
    await tester.pump();

    expect(bought, ['back_cabbage']);
    expect(equipped, ['back_midnight']);
    expect(premium, ['back_golden_goat']);
  });

  testWidgets('previews paint their own catalog styles, not the equipped one',
      (tester) async {
    await pumpShop(
      tester,
      profile: const PlayerProfile(
        equipped: EquippedCosmetics(
          cardBack: 'back_midnight',
          felt: 'felt_burgundy',
        ),
      ),
    );

    final backIds = [
      for (final paint in tester.widgetList<CustomPaint>(find.byType(CustomPaint)))
        if (paint.painter is LatticePainter)
          (paint.painter as LatticePainter).style.id,
    ];
    expect(backIds, [for (final item in cardBackItems) item.id]);

    final feltIds = [
      for (final paint in tester.widgetList<CustomPaint>(find.byType(CustomPaint)))
        if (paint.painter is FeltPainter)
          (paint.painter as FeltPainter).theme.id,
    ];
    expect(feltIds, [for (final item in feltItems) item.id]);

    // The card-back previews are the real widget at the canonical size.
    expect(
      tester.widgetList<CardBack>(find.byType(CardBack)).map((w) => w.height),
      everyElement(76),
    );
  });
}
