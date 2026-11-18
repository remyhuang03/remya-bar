import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_client/remya_client.dart';
import 'package:remya_ui/remya_ui.dart';

/// The owning view supplies the same Settings theme to its popup Flutter view,
/// and both know which output edge the bar sits on.
class BarPopupScope extends InheritedWidget {
  const BarPopupScope({
    super.key,
    required this.theme,
    this.bottom = false,
    this.popup,
    required super.child,
  });
  final RemyaTheme theme;
  final BarPopup? popup;

  /// Whether the bar is on the bottom edge, so cards open upwards.
  final bool bottom;

  static RemyaTheme themeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BarPopupScope>()!.theme;

  static bool bottomOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BarPopupScope>()?.bottom ??
      false;

  @override
  bool updateShouldNotify(BarPopupScope oldWidget) =>
      theme != oldWidget.theme ||
      bottom != oldWidget.bottom ||
      popup != oldWidget.popup;
}

/// Routes popup requests and card state for a single bar view.
final class BarPopup {
  BarPopup(this.channel);

  BarPopup.forView(int viewId)
    : this(MethodChannel('top.remya.bar/bar/$viewId/popup'));

  final MethodChannel channel;
  final openCard = ValueNotifier<String?>(null);
  static final keyboardOpen = ValueNotifier(false);
  static int _keyboardRevision = 0;
  bool _disposed = false;

  static BarPopup? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BarPopupScope>()?.popup;

  static MethodChannel viewChannel(int viewId) =>
      MethodChannel('top.remya.bar/popup/$viewId');

  static void setKeyboardVisibility(bool open) {
    _keyboardRevision++;
    keyboardOpen.value = open;
  }

  Future<void> syncKeyboardVisibility() async {
    final revision = _keyboardRevision;
    final open = await channel.invokeMethod<bool>('keyboardVisible');
    if (!_disposed && revision == _keyboardRevision) {
      keyboardOpen.value = open ?? false;
    }
  }

  Future<void> show({
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

  Future<void> update({
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

  Future<void> _send(
    String method, {
    required String kind,
    required Rect anchor,
    required Size size,
    required Map<String, Object?> data,
    required RemyaTheme theme,
  }) => _invoke(method, {
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
      contrast: theme.contrast,
    ).toMap(),
  });

  Future<void> _invoke(String method, [Object? arguments]) => _disposed
      ? Future.value()
      : channel.invokeMethod<void>(method, arguments);

  Future<void> hide({String? kind}) =>
      _invoke('hide', kind == null ? null : {'kind': kind});

  Future<void> enter({String? kind}) =>
      _invoke('enter', kind == null ? null : {'kind': kind});

  Future<void> leave({String? kind}) =>
      _invoke('leave', kind == null ? null : {'kind': kind});

  Future<void> watchTrayOutside(bool enabled) =>
      _invoke('watchTrayOutside', enabled);

  void dispose() {
    _disposed = true;
    openCard.dispose();
  }
}
