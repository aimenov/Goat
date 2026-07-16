import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:goat_app/core/cards.dart';
import 'package:goat_app/features/auth/login_screen.dart';
import 'package:goat_app/features/game/selection.dart';
import 'package:goat_app/shared/cards/card_face.dart';

void main() {
  group('CardFace', () {
    // Ranks, suit glyphs and pips are painted by [CardFacePainter] (vector
    // paths + serif TextPainter), so the tests assert on the painter that
    // carries the card id instead of text widgets.
    Finder facePainterFor(int card) => find.byWidgetPredicate(
          (w) =>
              w is CustomPaint &&
              w.painter is CardFacePainter &&
              (w.painter! as CardFacePainter).card == card,
        );

    testWidgets('renders the painted face for 10♠', (tester) async {
      // Card 7: suit 0 (♠), rank index 7 ('10').
      expect(cardName(7), '10♠');
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: CardFace(card: 7))),
      );
      expect(facePainterFor(7), findsOneWidget);
    });

    testWidgets('marks the шоха (6♣) with a ribbon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: CardFace(card: shoha))),
      );
      expect(find.text('ШОХА'), findsOneWidget);
      expect(facePainterFor(shoha), findsOneWidget);
    });
  });

  testWidgets('login screen shows nickname field and play button', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Играть'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  group('isValidLeadSelection', () {
    test('same rank is valid', () {
      // 6♠, 6♣, 6♦
      expect(isValidLeadSelection([0, 9, 18]), isTrue);
    });

    test('same suit is valid', () {
      // 6♠, 9♠, 10♠
      expect(isValidLeadSelection([0, 3, 7]), isTrue);
    });

    test('single card is valid', () {
      expect(isValidLeadSelection([13]), isTrue);
    });

    test('mixed rank and suit is invalid', () {
      // 6♠ + 7♣: neither same rank nor same suit
      expect(isValidLeadSelection([0, 10]), isFalse);
    });

    test('empty selection is invalid', () {
      expect(isValidLeadSelection([]), isFalse);
    });
  });

  group('autoPairing', () {
    void expectValidMatching(Map<int, List<int>> matrix, Map<int, int>? result) {
      expect(result, isNotNull);
      expect(result!.keys.toSet(), matrix.keys.toSet());
      expect(result.values.toSet().length, result.length,
          reason: 'beating cards must be distinct');
      for (final entry in result.entries) {
        expect(matrix[entry.key], contains(entry.value));
      }
    }

    test('simple one-to-one assignment', () {
      final matrix = {
        10: [20],
        11: [21],
      };
      expectValidMatching(matrix, autoPairing(matrix));
    });

    test('greedy first-choice fails but backtracking succeeds', () {
      // In insertion order: 10 -> 1, 11 -> 2 leaves 12 with nothing
      // (both 2 and 1 taken); a valid matching exists: 10->1, 11->3, 12->2.
      final matrix = {
        10: [1, 2],
        11: [2, 3],
        12: [2, 1],
      };
      expectValidMatching(matrix, autoPairing(matrix));
    });

    test('unsolvable matrix returns null', () {
      expect(
        autoPairing({
          10: [1],
          11: [1],
        }),
        isNull,
      );
    });

    test('target with no candidates returns null', () {
      expect(
        autoPairing({
          10: [1, 2],
          11: [],
        }),
        isNull,
      );
    });

    test('empty matrix yields empty pairing', () {
      expect(autoPairing(<int, List<int>>{}), isEmpty);
    });
  });
}
