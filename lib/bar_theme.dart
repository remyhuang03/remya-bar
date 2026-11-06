import 'package:material_ui/material_ui.dart';

const barFontFamily = 'Inter';
const barFontFamilyFallback = <String>[
  'Noto Sans CJK SC',
  'Noto Sans CJK TC',
  'Noto Sans CJK HK',
  'Noto Sans CJK JP',
  'Noto Sans CJK KR',
  'Noto Sans CJK',
  'sans-serif',
];

ThemeData barTheme(ThemeData theme) => theme.copyWith(
  textTheme: _typography(theme.textTheme),
  primaryTextTheme: _typography(theme.primaryTextTheme),
);

TextTheme _typography(TextTheme text) {
  final type = text.apply(
    fontFamily: barFontFamily,
    fontFamilyFallback: barFontFamilyFallback,
  );
  return type.copyWith(
    labelSmall: type.labelSmall?.copyWith(fontSize: 16, height: 1),
    labelMedium: type.labelMedium?.copyWith(fontSize: 16, height: 1),
    labelLarge: type.labelLarge?.copyWith(fontSize: 16, height: 1),
    bodySmall: type.bodySmall?.copyWith(fontSize: 13),
    bodyMedium: type.bodyMedium?.copyWith(fontSize: 16),
    bodyLarge: type.bodyLarge?.copyWith(fontSize: 16),
    titleMedium: type.titleMedium?.copyWith(fontSize: 19),
    titleLarge: type.titleLarge?.copyWith(fontSize: 22),
  );
}
