/// The casino-elegance dark theme, built entirely from [Tokens].
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildCasinoTheme() {
  const scheme = ColorScheme.dark(
    primary: Tokens.gold400,
    onPrimary: Tokens.onGold,
    secondary: Tokens.feltLine,
    onSecondary: Tokens.textPrimary,
    surface: Tokens.surface,
    onSurface: Tokens.textPrimary,
    surfaceContainerHighest: Tokens.surfaceHigh,
    error: Tokens.dangerDeep,
    onError: Tokens.textPrimary,
    outline: Tokens.gold600,
    outlineVariant: Color(0x338C6D1F),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: Tokens.sansFamily,
    scaffoldBackgroundColor: Tokens.felt800,
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.r10)),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontFamily: Tokens.sansFamily,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? Tokens.gold600.withValues(alpha: 0.35)
              : Tokens.gold400,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? Tokens.onGold.withValues(alpha: 0.55)
              : Tokens.onGold,
        ),
        overlayColor:
            WidgetStatePropertyAll(Tokens.gold100.withValues(alpha: 0.14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStatePropertyAll(
          BorderSide(color: Tokens.gold400.withValues(alpha: 0.65), width: 1),
        ),
        foregroundColor: const WidgetStatePropertyAll(Tokens.gold200),
        overlayColor:
            WidgetStatePropertyAll(Tokens.gold100.withValues(alpha: 0.14)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.r10)),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: const WidgetStatePropertyAll(Tokens.gold200),
        overlayColor:
            WidgetStatePropertyAll(Tokens.gold100.withValues(alpha: 0.14)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Tokens.gold400
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Tokens.onGold
              : Tokens.textSecondary,
        ),
        side: WidgetStatePropertyAll(
          BorderSide(color: Tokens.gold600.withValues(alpha: 0.4), width: 1),
        ),
        overlayColor:
            WidgetStatePropertyAll(Tokens.gold100.withValues(alpha: 0.14)),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: Tokens.titleSerif,
      iconTheme: IconThemeData(color: Tokens.gold300),
      actionsIconTheme: IconThemeData(color: Tokens.gold300),
    ),
    cardTheme: CardThemeData(
      color: Tokens.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.r14),
        side: BorderSide(
          color: Tokens.gold600.withValues(alpha: 0.28),
          width: 0.8,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Tokens.felt900.withValues(alpha: 0.5),
      labelStyle: const TextStyle(color: Tokens.textSecondary),
      hintStyle: const TextStyle(color: Tokens.textFaint),
      prefixIconColor: Tokens.gold300,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tokens.r10),
        borderSide: BorderSide(color: Tokens.gold600.withValues(alpha: 0.35)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tokens.r10),
        borderSide: const BorderSide(color: Tokens.gold300, width: 1.6),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tokens.r10),
        borderSide: BorderSide(color: Tokens.gold600.withValues(alpha: 0.35)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Tokens.surfaceHigh,
      contentTextStyle: const TextStyle(
        fontFamily: Tokens.sansFamily,
        color: Tokens.textPrimary,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.r10),
        side: BorderSide(color: Tokens.gold600.withValues(alpha: 0.4), width: 0.8),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: Tokens.gold300),
    dialogTheme: DialogThemeData(
      backgroundColor: Tokens.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.r20),
        side: BorderSide(color: Tokens.gold600.withValues(alpha: 0.4), width: 0.8),
      ),
      titleTextStyle: Tokens.titleSerif,
      contentTextStyle: Tokens.body.copyWith(color: Tokens.textSecondary),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Tokens.r20)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Tokens.felt900.withValues(alpha: 0.55),
      side: BorderSide(color: Tokens.gold600.withValues(alpha: 0.6), width: 0.8),
      labelStyle: const TextStyle(color: Tokens.textSecondary),
      iconTheme: const IconThemeData(color: Tokens.gold300),
    ),
    dividerTheme: DividerThemeData(
      color: Tokens.gold600.withValues(alpha: 0.4),
      thickness: 1,
    ),
  );
}
