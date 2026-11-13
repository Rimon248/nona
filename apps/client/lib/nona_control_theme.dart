import 'dart:io';

import 'package:flutter/material.dart';

abstract final class NonaColor {
  static const navy = Color(0xFF12354F);
  static const deep = Color(0xFF0D293E);
  static const sidebar = Color(0xFF0E2B40);
  static const raised = Color(0xFF1D445F);
  static const cream = Color(0xFFFBF0D9);
  static const coral = Color(0xFFE36B55);
  static const line = Color(0xFF466579);
  static const muted = Color(0xFFA9BEC9);
  static const soft = Color(0xFFE5EAF0);
}

ThemeData buildNonaControlTheme() {
  final scheme = const ColorScheme.dark().copyWith(
    primary: NonaColor.cream,
    onPrimary: NonaColor.navy,
    secondary: NonaColor.coral,
    surface: NonaColor.navy,
    onSurface: NonaColor.cream,
    outline: NonaColor.line,
    error: const Color(0xFFFF9D93),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: Platform.isWindows ? 'Segoe UI' : null,
    colorScheme: scheme,
    scaffoldBackgroundColor: NonaColor.navy,
    appBarTheme: const AppBarTheme(
      backgroundColor: NonaColor.navy,
      foregroundColor: NonaColor.cream,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: NonaColor.raised,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dividerTheme: const DividerThemeData(color: NonaColor.line, thickness: 1),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? NonaColor.coral
            : NonaColor.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? NonaColor.coral.withValues(alpha: 0.35)
            : NonaColor.line,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? NonaColor.coral
            : Colors.transparent,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: NonaColor.cream,
        foregroundColor: NonaColor.navy,
        disabledBackgroundColor: const Color(0xFF6D8492),
        disabledForegroundColor: const Color(0xFFE1E8E8),
        minimumSize: const Size(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: NonaColor.cream,
        side: const BorderSide(color: NonaColor.line),
        minimumSize: const Size(0, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: NonaColor.cream),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: NonaColor.raised,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: NonaColor.line),
      ),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: NonaColor.cream,
        fontSize: 35,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.3,
      ),
      headlineMedium: TextStyle(
        color: NonaColor.cream,
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.1,
      ),
      titleLarge: TextStyle(
        color: NonaColor.cream,
        fontSize: 23,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      titleMedium: TextStyle(
        color: NonaColor.cream,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(color: NonaColor.cream, fontSize: 16, height: 1.45),
      bodyMedium: TextStyle(color: NonaColor.soft, fontSize: 14, height: 1.45),
      bodySmall: TextStyle(color: NonaColor.muted, fontSize: 12, height: 1.4),
    ),
  );
}

class NonaFace extends StatelessWidget {
  const NonaFace({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => ClipOval(
    child: Image.asset(
      'assets/brand/nona-portrait.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
      semanticLabel: 'Нона, виртуальный помощник',
    ),
  );
}
