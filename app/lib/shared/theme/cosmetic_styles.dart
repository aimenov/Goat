/// Cosmetic palettes: card-back styles and table-felt themes. Pure const data
/// (a Dart mirror of the canonical catalog in packages/shared economy.ts) —
/// the painters take a style/theme instance and everything else resolves ids
/// through [CardBackStyle.byId] / [FeltTheme.byId]. Const canonicalization
/// makes `identical()` the cheap equality the painters use in shouldRepaint.
library;

import 'dart:ui';

import 'tokens.dart';

/// Palette for [LatticePainter]-drawn card backs: vertical [top]→[bottom]
/// gradient ([flat] in CPU mode) under a lattice/rosette/frame drawn with the
/// three accent tones (the painter bakes its own alphas on top).
class CardBackStyle {
  final String id;
  final Color top;
  final Color bottom;
  final Color flat;
  final Color accent;
  final Color accentSoft;
  final Color accentDeep;

  const CardBackStyle({
    required this.id,
    required this.top,
    required this.bottom,
    required this.flat,
    required this.accent,
    required this.accentSoft,
    required this.accentDeep,
  });

  /// The default deep-green/gold back — must render byte-identical to the
  /// pre-cosmetics game.
  static const classic = CardBackStyle(
    id: 'back_classic',
    top: Tokens.felt500,
    bottom: Tokens.felt800,
    flat: Tokens.felt600,
    accent: Tokens.gold400,
    accentSoft: Tokens.gold300,
    accentDeep: Tokens.gold600,
  );

  /// «Капустная грядка»: cabbage greens with ivory-lime accents.
  static const cabbage = CardBackStyle(
    id: 'back_cabbage',
    top: Color(0xFF6B9A45),
    bottom: Color(0xFF33551F),
    flat: Color(0xFF4E7433),
    accent: Color(0xFFF0F5DC),
    accentSoft: Color(0xFFDBE9B9),
    accentDeep: Color(0xFF2E4A18),
  );

  /// «Бордовый бархат»: deep wine reds under the classic gold trim.
  static const burgundy = CardBackStyle(
    id: 'back_burgundy',
    top: Color(0xFF5A1F2A),
    bottom: Color(0xFF2C0D14),
    flat: Color(0xFF451722),
    accent: Tokens.gold400,
    accentSoft: Tokens.gold300,
    accentDeep: Tokens.gold600,
  );

  /// «Полночь»: steel blues with silvery accents.
  static const midnight = CardBackStyle(
    id: 'back_midnight',
    top: Color(0xFF1B2A47),
    bottom: Color(0xFF0A1220),
    flat: Color(0xFF152238),
    accent: Color(0xFFB9C6DE),
    accentSoft: Color(0xFFDCE4F2),
    accentDeep: Color(0xFF5C6E92),
  );

  /// «Слоновая кость»: the face palette inverted — ivory ground, felt trim.
  static const ivory = CardBackStyle(
    id: 'back_ivory',
    top: Tokens.ivory,
    bottom: Tokens.ivoryWarm,
    flat: Tokens.ivory,
    accent: Tokens.felt600,
    accentSoft: Tokens.felt500,
    accentDeep: Tokens.felt800,
  );

  /// «Золотой козёл» (premium): gold-on-gold with dark inked ornament.
  static const goldenGoat = CardBackStyle(
    id: 'back_golden_goat',
    top: Tokens.gold300,
    bottom: Tokens.gold600,
    flat: Tokens.gold400,
    accent: Color(0xFF4A3A10),
    accentSoft: Color(0xFF7A5F1A),
    accentDeep: Tokens.onGold,
  );

  /// Every style, catalog order.
  static const List<CardBackStyle> all = [
    classic,
    cabbage,
    burgundy,
    midnight,
    ivory,
    goldenGoat,
  ];

  /// Resolves a server/cached id; null for unknown ids (callers keep the
  /// current style so a newer server never breaks an older client).
  static CardBackStyle? byId(String id) {
    for (final style in all) {
      if (style.id == id) return style;
    }
    return null;
  }
}

/// Palette for [FeltPainter]: [base] ground, radial light pool
/// [light]→[mid]→[base], [deep] vignette; [flat] (= [mid]) in CPU mode.
class FeltTheme {
  final String id;
  final Color light;
  final Color mid;
  final Color base;
  final Color deep;

  const FeltTheme({
    required this.id,
    required this.light,
    required this.mid,
    required this.base,
    required this.deep,
  });

  /// CPU mode collapses the gradients to one tone — the mid felt.
  Color get flat => mid;

  /// The default casino green — must render byte-identical to the
  /// pre-cosmetics game.
  static const classic = FeltTheme(
    id: 'felt_classic',
    light: Tokens.felt600,
    mid: Tokens.felt700,
    base: Tokens.felt800,
    deep: Tokens.felt900,
  );

  /// «Бордовый бархат».
  static const burgundy = FeltTheme(
    id: 'felt_burgundy',
    light: Color(0xFF4A1A26),
    mid: Color(0xFF38121C),
    base: Color(0xFF2A0C14),
    deep: Color(0xFF17060B),
  );

  /// «Полночь».
  static const midnight = FeltTheme(
    id: 'felt_midnight',
    light: Color(0xFF1C2C4A),
    mid: Color(0xFF14213A),
    base: Color(0xFF0D1728),
    deep: Color(0xFF060C16),
  );

  /// «Капустная грядка» (premium).
  static const cabbage = FeltTheme(
    id: 'felt_cabbage',
    light: Color(0xFF3E6B2A),
    mid: Color(0xFF2F5420),
    base: Color(0xFF234018),
    deep: Color(0xFF12240C),
  );

  /// Every theme, catalog order.
  static const List<FeltTheme> all = [classic, burgundy, midnight, cabbage];

  /// Resolves a server/cached id; null for unknown ids.
  static FeltTheme? byId(String id) {
    for (final theme in all) {
      if (theme.id == id) return theme;
    }
    return null;
  }
}
