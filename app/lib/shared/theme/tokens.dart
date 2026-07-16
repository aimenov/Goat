/// Casino-elegance design tokens: the single source of truth for colors,
/// shadows, radii, spacing and typography. Everything is `static const`
/// (zero runtime cost, tree-shakes cleanly).
library;

import 'package:flutter/material.dart';

abstract final class Tokens {
  // ------------------------------------------------------------ felt greens
  static const felt900 = Color(0xFF0A1B10);
  static const felt800 = Color(0xFF0F2718);
  static const felt700 = Color(0xFF153522);
  static const felt600 = Color(0xFF1C452D);
  static const felt500 = Color(0xFF255A3B);
  static const feltLine = Color(0xFF2F7D4E);

  // -------------------------------------------------------- gold/brass ramp
  static const gold100 = Color(0xFFF7E7B4);
  static const gold200 = Color(0xFFEFD68C);
  static const gold300 = Color(0xFFE6C36A);
  static const gold400 = Color(0xFFD4AF37);
  static const gold500 = Color(0xFFB8912E);
  static const gold600 = Color(0xFF8C6D1F);
  static const goldGlow = Color(0xFFFFD54F);

  /// Dark warm ink used on gold-filled surfaces (buttons, badges).
  static const onGold = Color(0xFF221B07);

  // ------------------------------------------------------------------ ivory
  static const ivory = Color(0xFFFAF3E3);
  static const ivoryWarm = Color(0xFFF1E7CC);
  static const ivoryEdge = Color(0xFFE3D5AF);

  // -------------------------------------------------------------- suit inks
  static const suitRed = Color(0xFFAE3B32);
  static const suitBlack = Color(0xFF26221A);
  static const suitRedOnDark = Color(0xFFE57368);
  static const suitLightOnDark = Color(0xFFF2EEE3);

  // --------------------------------------------------------- surfaces, text
  static const surface = Color(0xFF14231B);
  static const surfaceHigh = Color(0xFF1C2F24);
  static const textPrimary = Color(0xFFF2EEE3);
  static const textSecondary = Color(0xFFC9C2AD);
  static const textFaint = Color(0xFF8D8A7A);

  // --------------------------------------------------------------- semantic
  static const success = Color(0xFF7BC488);
  static const danger = Color(0xFFE25B4E);
  static const dangerDeep = Color(0xFF9C2B22);

  // ---------------------------------------------------------------- shadows
  /// Cards at rest.
  static const shadowCard = BoxShadow(
    color: Color(0x59000000),
    blurRadius: 4,
    offset: Offset(0, 2),
  );

  /// Overlays, selected cards.
  static const shadowRaised = BoxShadow(
    color: Color(0x73000000),
    blurRadius: 14,
    offset: Offset(0, 5),
  );

  /// Gold glow with intensity [v] in [0, 1] — the PulseGlow formula.
  static BoxShadow glowGold(double v) => BoxShadow(
    color: gold300.withValues(alpha: 0.18 + 0.30 * v),
    blurRadius: 8 + 8 * v,
    spreadRadius: 0.5 + 2 * v,
  );

  // ------------------------------------------------------------------ radii
  static const double r4 = 4;
  static const double r10 = 10;
  static const double r14 = 14;
  static const double r20 = 20;

  // ---------------------------------------------------------------- spacing
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s7 = 32;

  // ------------------------------------------------------------- typography
  static const serifFamily = 'PlayfairDisplay';
  static const sansFamily = 'Inter';

  /// «Козёл» on login.
  static const displaySerif = TextStyle(
    fontFamily: serifFamily,
    fontWeight: FontWeight.w800,
    fontSize: 40,
    letterSpacing: 0.5,
    color: gold200,
    height: 1.1,
  );

  /// Game-over headline, «Итоги раздачи».
  static const headlineSerif = TextStyle(
    fontFamily: serifFamily,
    fontWeight: FontWeight.w700,
    fontSize: 26,
    color: gold200,
    height: 1.2,
  );

  /// AppBar titles («Столы», «Достижения», «Ждём игроков»).
  static const titleSerif = TextStyle(
    fontFamily: serifFamily,
    fontWeight: FontWeight.w700,
    fontSize: 20,
    color: gold200,
  );

  /// Tile titles.
  static const titleMedium = TextStyle(
    fontFamily: sansFamily,
    fontWeight: FontWeight.w600,
    fontSize: 16,
    color: textPrimary,
  );

  /// Default body.
  static const body = TextStyle(
    fontFamily: sansFamily,
    fontWeight: FontWeight.w400,
    fontSize: 14,
    color: textPrimary,
  );

  /// Seat names, chips.
  static const label = TextStyle(
    fontFamily: sansFamily,
    fontWeight: FontWeight.w500,
    fontSize: 12,
    color: textPrimary,
  );

  /// Hints, captions («Карты уйдут втёмную»).
  static const caption = TextStyle(
    fontFamily: sansFamily,
    fontWeight: FontWeight.w400,
    fontSize: 11,
    color: textFaint,
  );

  /// All scores/counters — tabular figures so CountUpText never jitters.
  static const numeric = TextStyle(
    fontFamily: sansFamily,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
