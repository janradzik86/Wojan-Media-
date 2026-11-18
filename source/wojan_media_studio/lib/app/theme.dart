import 'package:material_ui/material_ui.dart';

/// WoJan Media Studio visual identity: dark studio, anthracite panels,
/// teal/magenta accents, high contrast.
class WmsColors {
  static const bg = Color(0xFF111317);
  static const panel = Color(0xFF1B1E24);
  static const panel2 = Color(0xFF252931);
  static const accent = Color(0xFF35D0BA);
  static const accent2 = Color(0xFFFF4FA3);
  static const text = Color(0xFFF2F4F7);
  static const muted = Color(0xFF9AA3AF);
  static const warn = Color(0xFFFFB020);
  static const error = Color(0xFFFF5A5F);
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: WmsColors.accent, brightness: b, secondary: WmsColors.accent2).copyWith(
    surface: dark ? WmsColors.panel : const Color(0xFFF7F8FA),
    primary: dark ? WmsColors.accent : const Color(0xFF0E8F7E),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: b,
    scaffoldBackgroundColor: dark ? WmsColors.bg : const Color(0xFFEDEFF3),
    cardTheme: CardThemeData(color: dark ? WmsColors.panel : Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    appBarTheme: AppBarTheme(backgroundColor: dark ? WmsColors.panel : Colors.white, elevation: 0, centerTitle: false),
    navigationRailTheme: NavigationRailThemeData(backgroundColor: dark ? WmsColors.panel : Colors.white),
    sliderTheme: const SliderThemeData(showValueIndicator: ShowValueIndicator.onDrag),
    inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: dark ? WmsColors.panel2 : Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none), isDense: true),
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );
}
