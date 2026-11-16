import 'package:material_ui/material_ui.dart';

/// Big, high-contrast theme: large text and tap targets for easy use.
ThemeData kirayaTheme({Color seed = const Color(0xFF00796B)}) {
  final scheme = ColorScheme.fromSeed(seedColor: seed);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  // Merge real font sizes first: base.textTheme has none, and apply(fontSizeFactor) asserts on null sizes.
  final text = Typography.material2021().englishLike.merge(base.textTheme).apply(fontSizeFactor: 1.12);
  return base.copyWith(
    textTheme: text,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 56),
        textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(64, 52), textStyle: text.titleMedium),
    ),
    cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 12),
  );
}

const kGood = Color(0xFF2E7D32);
const kBad = Color(0xFFC62828);
const kWarn = Color(0xFFEF6C00);
