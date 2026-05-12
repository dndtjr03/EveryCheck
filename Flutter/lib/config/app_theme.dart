import 'package:flutter/material.dart';

class AppColors {
  static const primary     = Color(0xFF3B87E8);
  static const primaryDark = Color(0xFF2C65AE);
  static const primaryLight= Color(0xFFE8F1FC);

  static const secondary     = Color(0xFF38C07C);
  static const secondaryLight= Color(0xFFE7F7EF);

  static const accent      = Color(0xFFFF7C45);
  static const accentLight = Color(0xFFFFEFE9);

  static const danger      = Color(0xFFE04030);
  static const dangerLight = Color(0xFFFEF0EE);

  static const bg      = Color(0xFFF5F6FA);
  static const surface = Color(0xFFFFFFFF);
  static const border  = Color(0xFFE8E6E2);

  static const n100 = Color(0xFFF0EDE8);
  static const n200 = Color(0xFFE2DDD6);
  static const n300 = Color(0xFFC8C2B8);
  static const n400 = Color(0xFFA09890);
  static const n500 = Color(0xFF787068);
  static const n600 = Color(0xFF5A534C);
  static const n700 = Color(0xFF3C3730);
  static const n800 = Color(0xFF1E1B18);

  static const kakao = Color(0xFFFEE500);
  static const kakaoText = Color(0xFF3C1E1E);
  static const naver = Color(0xFF03C75A);
}

/// 다크 모드 전용 컬러 (HTML 디자인 기준).
/// 위젯에서 직접 참조하기보다 Theme.of(context)를 통해 자동 전환되도록 권장.
class AppColorsDark {
  static const bg      = Color(0xFF0F1117);
  static const surface = Color(0xFF1E2130);
  static const border  = Color(0xFF2A2E3C);

  static const n100 = Color(0xFF2A2E3C);
  static const n200 = Color(0xFF353A4D);
  static const n300 = Color(0xFF4A5068);
  static const n400 = Color(0xFF6B7090);
  static const n500 = Color(0xFF8890A8);
  static const n600 = Color(0xFFA8B0C8);
  static const n700 = Color(0xFFC8D0E8);
  static const n800 = Color(0xFFE8ECF5);
}

const kRadius = 14.0;
const kRadiusPill = 9999.0;

/// Brightness에 따라 적절한 surface 색 반환.
/// 위젯에서 `AppColors.surface` 대신 점진적으로 사용 가능.
Color surfaceOf(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColorsDark.surface
        : AppColors.surface;

Color bgOf(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColorsDark.bg
        : AppColors.bg;

Color borderOf(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColorsDark.border
        : AppColors.border;

/// ── Theme 빌더 ───────────────────────────────────────────────────────────

ThemeData buildLightTheme() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ).copyWith(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
        error: AppColors.danger,
      ),
      scaffoldBackgroundColor: AppColors.bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.n800,
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadius),
          side: const BorderSide(color: AppColors.border, width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadius - 2),
          borderSide: const BorderSide(color: AppColors.border, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadius - 2),
          borderSide: const BorderSide(color: AppColors.border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadius - 2),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        labelStyle: const TextStyle(color: AppColors.n500, fontSize: 13),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kRadiusPill),
          ),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primaryLight,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.primary : AppColors.n500,
          );
        }),
      ),
      textTheme: const TextTheme(
        bodyLarge:  TextStyle(color: AppColors.n800, fontSize: 15),
        bodyMedium: TextStyle(color: AppColors.n700, fontSize: 14),
        bodySmall:  TextStyle(color: AppColors.n500, fontSize: 12),
      ),
    );

ThemeData buildDarkTheme() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
      ).copyWith(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColorsDark.surface,
        error: AppColors.danger,
      ),
      scaffoldBackgroundColor: AppColorsDark.bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColorsDark.surface,
        foregroundColor: AppColorsDark.n800,
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColorsDark.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadius),
          side: const BorderSide(color: AppColorsDark.border, width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadius - 2),
          borderSide: const BorderSide(color: AppColorsDark.border, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadius - 2),
          borderSide: const BorderSide(color: AppColorsDark.border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadius - 2),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        filled: true,
        fillColor: AppColorsDark.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        labelStyle: const TextStyle(color: AppColorsDark.n500, fontSize: 13),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kRadiusPill),
          ),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColorsDark.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.2),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.primary : AppColorsDark.n500,
          );
        }),
      ),
      textTheme: const TextTheme(
        bodyLarge:  TextStyle(color: AppColorsDark.n800, fontSize: 15),
        bodyMedium: TextStyle(color: AppColorsDark.n700, fontSize: 14),
        bodySmall:  TextStyle(color: AppColorsDark.n500, fontSize: 12),
      ),
    );
