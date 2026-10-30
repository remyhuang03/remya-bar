import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

/// The owning view supplies the same Settings theme to its popup Flutter view.
class BarPopupScope extends InheritedWidget {
  const BarPopupScope({super.key, required this.theme, required super.child});
  final RemyaTheme theme;

  static RemyaTheme themeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BarPopupScope>()!.theme;

  @override
  bool updateShouldNotify(BarPopupScope oldWidget) => theme != oldWidget.theme;
}

abstract final class BarPopup {
  static const channel = MethodChannel('top.remya.bar/popup');

  static Future<void> show({
    required String kind,
    required Rect anchor,
    required Size size,
    required Map<String, Object?> data,
    required RemyaTheme theme,
  }) => channel.invokeMethod<void>('show', {
    'kind': kind,
    'anchor': [
      anchor.left.floor(),
      anchor.top.floor(),
      anchor.width.ceil(),
      anchor.height.ceil(),
    ],
    'size': [size.width.ceil(), size.height.ceil()],
    'data': data,
    'theme': ThemeConfig(
      styleVariant: theme.styleVariant.configKey,
      mode: theme.mode.name,
    ).toMap(),
  });

  static Future<void> hide() => channel.invokeMethod<void>('hide');
}
