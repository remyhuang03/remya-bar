import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_client/remya_client.dart';
import 'package:remya_bar/features/settings/bar_preferences.dart';
import 'package:remya_ui/remya_ui.dart';

import '../../src/rust/system_bridge/api.dart' as api;
import '../../widgets/bar_tooltip.dart';
import '../popups/bar_popup.dart';
import 'tray_icon.dart';

const _menuKind = 'tray-menu';
const _motion = Duration(milliseconds: 240);
const _iconsChannel = MethodChannel('top.remya.bar/icons');

class BarTray extends StatefulWidget {
  const BarTray({super.key});

  @override
  State<BarTray> createState() => BarTrayState();
}

class BarTrayState extends State<BarTray> {
  final _settings = SettingsClient();
  late final _preferences = BarPreferences(client: _settings);
  late final StreamSubscription<SettingsChange> _changes;
  late final Timer _timer;
  var _items = <api.TrayItem>[];
  var _folded = <String>{};
  var _icons = <String, Uint8List>{};
  bool _refreshing = false;
  bool _expanded = false;
  bool _writing = false;
  int _preferencesRevision = 0;
  int _menuToken = 0;
  api.TrayItem? _menuItem;
  Rect? _menuAnchor;
  RemyaTheme? _menuTheme;
  double _textScale = 1;
  final _pages = <({int id, String title})>[];

