import 'dart:async';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../popups/bar_popup_button.dart';

part 'keyboard_key.dart';

const keyboardKind = 'keyboard';
const keyboardSize = Size(972, 421);

enum _Modifier {
  shift('Shift', 1),
  ctrl('Ctrl', 2),
  alt('Alt', 4),
  superKey('Super', 8),
  rightAlt('Alt', 16),
  fn('Fn', 0);

  const _Modifier(this.label, this.mask);
  final String label;
  final int mask;
}

enum _KeyState { idle, latched, locked }

class KeyboardPanel extends StatefulWidget {
  const KeyboardPanel({super.key, required this.data, required this.channel});

  final Map<String, Object?> data;
  final MethodChannel channel;

  @override
  State<KeyboardPanel> createState() => _KeyboardPanelState();
}

class _KeyboardPanelState extends State<KeyboardPanel> {
  static const _doubleTapTime = Duration(milliseconds: 300);
  final _clock = Stopwatch()..start();
  final _modifiers = <_Modifier, (_KeyState, Duration)>{};
  final _layoutMenu = MenuController();
  late Map<Object?, Object?> _device;
  late Map<Object?, Object?> _layout;
  late final Timer _poll;
  bool _reading = false;
  int? _pendingLayout;
  bool _docked = false;
  bool? _capsOverride;
  (String, Offset)? _preview;
  String? _error;

  Map get _config => _device['config'] as Map;
  List get _layouts => _layout['layouts'] as List;
  int get _group => _config['group'] as int;
  String get _layoutName => _layouts[_group] as String;
  bool get _caps => _capsOverride ?? (_device['caps'] == true);
  bool get _shift => _modifiers.containsKey(_Modifier.shift);
  bool get _fn => _modifiers.containsKey(_Modifier.fn);

  @override
  void initState() {
    super.initState();
    _device = widget.data['device'] as Map<Object?, Object?>;
    _layout = widget.data['layout'] as Map<Object?, Object?>;
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll.cancel();
    super.dispose();
  }

  Future<Map<Object?, Object?>?> _call(String action, [Object? value]) =>
      widget.channel.invokeMapMethod('action', {
        'action': 'keyboard.$action',
        'value': value,
      });

