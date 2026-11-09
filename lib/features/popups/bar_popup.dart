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
  static final openCard = ValueNotifier<String?>(null);
  static final keyboardOpen = ValueNotifier(false);

  static const channel = MethodChannel('top.remya.bar/popup');

  static MethodChannel viewChannel(int viewId) =>
      MethodChannel('${channel.name}/$viewId');

  static Future<void> show({
    required String kind,
    required Rect anchor,
    required Size size,
    required Map<String, Object?> data,
    required RemyaTheme theme,
  }) => _send(
    'show',
    kind: kind,
    anchor: anchor,
    size: size,
    data: data,
    theme: theme,
  );

  static Future<void> update({
    required String kind,
    required Rect anchor,
    required Size size,
    required Map<String, Object?> data,
    required RemyaTheme theme,
  }) => _send(
    'update',
    kind: kind,
    anchor: anchor,
    size: size,
    data: data,
    theme: theme,
  );

  static Future<void> _send(
    String method, {
    required String kind,
    required Rect anchor,
    required Size size,
    required Map<String, Object?> data,
    required RemyaTheme theme,
  }) => channel.invokeMethod<void>(method, {
    'kind': kind,
    'opening': method == 'show',
    'anchor': [
      anchor.left.floor(),
      anchor.top.floor(),
      anchor.width.ceil(),
      anchor.height.ceil(),
    ],
    'size': [size.width.ceil(), size.height.ceil()],
    'data': data,
    'seed': theme.seedColor.toARGB32() & 0xFFFFFF,
    'theme': ThemeConfig(
      styleVariant: theme.styleVariant.configKey,
      mode: theme.mode.name,
    ).toMap(),
  });

  static Future<void> hide({String? kind}) =>
      channel.invokeMethod<void>('hide', kind == null ? null : {'kind': kind});

  static Future<void> enter({String? kind}) =>
      channel.invokeMethod<void>('enter', kind == null ? null : {'kind': kind});
  static Future<void> leave({String? kind}) =>
      channel.invokeMethod<void>('leave', kind == null ? null : {'kind': kind});
}