  @override
  void initState() {
    super.initState();
    _changes = _settings.changes
        .where((change) => change.topic == barFoldedAppsSettingId)
        .listen((_) => _readPreferences(), onError: (Object _) {});
    unawaited(_readPreferences());
    unawaited(_refresh());
    // Folded apps follow Settings signals; only tray items are polled.
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_refresh()),
    );
  }

  Future<void> _readPreferences() async {
    if (_writing || !mounted) return;
    final revision = ++_preferencesRevision;
    try {
      final folded = await _preferences.readFoldedApps();
      if (!mounted || revision != _preferencesRevision) return;
      _applyFolded(folded);
    } catch (error) {
      debugPrint('Tray preferences: $error');
    }
  }

  void _applyFolded(Set<String> folded) {
    if (_folded.length == folded.length && _folded.containsAll(folded)) return;
    setState(() => _folded = folded);
    if (!_items.any(_isFolded)) _setExpanded(false);
  }

  bool _isFolded(api.TrayItem item) => _folded.contains(item.appId);

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final items = await api.trayItems();
      final icons = await _lookupIcons({
        for (final item in items)
          if (item.iconName.isNotEmpty &&
              (item.iconWidth < 64 || item.iconHeight < 64))
            (item.iconName, item.iconThemePath),
      });
      if (!mounted) return;
      setState(() {
        _items = items;
        _icons = icons;
      });
      if (!_items.any(_isFolded)) _setExpanded(false);
      if (_menuItem case final selected?
          when !_items.any((item) => item.id == selected.id)) {
        _closeMenu();
      }
    } catch (error) {
      debugPrint('Tray: $error');
    } finally {
      _refreshing = false;
    }
  }

  Future<Map<String, Uint8List>> _lookupIcons(
    Set<(String, String)> names,
  ) async {
    if (names.isEmpty) return {};
    return await _iconsChannel.invokeMapMethod<String, Uint8List>(
          'lookupTray',
          [
            for (final (name, path) in names) [name, path],
          ],
        ) ??
        {};
  }

  String _iconKey(String name, String path) => '$path\n$name';

  Map<String, Object?> _artwork(api.TrayItem item) => {
    'argb': item.iconArgb,
    'width': item.iconWidth,
    'height': item.iconHeight,
    'png': _icons[_iconKey(item.iconName, item.iconThemePath)],
    'attention': item.attention,
  };

  Future<void> _action(
    api.TrayItem item,
    String action, [
    int delta = 0,
  ]) async {
    try {
      await api.trayAction(id: item.id, action: action, delta: delta);
    } catch (error) {
      debugPrint('Tray action: $error');
    }
  }

  void _setExpanded(bool expanded) {
    if (_expanded == expanded) return;
    setState(() => _expanded = expanded);
    _send(BarPopup.channel.invokeMethod<void>('watchTrayOutside', expanded));
  }

  void _send(Future<void> request) {
    unawaited(request.catchError((Object error) => debugPrint('Tray: $error')));
  }

  void _closeMenu() {
    if (_menuItem == null) return;
    setState(() {
      ++_menuToken;
      _menuItem = null;
    });
    _send(BarPopup.hide(kind: _menuKind));
  }

  Future<void> _openMenu(BuildContext context, api.TrayItem item) async {
    if (_menuItem?.id == item.id) {
      _closeMenu();
      return;
    }
    final box = context.findRenderObject() as RenderBox;
    _menuAnchor = box.localToGlobal(.zero) & box.size;
    _menuTheme = BarPopupScope.themeOf(context);
    _textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    setState(() {
      ++_menuToken;
      _menuItem = item;
      _pages
        ..clear()
        ..add((id: 0, title: _title(item)));
    });
    final token = _menuToken;
    try {
      await _showMenu(_pages.last, first: true);
    } catch (error) {
      if (mounted && token == _menuToken) _closeMenu();
      debugPrint('Tray menu: $error');
    }
  }

  Future<void> _showMenu(
    ({int id, String title}) page, {
    bool first = false,
  }) async {
    final item = _menuItem!;
    final token = _menuToken;
    List<api.TrayMenuEntry>? entries;
    if (item.hasMenu) {
      try {
        entries = await api.trayMenu(id: item.id, parent: page.id);
      } catch (error) {
        if (page.id != 0) rethrow;
        debugPrint('Tray menu: $error');
      }
    }
    if (!mounted || token != _menuToken) return;
    final icons = await _lookupIcons({
      for (final entry in entries ?? const <api.TrayMenuEntry>[])
        if (entry.iconName.isNotEmpty && entry.iconData.isEmpty)
          (entry.iconName, item.iconThemePath),
    });
    if (!mounted || token != _menuToken) return;
    final data = {
      'token': token,
      'title': page.title,
      'artwork': _artwork(item),
      'parent': page.id,
      'canFold': _canFold(item),
      'folded': _isFolded(item),
      'nativeMenu': entries == null,
      'scale': _textScale,
      'entries': [
        for (final entry in entries ?? const <api.TrayMenuEntry>[])
          {
            'id': entry.id,
            'label': entry.label,
            'enabled': entry.enabled,
            'separator': entry.separator,
            'submenu': entry.submenu,
            'iconName': entry.iconName,
            'icon': entry.iconData.isEmpty
                ? icons[_iconKey(entry.iconName, item.iconThemePath)]
                : entry.iconData,
            'toggleType': entry.toggleType,
            'toggleState': entry.toggleState,
          },
      ],
    };
    final size = Size(
      (200 * _textScale).clamp(200, 420),
      ((entries?.length ?? 2) * 36.0 + 98).clamp(64, 720),
    );
    await (first ? BarPopup.show : BarPopup.update)(
      kind: _menuKind,
      anchor: _menuAnchor!,
      size: size,
      data: data,
      theme: _menuTheme!,
    );
  }

  bool _canFold(api.TrayItem item) =>
      item.appId.trim().isNotEmpty &&
      !RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(item.appId) &&
      utf8.encode(item.appId).length <= 256;

  Future<void> popupAction(Map<dynamic, dynamic> args) async {
    final action = args['action'];
    if (action == 'tray.outside') {
      _closeMenu();
      _setExpanded(false);
      return;
    }
    final item = _menuItem;
    if (item == null || args['token'] != _menuToken) return;
    final token = _menuToken;
    switch (action) {
      case 'tray.closed':
        setState(() {
          ++_menuToken;
          _menuItem = null;
        });
      case 'tray.fold' when _canFold(item) && !_writing:
        _writing = true;
        ++_preferencesRevision;
        try {
          final folded = await _preferences.setAppFolded(
            item.appId,
            !_isFolded(item),
          );
          if (!mounted) return;
          _applyFolded(folded);
        } finally {
          _writing = false;
          unawaited(_readPreferences());
        }
        if (token == _menuToken) _closeMenu();
      case 'tray.submenu' when args['entry'] is int && args['label'] is String:
        final page = (id: args['entry'] as int, title: args['label'] as String);
        if (_pages.length >= 16 ||
            _pages.any((current) => current.id == page.id)) {
          throw StateError('Invalid application submenu');
        }
        await _showMenu(page);
        if (token == _menuToken) _pages.add(page);
      case 'tray.back' when _pages.length > 1:
        await _showMenu(_pages[_pages.length - 2]);
        if (token == _menuToken) _pages.removeLast();
      case 'tray.menu' when args['entry'] is int:
        await api.trayMenuAction(
          id: item.id,
          parent: _pages.last.id,
          entry: args['entry'] as int,
        );
        if (token == _menuToken) _closeMenu();
      case 'tray.context':
        await api.trayAction(id: item.id, action: 'context', delta: 0);
        if (token == _menuToken) _closeMenu();
      case 'tray.activate':
        await api.trayAction(id: item.id, action: 'activate', delta: 0);
        if (token == _menuToken) _closeMenu();
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    unawaited(_changes.cancel().whenComplete(_settings.close));
    if (_expanded) {
      _send(BarPopup.channel.invokeMethod<void>('watchTrayOutside', false));
    }
    if (_menuItem != null) _send(BarPopup.hide(kind: _menuKind));
    super.dispose();
  }

  String _title(api.TrayItem item) =>
      item.title.isEmpty ? 'Application' : item.title;

  Widget _button(api.TrayItem item) => _TrayButton(
    key: ValueKey(item.id),
    title: _title(item),
    artwork: _artwork(item),
    selected: _menuItem?.id == item.id,
    onActivate: (context) =>
        item.itemIsMenu ? _openMenu(context, item) : _action(item, 'activate'),
    onMenu: (context) => _openMenu(context, item),
    onSecondary: () => _action(item, 'secondary'),
    onScroll: (offset) {
      final horizontal = offset.dx.abs() > offset.dy.abs();
      final delta = horizontal ? offset.dx : offset.dy;
      if (delta != 0) {
        _action(
          item,
          horizontal ? 'scrollHorizontal' : 'scroll',
          delta > 0 ? -120 : 120,
        );
      }
    },
  );

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final folded = _items.where(_isFolded);
    final pinned = _items.where((item) => !_isFolded(item));
    return TapRegion(
      onTapOutside: (_) {
        _closeMenu();
        _setExpanded(false);
      },
      child: SizedBox(
        height: 32,
        child: Material(
          color: colors.surfaceContainerHigh,
          shape: const StadiumBorder(),
          child: Padding(
            padding: folded.isEmpty
                ? const .symmetric(horizontal: 12, vertical: 3)
                : .only(
                    left: 3,
                    right: pinned.isEmpty ? 3 : 12,
                    top: 3,
                    bottom: 3,
                  ),
            child: Row(
              spacing: folded.isNotEmpty && pinned.isNotEmpty ? 2 : 0,
              mainAxisSize: .min,
              children: [
                if (folded.isNotEmpty)
                  _TrayToggle(
                    expanded: _expanded,
                    onTap: () {
                      _closeMenu();
                      _setExpanded(!_expanded);
                    },
                  ),
                Flexible(
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context)
                        .copyWith(dragDevices: {.mouse, .touch, .trackpad}),
                    child: SingleChildScrollView(
                      scrollDirection: .horizontal,
                      reverse: true,
                      child: Row(
                        mainAxisSize: .min,
                        children: [
                          if (folded.isNotEmpty)
                            TweenAnimationBuilder<double>(
                              duration: _motion,
                              curve: Curves.easeInOutCubicEmphasized,
                              tween: Tween(end: _expanded ? 1 : 0),
                              child: Padding(
                                padding: .only(right: pinned.isEmpty ? 0 : 2),
                                child: Material(
                                  color: colors.onSurface.withValues(
                                    alpha: .08,
                                  ),
                                  borderRadius: .circular(4),
                                  child: Row(
                                    children: folded.map(_button).toList(),
                                  ),
                                ),
                              ),
                              builder: (context, width, child) => ExcludeFocus(
                                excluding: !_expanded,
                                child: IgnorePointer(
                                  ignoring: !_expanded,
                                  child: ClipRect(
                                    child: Align(
                                      alignment: .centerRight,
                                      widthFactor: width,
                                      child: child,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          for (final item in pinned) _button(item),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrayToggle extends StatelessWidget {
  const _TrayToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = expanded ? 'Collapse tray apps' : 'Expand tray apps';
    return BarTooltip(
      message: label,
      trayStyle: true,
      child: Semantics(
        expanded: expanded,
        child: IconButton(
          isSelected: expanded,
          onPressed: onTap,
          style: _buttonStyle(
            context,
            background: expanded ? colors.secondaryContainer : null,
            foreground: expanded
                ? colors.onSecondaryContainer
                : colors.onSurface,
            radius: 13,
          ),
          icon: AnimatedRotation(
            turns: expanded ? .5 : 0,
            duration: _motion,
            child: const Icon(Icons.chevron_left_rounded, size: 18),
          ),
        ),
      ),
    );
  }
}

class _TrayButton extends StatelessWidget {
  const _TrayButton({
    super.key,
    required this.title,
    required this.artwork,
    required this.selected,
    required this.onActivate,
    required this.onMenu,
    required this.onSecondary,
    required this.onScroll,
  });

  final String title;
  final Map<String, Object?> artwork;
  final bool selected;
  final ValueChanged<BuildContext> onActivate;
  final ValueChanged<BuildContext> onMenu;
  final VoidCallback onSecondary;
  final ValueChanged<Offset> onScroll;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return BarTooltip(
      message: selected ? '' : title,
      trayStyle: true,
      child: Semantics(
        label: title,
        selected: selected,
        customSemanticsActions: {
          const CustomSemanticsAction(label: 'Application menu'): () =>
              onMenu(context),
        },
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.contextMenu): () =>
                onMenu(context),
            const SingleActivator(LogicalKeyboardKey.f10, shift: true): () =>
                onMenu(context),
          },
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                GestureBinding.instance.pointerSignalResolver.register(
                  event,
                  (_) => onScroll(event.scrollDelta),
                );
              }
            },
            child: GestureDetector(
              onSecondaryTap: () => onMenu(context),
              onTertiaryTapUp: (_) => onSecondary(),
              child: IconButton(
                onPressed: () => onActivate(context),
                style: _buttonStyle(
                  context,
                  background: selected
                      ? colors.onSurface.withValues(alpha: .10)
                      : null,
                  radius: selected ? 6 : 8,
                ),
                icon: _PressableArtwork(artwork: artwork, selected: selected),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PressableArtwork extends StatelessWidget {
  const _PressableArtwork({required this.artwork, required this.selected});

  final Map<String, Object?> artwork;
  final bool selected;

  @override
  Widget build(BuildContext context) => TrayIcon(
    data: artwork,
    size: selected ? 16 : IconTheme.of(context).size ?? 18,
  );
}

ButtonStyle _buttonStyle(
  BuildContext context, {
  required double radius,
  Color? background,
  Color? foreground,
}) {
  final ink = foreground ?? Theme.of(context).colorScheme.onSurface;
  return ButtonStyle(
    padding: const WidgetStatePropertyAll(.zero),
    minimumSize: const WidgetStatePropertyAll(Size.square(26)),
    maximumSize: const WidgetStatePropertyAll(Size.square(26)),
    tapTargetSize: .shrinkWrap,
    visualDensity: .standard,
    backgroundColor: .all(background),
    foregroundColor: .all(ink),
    iconSize: .resolveWith(
      (states) => states.contains(WidgetState.pressed) ? 16 : 18,
    ),
    shape: .resolveWith(
      (states) => RoundedRectangleBorder(
        borderRadius: .circular(
          states.contains(WidgetState.pressed) && radius <= 8 ? 6 : radius,
        ),
      ),
    ),
    overlayColor: .resolveWith(
      (states) => ink.withValues(
        alpha:
            states.contains(WidgetState.pressed) ||
                states.contains(WidgetState.focused)
            ? .10
            : states.contains(WidgetState.hovered)
            ? .08
            : 0,
      ),
    ),
  );
}
