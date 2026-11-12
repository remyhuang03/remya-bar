import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/remya_settings_client.dart'
    show BarOsdPreferences;

import '../../widgets/bar_pill.dart';
import '../../widgets/bar_tooltip.dart';

import '../osd/osd_slider.dart';
import '../popups/bar_popup_button.dart';
import '../popups/popup_measure.dart';

part 'sidebar_controls.dart';
part 'sidebar_detail.dart';

const sidebarSize = Size(420, 663);

/// The quick settings toggle: live Wi-Fi, Bluetooth and volume status icons.
/// States whose value is unknown are omitted rather than guessed.
class BarSidebarButton extends StatefulWidget {
  const BarSidebarButton({
    super.key,
    required this.onToggle,
    this.open = false,
    this.wifi,
    this.bluetooth,
    this.volume,
    this.muted,
  });

  final Future<void> Function(Rect anchor, double scale) onToggle;
  final bool open;
  final bool? wifi;
  final bool? bluetooth;
  final double? volume;
  final bool? muted;

  @override
  State<BarSidebarButton> createState() => _BarSidebarButtonState();
}

class _BarSidebarButtonState extends State<BarSidebarButton> {
  final _pill = GlobalKey();

  void _toggle() {
    final box = _pill.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    unawaited(
      widget.onToggle(
        box.localToGlobal(.zero) & box.size,
        MediaQuery.textScalerOf(context).scale(1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final icons = [
      if (widget.wifi case final on?)
        on ? Icons.wifi_rounded : Icons.wifi_off_rounded,
      if (widget.bluetooth case final on?)
        on ? Icons.bluetooth_rounded : Icons.bluetooth_disabled_rounded,
      if (widget.muted == true || widget.volume == 0)
        Icons.volume_off_rounded
      else if (widget.volume case final volume?)
        volume < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded,
    ];
    return BarTooltip(
      message: 'Quick settings',
      child: BarPill(
        pillKey: _pill,
        semanticsLabel: 'Quick settings',
        toggled: widget.open,
        onTap: _toggle,
        padding: const .symmetric(horizontal: 12),
        builder: (context, state) => Row(
          mainAxisSize: .min,
          spacing: 6,
          children: [
            for (final icon in icons.isEmpty ? [Icons.tune_rounded] : icons)
              Icon(icon, size: 18, color: state.foreground),
          ],
        ),
      ),
    );
  }
}

class RightSidebar extends StatefulWidget {
  const RightSidebar({
    super.key,
    required this.data,
    required this.onAction,
    required this.onHeight,
  });

  final Map<String, Object?> data;
  final Future<void> Function(Map<String, Object?>) onAction;
  final ValueChanged<double> onHeight;

  @override
  State<RightSidebar> createState() => _RightSidebarState();
}

class _RightSidebarState extends State<RightSidebar> {
  static const _large = {
    'internet': ('Internet', Icons.wifi_rounded),
    'bluetooth': ('Bluetooth', Icons.bluetooth_rounded),
    'audio': ('Audio', Icons.headphones_rounded),
    'night-light': ('Night Light', Icons.dark_mode_rounded),
    'dnd': ('Do Not Disturb', Icons.do_not_disturb_on_rounded),
    'power': ('Power', Icons.bolt_rounded),
  };

  static const _small = {
    'caffeine': ('Keep awake', Icons.coffee_rounded),
    'record': ('Screen record', Icons.radio_button_checked_rounded),
    'screenshot': ('Screenshot', Icons.crop_free_rounded),
    'picker': ('Color picker', Icons.colorize_rounded),
    'dark': ('Dark mode', Icons.dark_mode_rounded),
    'dnd-quick': ('Do Not Disturb', Icons.do_not_disturb_on_rounded),
    'airplane': ('Airplane mode', Icons.flight_rounded),
    'keyboard': ('On-screen keyboard', Icons.keyboard_rounded),
    'clipboard': ('Clipboard', Icons.content_paste_rounded),
    'mic-mute': ('Mic mute', Icons.mic_off_rounded),
  };

  static const _powerActions = {
    'lock': ('Lock', Icons.lock_rounded),
    'logout': ('Log out', Icons.logout_rounded),
    'restart': ('Restart', Icons.restart_alt_rounded),
    'shutdown': ('Shut down', Icons.power_settings_new_rounded),
  };

  static const _detailTitles = {
    'internet': 'Wi-Fi',
    'bluetooth': 'Bluetooth',
    'audio': 'Audio',
    'power': 'Power',
  };

  String? _detail;
  bool _power = false;
  int _pendingActions = 0;
  bool get _busy => _pendingActions > 0;
  String? _error;
  String? _confirming;
  Timer? _confirmation;
  List<String>? _original;
  List<String>? _draft;
  final _scroll = ScrollController();

  Map get _network => _map(widget.data['network']);
  Map get _bluetooth => _map(widget.data['bluetooth']);
  Map get _sound => _map(widget.data['sound']);
  Map get _night => _map(widget.data['night-light']);
  bool? get _dnd => _map(widget.data['notification-dnd'])['value'] as bool?;
  Map get _powerState => _map(widget.data['power']);
  Map get _powerSystem => _map(_powerState['system']);
  List<String>? get _saved =>
      (widget.data['layout'] as List?)?.whereType<String>().toList();
  List<String> get _tiles =>
      _draft ?? _saved ?? [..._large.keys, ..._small.keys];
  List<String> get _profiles => _rowsOf<String>(_powerSystem['profiles']);
  String? _adapterId;
  Map? get _adapter {
    final adapters = _rowsOf<Map>(_bluetooth['adapters']);
    return adapters.where((item) => item['id'] == _adapterId).firstOrNull ??
        adapters.where((item) => item['powered'] == true).firstOrNull ??
        adapters.firstOrNull;
  }

  Map? get _output => _audioDevice('output');
  Map? get _input => _audioDevice('input');

  Map? _audioDevice(String direction) {
    final system = _map(_sound['system']);
    final name = system['default_$direction'];
    return _rowsOf<Map>(system['devices'])
        .where(
          (device) =>
              device['direction'] == direction && device['name'] == name,
        )
        .firstOrNull;
  }

  @override
  void dispose() {
    _confirmation?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<bool> _send(String action, {Object? value, Object? target}) async {
    if (_busy &&
        const {
          'sidebar.layout',
          'sidebar.session',
          'sidebar.wifi-connect',
          'sidebar.wifi-forget',
          'sidebar.bluetooth-pair',
          'sidebar.bluetooth-forget',
          'sidebar.bluetooth-respond',
        }.contains(action)) {
      return false;
    }
    setState(() {
      _pendingActions++;
      _error = null;
    });
    try {
      await widget.onAction({
        'action': action,
        'value': value,
        'target': target,
      });
      return true;
    } catch (error) {
      if (mounted) {
        final message = error is PlatformException ? error.message : null;
        setState(() => _error = message ?? 'Could not complete this action.');
      }
      return false;
    } finally {
      if (mounted) setState(() => _pendingActions--);
    }
  }

  void _view(String? detail) {
    setState(() {
      _detail = detail;
      _error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (detail == 'internet' &&
        _network['wifi_enabled'] == true &&
        _network['adapter'] is String) {
      unawaited(_send('sidebar.wifi-scan'));
    }
  }

  void _clearConfirmation() {
    _confirmation?.cancel();
    _confirming = null;
  }

  void _session(String id) {
    if (_busy) return;
    if (id == 'lock' || id == _confirming) {
      setState(_clearConfirmation);
      unawaited(_send('sidebar.session', value: id));
      return;
    }
    _confirmation?.cancel();
    setState(() => _confirming = id);
    _confirmation = Timer(
      const Duration(seconds: 3),
      () => setState(_clearConfirmation),
    );
  }

  Future<void> _edit() async {
    if (_busy) return;
    final draft = _draft;
    if (draft == null) {
      final saved = _saved;
      if (saved == null) return;
      setState(() {
        _power = false;
        _clearConfirmation();
        _original = saved;
        _draft = [...saved];
      });
    } else if (listEquals(draft, _original) ||
        await _send('sidebar.layout', value: draft, target: _original)) {
      if (mounted) setState(() => _draft = _original = null);
    }
  }

  void _place(String id, String? before) {
    if (_busy) return;
    setState(() {
      final draft = _draft!..remove(id);
      final index = before == null ? -1 : draft.indexOf(before);
      draft.insert(index < 0 ? draft.length : index, id);
    });
  }

  void _escape() {
    if (_draft != null) {
      unawaited(_edit());
    } else {
      unawaited(widget.onAction({'action': 'close'}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _escape},
      child: Focus(
        autofocus: true,
        child: Material(
          color: theme.colorScheme.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: .circular(32),
            side: BorderSide(color: theme.colorScheme.surfaceContainerHighest),
          ),
          clipBehavior: .antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final pad = constraints.maxWidth < 340 ? 12.0 : 24.0;
              final headerHeight =
                  44.0 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 2);
              return Padding(
                padding: .symmetric(vertical: pad),
                child: Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .stretch,
                  spacing: 16,
                  children: [
                    Padding(
                      padding: .symmetric(horizontal: pad),
                      child: SizedBox(
                        height: headerHeight,
                        child: _header(theme),
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        controller: _scroll,
                        padding: .symmetric(horizontal: pad),
                        child: PopupMeasure(
                          onHeight: (height) => widget.onHeight(
                            height + pad * 2 + 16 + headerHeight,
                          ),
                          child: Column(
                            crossAxisAlignment: .stretch,
                            spacing: 16,
                            children: [
                              if (_error case final error?)
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        error,
                                        style: TextStyle(
                                          color: theme.colorScheme.error,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close_rounded),
                                      tooltip: 'Dismiss error',
                                      onPressed: () =>
                                          setState(() => _error = null),
                                    ),
                                  ],
                                ),
                              if (_detail == null)
                                ..._overview(theme)
                              else
                                _SidebarDetail(
                                  key: ValueKey(_detail),
                                  kind: _detail!,
                                  data: widget.data,
                                  adapter: _adapter,
                                  onSelectAdapter: (id) =>
                                      setState(() => _adapterId = id),
                                  busy: _busy,
                                  send: _send,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) {
    if (_detail case final detail?) {
      final enabled = switch (detail) {
        'internet'
            when _network['wifi_hardware_enabled'] == true &&
                _network['writable'] == true =>
          _network['wifi_enabled'] as bool?,
        'bluetooth' when _adapter?['hardware_blocked'] != true =>
          _adapter?['powered'] as bool?,
        _ => null,
      };
      return Row(
        spacing: 8,
        children: [
          BarPopupButton(
            const Icon(Icons.arrow_back_rounded, size: 20),
            'Back',
            () => _view(null),
          ),
          Expanded(
            child: Text(
              _detailTitles[detail]!,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: .bold),
            ),
          ),
          if (detail == 'internet' || detail == 'bluetooth')
            Semantics(
              label: _detailTitles[detail],
              child: Switch(
                value: enabled ?? false,
                onChanged: enabled == null
                    ? null
                    : (value) async {
                        if (detail == 'bluetooth') {
                          await _send(
                            'sidebar.bluetooth',
                            value: {
                              'adapter': _adapter!['id'],
                              'enabled': value,
                            },
                          );
                        } else {
                          final success = await _send(
                            'sidebar.wifi',
                            value: value,
                          );
                          if (success &&
                              value &&
                              mounted &&
                              _detail == detail &&
                              _network['adapter'] is String) {
                            await _send('sidebar.wifi-scan');
                          }
                        }
                      },
              ),
            ),
        ],
      );
    }
    if (_draft != null) {
      return Row(
        children: [
          Expanded(
            child: _SidebarLabel(
              'Edit layout',
              'Drag to reorder • tap − to hide',
              titleSize: 20,
              bold: true,
            ),
          ),
          BarPopupButton(
            const Icon(Icons.edit_rounded, size: 20),
            'Finish editing',
            _busy ? null : _edit,
            selected: true,
          ),
        ],
      );
    }
    final account = _map(widget.data['account']);
    final username = account['username'] as String? ?? '';
    return Row(
      spacing: 12,
      children: [
        _AccountAvatar(
          path: account['avatar_path'] as String?,
          key: ValueKey((account['avatar_path'], account['avatar_revision'])),
          initial: username.isEmpty
              ? null
              : username.characters.first.toUpperCase(),
        ),
        Expanded(
          child: _SidebarLabel(
            username.isEmpty ? 'Account' : username,
            _uptime(widget.data['uptimeSeconds']),
            titleSize: 20,
            bold: true,
          ),
        ),
        SizedBox(
          width: (MediaQuery.sizeOf(context).width - 148)
              .clamp(44, 160)
              .toDouble(),
          child: FittedBox(
            fit: .scaleDown,
            alignment: .centerRight,
            child: Row(
              mainAxisSize: .min,
              children: [
                BarPopupButton(
                  const Icon(Icons.edit_rounded, size: 20),
                  'Edit layout',
                  _saved == null || _busy ? null : _edit,
                ),
                BarPopupButton(
                  const Icon(Icons.close_rounded, size: 20),
                  'Quit Remya Bar',
                  () => _send('quit'),
                ),
                BarPopupButton(
                  const Icon(Icons.settings_outlined, size: 20),
                  'Settings',
                  () => _send('sidebar.settings', target: 'remya-bar'),
                ),
                BarPopupButton(
                  const Icon(Icons.power_settings_new_rounded, size: 20),
                  'Power',
                  () => setState(() {
                    _power = !_power;
                    _clearConfirmation();
                  }),
                  selected: _power,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _overview(ThemeData theme) {
    final colors = theme.colorScheme;
    final edit = _draft != null;
    final brightness = _map(widget.data['brightness']);
    final hidden = [
      ..._large.keys,
      ..._small.keys,
    ].where((id) => !_tiles.contains(id));
    return [
      if (_power)
        Row(
          spacing: 8,
          children: [
            for (final MapEntry(key: id, value: (label, icon))
                in _powerActions.entries)
              Expanded(
                child: _PowerButton(
                  label: label,
                  icon: icon,
                  confirm: id == _confirming,
                  onPressed: _busy ? null : () => _session(id),
                ),
              ),
          ],
        ),
      Opacity(
        opacity: edit ? .38 : 1,
        child: Column(
          spacing: 8,
          children: [
            _brightnessSlider(brightness, edit),
            _soundSlider(
              'output',
              _output,
              Icons.volume_up_rounded,
              Icons.volume_off_rounded,
              'Output volume',
            ),
            _soundSlider(
              'input',
              _input,
              Icons.mic_rounded,
              Icons.mic_off_rounded,
              'Microphone',
            ),
          ],
        ),
      ),
      if (_tiles.any(_large.containsKey) || edit)
        _grid(2, _tiles.where(_large.containsKey).toList(), _largeTile),
      if (_tiles.any(_small.containsKey) || edit)
        _grid(5, _tiles.where(_small.containsKey).toList(), _smallTile),
      if (edit) ...[
        Column(
          crossAxisAlignment: .stretch,
          spacing: 8,
          children: [
            const Text('Hidden — drag up to add'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final id in hidden)
                  _EditableTile(
                    id: id,
                    label: (_large[id] ?? _small[id]!).$1,
                    icon: (_large[id] ?? _small[id]!).$2,
                    onActivate: _busy ? null : () => _place(id, null),
                    child: SizedBox(
                      width: 68,
                      height: 52,
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(padding: .zero),
                        onPressed: _busy ? null : () => _place(id, null),
                        child: Icon((_large[id] ?? _small[id]!).$2, size: 20),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ],
      Text(
        edit
            ? 'Esc to finish'
            : _power
            ? 'Log out, restart and shut down need a second click within 3 s'
            : 'Esc to close',
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
          fontSize: 12,
          height: 1.2,
        ),
      ),
    ];
  }

  BarOsdPreferences get _osdPreferences {
    try {
      return BarOsdPreferences.fromJson(widget.data['osd']);
    } on FormatException {
      return const BarOsdPreferences();
    }
  }

  Widget _brightnessSlider(Map brightness, bool edit) {
    final hardware = brightness['percent'] as num?;
    final gamma = brightness['gamma'] as num?;
    final minimum = _osdPreferences.gammaMin;
    final offset = hardware == null ? 0 : 99;
    final position = gamma != null && (hardware == null || gamma < 100)
        ? gamma - offset
        : hardware?.clamp(1, 100);
    bool software(double value) =>
        gamma != null && (hardware == null || value < 1);
    return _SidebarSlider(
      key: ValueKey((brightness['output'], hardware != null)),
      icon: Icons.brightness_6_rounded,
      label: 'Brightness',
      percent: position,
      min: gamma == null ? 1 : (minimum - offset).toDouble(),
      // Software dimming sits below the hardware floor, or below 100% alone.
      threshold: gamma == null ? null : 100.0 - offset,
      zone: .software,
      // The gamma fill color marks software dimming; no extra wording.
      valueLabel: (value) =>
          '${(software(value) ? value + offset : value).round()}%',
      onChange: edit || position == null || brightness['output'] == null
          ? null
          : (value) => _send(
              'sidebar.brightness',
              target: brightness['output'],
              value: software(value)
                  ? {'gamma': (value + offset).round()}
                  : value,
            ),
    );
  }

  Widget _soundSlider(
    String direction,
    Map? device,
    IconData icon,
    IconData mutedIcon,
    String label,
  ) {
    final preferences = _map(device?['preferences']);
    final values = _rowsOf<int>(preferences['channels']);
    final percent = values.isEmpty
        ? null
        : values.reduce((a, b) => a > b ? a : b) * 100 / 65536;
    // Zero volume and mute are one state, as in the OSD.
    final muted = preferences['muted'] == true || percent?.round() == 0;
    final output = direction == 'output';
    final maximum = output
        ? math.max(_osdPreferences.volumeMax, percent?.ceil() ?? 0)
        : 100;
    final enabled = _draft == null && device != null;
    return _SidebarSlider(
      key: ValueKey((direction, device?['name'])),
      icon: muted ? mutedIcon : icon,
      label: label,
      percent: percent,
      max: maximum.toDouble(),
      threshold: maximum > 100 ? 100 : null,
      zone: .boost,
      muted: muted,
      onChange: enabled && percent != null
          ? (value) => _send(
              'sidebar.$direction-volume',
              target: device['name'],
              value: value,
            )
          : null,
      onIcon: enabled
          ? () => _send(
              'sidebar.$direction-muted',
              target: device['name'],
              value: !muted,
            )
          : null,
      onSecondary: output && _draft == null ? () => _view('audio') : null,
    );
  }

  Widget _grid(
    int columns,
    List<String> ids,
    Widget Function(String) buildTile,
  ) => LayoutBuilder(
    builder: (context, bounds) {
      final width = (bounds.maxWidth - (columns - 1) * 8) / columns;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final id in ids) SizedBox(width: width, child: buildTile(id)),
          if (_draft != null && ids.isEmpty)
            DragTarget<String>(
              onWillAcceptWithDetails: (drag) =>
                  !_busy && (_large.containsKey(drag.data) == (columns == 2)),
              onAcceptWithDetails: (drag) => _place(drag.data, null),
              builder: (_, candidates, _) => SizedBox(
                height: 40,
                child: Center(
                  child: Text(
                    candidates.isEmpty
                        ? 'Drag here to restore'
                        : 'Drop to restore',
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _largeTile(String id) {
    final (title, icon) = _large[id]!;
    final wifi = _network['wifi_enabled'] == true;
    final bluetooth = _adapter?['powered'] == true;
    final audio =
        _output != null && _map(_output?['preferences'])['muted'] != true;
    final night = _night['enabled'] == true;
    final profile = _powerSystem['profile'] as String?;
    final saver = profile == 'power-saver';
    final primary = _rowsOf<Map>(_network['active'])
        .where((item) => item['uuid'] == _network['primary_uuid'])
        .firstOrNull;
    final connected = _rowsOf<Map>(_bluetooth['devices'])
        .where((item) => item['connected'] == true)
        .length;
    final dnd = _dnd;
    final (bool active, String subtitle, VoidCallback? toggle) = switch (id) {
      'internet' => (
        wifi,
        primary?['name'] as String? ??
            (_network.isEmpty
                ? 'Unavailable'
                : wifi
                ? 'On'
                : 'Off'),
        _network['writable'] == true &&
                _network['wifi_hardware_enabled'] == true
            ? () => _send('sidebar.wifi', value: !wifi)
            : null,
      ),
      'bluetooth' => (
        bluetooth,
        _adapter == null
            ? 'Unavailable'
            : bluetooth
            ? '$connected connected'
            : 'Off',
        _adapter != null && _adapter?['hardware_blocked'] != true
            ? () => _send(
                'sidebar.bluetooth',
                value: {'adapter': _adapter!['id'], 'enabled': !bluetooth},
              )
            : null,
      ),
      'audio' => (
        audio,
        _output?['description'] as String? ?? 'Unavailable',
        _output == null
            ? null
            : () => _send(
                'sidebar.output-muted',
                target: _output!['name'],
                value: audio,
              ),
      ),
      'night-light' => (
        night,
        _night.isEmpty
            ? 'Unavailable'
            : night
            ? _night['end'] is String
                  ? "Until ${_night['end']}"
                  : "${_night['live_temperature'] ?? _night['temperature']} K"
            : 'Off',
        _night['temperature'] is num &&
                _night['write_blocked'] == null &&
                _night['conflict'] != true
            ? () => _send('sidebar.night-light', value: !night)
            : null,
      ),
      'power' => (
        saver,
        profile == null ? 'Unavailable' : _profileLabel(profile),
        _powerState['conflict'] != true &&
                _profiles.contains(saver ? 'balanced' : 'power-saver')
            ? () => _send(
                'sidebar.profile',
                value: saver ? 'balanced' : 'power-saver',
              )
            : null,
      ),
      'dnd' => (
        dnd == true,
        dnd == null
            ? 'Unavailable'
            : dnd
            ? 'On'
            : 'Off',
        dnd == null ? null : () => _send('sidebar.dnd', value: !dnd),
      ),
      _ => (false, 'Not implemented', null),
    };
    final detail = _detailTitles.containsKey(id) ? () => _view(id) : null;
    final tile = _LargeTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      active: active,
      editing: _draft != null,
      onToggle: _draft != null ? null : toggle,
      onDetail: _draft != null ? null : detail,
    );
    return _editable(id, title, icon, tile);
  }

  Widget _smallTile(String id) {
    final (title, icon) = _small[id]!;
    final input = _input;
    final mode = _map(_map(widget.data['theme'])['theme'])['theme_mode'];
    final awake = _map(widget.data['keep-awake'])['value'];
    final airplane = _map(widget.data['airplane']);
    final bool? selected = switch (id) {
      'caffeine' when awake is bool => awake,
      'dark' when mode == 'light' || mode == 'dark' => mode == 'dark',
      'dnd-quick' => _dnd,
      'airplane' when airplane['available'] == true =>
        airplane['enabled'] as bool?,
      'keyboard' => widget.data['keyboardOpen'] as bool?,
      'mic-mute' => _map(input?['preferences'])['muted'] as bool?,
      _ => null,
    };
    final tile = _SmallTile(
      icon: icon,
      title: selected == null ? '$title unavailable' : title,
      selected: selected,
      editing: _draft != null,
      onTap: selected == null || _draft != null
          ? null
          : switch (id) {
              'caffeine' => () => _send('sidebar.keep-awake', value: !selected),
              'dark' => () => _send('sidebar.dark', value: !selected),
              'dnd-quick' => () => _send('sidebar.dnd', value: !selected),
              'airplane' when !_busy => () => _send(
                'sidebar.airplane',
                value: !selected,
              ),
              'keyboard' when !_busy => () => _send(
                'sidebar.keyboard',
                value: !selected,
              ),
              'mic-mute' => () => _send(
                'sidebar.input-muted',
                target: input!['name'],
                value: !selected,
              ),
              _ => null,
            },
    );
    return _editable(id, title, icon, tile);
  }

  Widget _editable(String id, String title, IconData icon, Widget tile) {
    if (_draft == null) return tile;
    return _EditableTile(
      id: id,
      label: title,
      icon: icon,
      onActivate: _busy ? null : () => setState(() => _draft!.remove(id)),
      onDrop: (moving) => _place(moving, id),
      child: tile,
    );
  }
}

Map _map(Object? value) => value is Map ? value : const {};
List<T> _rowsOf<T>(Object? value) =>
    value is List ? value.whereType<T>().toList() : [];

String _profileLabel(String id) => switch (id) {
  'power-saver' => 'Power Saver',
  'balanced' => 'Balanced',
  'performance' => 'Performance',
  _ => id,
};

String _uptime(Object? seconds) {
  if (seconds is! num || !seconds.isFinite || seconds < 0) {
    return 'Uptime unavailable';
  }
  final uptime = Duration(seconds: seconds.floor());
  return [
    'Up',
    if (uptime.inDays > 0) '${uptime.inDays}d',
    if (uptime.inHours > 0) '${uptime.inHours % 24}h',
    '${uptime.inMinutes % 60}m',
  ].join(' ');
}