  Future<void> _action(String action, [Object? value]) async {
    try {
      await widget.channel.invokeMethod<void>('action', {
        'action': action == 'close' ? action : 'keyboard.$action',
        'value': value,
      });
      if (mounted && _error != null) setState(() => _error = null);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not complete keyboard action');
      }
      debugPrint('Virtual keyboard $action: $error');
    }
  }

  Future<void> _refresh([int? group]) async {
    if (_reading) {
      if (group != null) _pendingLayout = group;
      return;
    }
    _reading = true;
    try {
      final device = await _call('device', group);
      if (!mounted || device == null) return;
      final config = Map<Object?, Object?>.of(device['config'] as Map);
      // A touch-only session has no physical group to read back.
      if (group == null && device['physical'] == false) {
        config['group'] = _group;
      }
      final sameConfig = mapEquals(config, _config);
      final layout = sameConfig ? _layout : await _call('configure', config);
      if (!mounted || layout == null) return;
      final next = {...device, 'config': sameConfig ? _config : config};
      if (_error == null && mapEquals(next, _device)) return;
      setState(() {
        if (_device['caps'] != device['caps']) _capsOverride = null;
        _device = next;
        _layout = layout;
        _error = null;
        if (device['preview'] == false) _preview = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not read keyboard layout');
      debugPrint('Virtual keyboard layout: $error');
    } finally {
      _reading = false;
      if (_pendingLayout case final group? when mounted) {
        _pendingLayout = null;
        unawaited(_refresh(group));
      }
    }
  }

  void _toggleModifier(_Modifier modifier) {
    setState(() {
      final previous = _modifiers[modifier];
      final now = _clock.elapsed;
      if (previous == null) {
        _modifiers[modifier] = (.latched, now);
      } else if (previous.$1 == .latched &&
          now - previous.$2 < _doubleTapTime) {
        _modifiers[modifier] = (.locked, now);
      } else {
        _modifiers.remove(modifier);
      }
    });
  }

  void _press(int code) {
    final modifiers = _modifiers.keys.fold(0, (mask, key) => mask | key.mask);
    final locks = (_caps ? 1 : 0) | (_device['num'] == true ? 2 : 0);
    unawaited(_action('press', [code, modifiers, locks]));
    setState(() {
      _modifiers.removeWhere((_, state) => state.$1 == .latched);
    });
  }

  void _toggleCaps() => setState(() => _capsOverride = !_caps);

  Future<void> _dock() async {
    final docked = !_docked;
    try {
      await _call('dock', docked);
      if (mounted) setState(() => _docked = docked);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not reposition keyboard');
      debugPrint('Virtual keyboard dock: $error');
    }
  }

  List<List<_KeySpec>> _rows() {
    final labels = _layout['labels'] as List;
    final caps = _caps ? 2 : 0;
    _KeySpec character(int code, {double units = 1}) {
      final normal = (labels[caps] as List)[code] as String;
      final shifted = (labels[caps + 1] as List)[code] as String;
      return _KeySpec(
        code,
        _shift ? shifted : normal,
        alternate: normal.toLowerCase() == shifted.toLowerCase()
            ? null
            : _shift
            ? normal
            : shifted,
        units: units,
        kind: .character,
      );
    }

    final functionKeys = [for (var key = 59; key <= 68; key++) key, 87, 88];
    return [
      [
        const _KeySpec(1, 'Esc'),
        for (var i = 0; i < 12; i++)
          if (_fn)
            _KeySpec(
              i + 2,
              'F${i + 1}',
              send: functionKeys[i],
              kind: .character,
            )
          else
            character(i + 2),
        _KeySpec(
          14,
          _fn ? 'Delete' : 'Backspace',
          icon: _fn ? null : 'backspace',
          units: 2,
          send: _fn ? 111 : 14,
          repeat: true,
        ),
      ],
      [
        const _KeySpec(15, 'Tab', icon: 'tab', units: 1.5),
        for (var code = 16; code <= 27; code++) character(code),
        character(43, units: 1.5),
      ],
      [
        const _KeySpec(58, 'Caps', icon: 'caps', units: 1.75),
        for (var code = 30; code <= 40; code++) character(code),
        const _KeySpec(28, 'Enter', icon: 'enter', units: 2.25, kind: .accent),
      ],
      [
        const _KeySpec(
          42,
          'Shift',
          icon: 'shift',
          units: 2.25,
          modifier: .shift,
        ),
        for (var code = 44; code <= 53; code++) character(code),
        _KeySpec(
          103,
          _fn ? 'PgUp' : 'Up',
          icon: _fn ? null : 'up',
          send: _fn ? 104 : 103,
          repeat: true,
        ),
        const _KeySpec(
          54,
          'Shift',
          icon: 'shift',
          units: 1.75,
          modifier: .shift,
        ),
      ],
      [
        const _KeySpec(29, 'Ctrl', units: 1.25, modifier: .ctrl),
        const _KeySpec(125, 'Super', units: 1.25, modifier: .superKey),
        const _KeySpec(56, 'Alt', units: 1.25, modifier: .alt),
        _KeySpec(57, _layoutName, units: 6.25, kind: .space),
        const _KeySpec(100, 'Alt', modifier: .rightAlt),
        const _KeySpec(0, 'Fn', modifier: .fn),
        _KeySpec(
          105,
          _fn ? 'Home' : 'Left',
          icon: _fn ? null : 'left',
          send: _fn ? 102 : 105,
          repeat: true,
        ),
        _KeySpec(
          108,
          _fn ? 'PgDn' : 'Down',
          icon: _fn ? null : 'down',
          send: _fn ? 109 : 108,
          repeat: true,
        ),
        _KeySpec(
          106,
          _fn ? 'End' : 'Right',
          icon: _fn ? null : 'right',
          send: _fn ? 107 : 106,
          repeat: true,
        ),
      ],
    ];
  }

  Widget _keyRow(List<_KeySpec> keys, double y) {
    var x = 24.0;
    return Row(
      spacing: 6,
      children: [
        for (final key in keys)
          _key(key, Offset((x += key.units * 62) - key.units * 31 - 3, y)),
      ],
    );
  }

  Widget _key(_KeySpec key, Offset center) {
    final modifier = key.modifier;
    return _KeyboardKey(
      key: ValueKey(key.code),
      spec: key,
      state: key.code == 58 && _caps
          ? .locked
          : _modifiers[modifier]?.$1 ?? .idle,
      onActivate: modifier != null
          ? () => _toggleModifier(modifier)
          : key.code == 58
          ? _toggleCaps
          : () => _press(key.send ?? key.code),
      onPreview:
          _device['preview'] != false &&
              key.kind == .character &&
              key.send == null
          ? (show) => setState(() {
              if (show) {
                _preview = (key.label, center);
              } else if (_preview?.$2 == center) {
                _preview = null;
              }
            })
          : null,
    );
  }

  Widget _toolbar(ColorScheme colors) {
    final combo = _modifiers.keys
        .where((modifier) => modifier != .fn)
        .map((modifier) => modifier.label)
        .toSet()
        .join(' + ');
    final code = (_config['layout'] as String?)?.split(',');
    final chip = code == null || _group >= code.length || code[_group].isEmpty
        ? _layoutName
        : code[_group] == 'us'
        ? 'EN · US'
        : code[_group].toUpperCase();
    return Row(
      spacing: 8,
      children: [
        MenuAnchor(
          controller: _layoutMenu,
          menuChildren: [
            for (final (index, name) in _layouts.indexed)
              MenuItemButton(
                leadingIcon: index == _group ? const Icon(Icons.check) : null,
                onPressed: () => _refresh(index),
                child: Text(name as String),
              ),
          ],
          builder: (context, controller, _) => GestureDetector(
            onSecondaryTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: FilledButton.tonal(
              onPressed: () => _refresh((_group + 1) % _layouts.length),
              style: FilledButton.styleFrom(
                padding: const .fromLTRB(12, 0, 16, 0),
                minimumSize: const Size(104, 40),
                fixedSize: const Size.fromHeight(40),
                tapTargetSize: .shrinkWrap,
              ),
              child: Row(
                spacing: 8,
                children: [
                  const _KeyboardIcon('layout'),
                  Text(chip, style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ),
        ),
        const BarPopupButton(_KeyboardIcon('emoji'), 'Emoji unavailable', null),
        const BarPopupButton(
          _KeyboardIcon('clipboard'),
          'Clipboard unavailable',
          null,
        ),
        Expanded(
          child: Center(
            child: combo.isEmpty
                ? null
                : Container(
                    padding: const .symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: .circular(16),
                    ),
                    child: Text(
                      '$combo + …',
                      style: TextStyle(
                        color: colors.onPrimaryContainer,
                        fontSize: 12,
                      ),
                    ),
                  ),
          ),
        ),
        BarPopupButton(
          _KeyboardIcon(_docked ? 'dock-active' : 'dock'),
          _docked ? 'Float' : 'Dock',
          _dock,
          selected: _docked,
        ),
        BarPopupButton(
          const _KeyboardIcon('settings'),
          'Settings',
          () => _action('settings'),
        ),
        BarPopupButton(
          const _KeyboardIcon('hide'),
          'Hide',
          () => _action('close'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rows = _rows();
    final outline = _KeyboardOutline(_docked, colors.surfaceContainerHighest);
    return Padding(
      padding: .fromLTRB(20, 20, 20, _docked ? 0 : 20),
      child: FittedBox(
        fit: .scaleDown,
        child: SizedBox.fromSize(
          size: keyboardSize,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: outline.borderRadius,
              boxShadow: [
                BoxShadow(
                  color: const Color(0x66000000),
                  offset: Offset(0, _docked ? -8 : 12),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Material(
              color: colors.surfaceContainer,
              shape: outline,
              clipBehavior: .antiAlias,
              child: Stack(
                children: [
                  Padding(
                    padding: const .all(24),
                    child: Column(
                      crossAxisAlignment: .stretch,
                      spacing: 16,
                      children: [
                        _toolbar(colors),
                        Column(
                          spacing: 6,
                          children: [
                            for (var i = 0; i < rows.length; i++)
                              _keyRow(rows[i], 80.0 + i * 58),
                          ],
                        ),
                        Text(
                          _error ??
                              (_docked
                                  ? 'Docked — windows are resized to stay above the keyboard  ·  Tap Dock again to float'
                                  : _fn
                                  ? 'Fn — F-row, Delete and navigation keys'
                                  : _shift
                                  ? 'Shift  ·  Double-tap a modifier to lock'
                                  : 'Long-press Backspace / arrows to repeat  ·  Double-tap a modifier to lock'),
                          style: TextStyle(
                            color: _error == null
                                ? colors.onSurfaceVariant
                                : colors.error,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_docked)
                    Align(
                      alignment: .topCenter,
                      child: _DragHandle(
                        action: _action,
                        readCursor: () => _call('cursor'),
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  if (_preview case (final label, final position))
                    Positioned(
                      left: (position.dx - 32).clamp(
                        0,
                        keyboardSize.width - 64,
                      ),
                      top: position.dy - 76,
                      child: IgnorePointer(
                        child: Container(
                          width: 64,
                          height: 72,
                          alignment: .center,
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: .circular(22),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x59000000),
                                offset: Offset(0, 8),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: .bold,
                              color: colors.onPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The docked panel meets the bottom edge without a bottom stroke.
class _KeyboardOutline extends RoundedRectangleBorder {
  _KeyboardOutline(this.docked, Color color)
    : super(
        borderRadius: docked
            ? const .vertical(top: Radius.circular(32))
            : .circular(32),
        side: BorderSide(color: color),
      );

  final bool docked;

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    canvas.save();
    if (docked) {
      canvas.clipRect(
        Rect.fromLTRB(
          rect.left,
          rect.top,
          rect.right,
          rect.bottom - side.width,
        ),
      );
    }
    super.paint(canvas, rect, textDirection: textDirection);
    canvas.restore();
  }
}
