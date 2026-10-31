import 'package:material_ui/material_ui.dart';

ThemeData barTheme(ThemeData theme) => theme.copyWith(
  textTheme: theme.textTheme.apply(fontFamily: 'Roboto Flex'),
  primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Roboto Flex'),
);
