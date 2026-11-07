import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

import '../../src/rust/system_bridge/api.dart' as system;

class SidebarBackend extends ChangeNotifier {
  final _settings = SettingsClient();
  final _data = <String, Object?>{};
  Timer? _poll;
  StreamSubscription<SettingsChange>? _changes;
  String? _output;
  int _generation = 0;
  bool _refreshing = false;
  bool _writing = false;
  bool _disposed = false;

  Map<String, Object?> get data => Map.unmodifiable(_data);

  void open(String? output) {
    if (_output != output) {
      _output = output;
      _generation++;
      _data.remove('brightness');
    }
    _changes ??= _settings.changes.listen(
      (change) {
        if (_poll == null) return;
        final key = switch (change.topic) {
          'theme' => 'theme',
          keepAwakeSettingId => 'keep-awake',
          _ => null,
        };
        if (key != null) {
          _generation++;
          _data[key] = change.value;
          notifyListeners();
          return;
        }
        if (const {
          'sound',
          'power',
          'network',
          'bluetooth',
          'night-light',
          barSidebarLayoutSettingId,
        }.contains(change.topic)) {
          unawaited(_refresh());
        }
      },
      onError: (Object error) => debugPrint('Sidebar Settings changes: $error'),
    );
    _poll ??= Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
    unawaited(_refresh());
  }

  void close() {
    _poll?.cancel();
    _poll = null;
    unawaited(_changes?.cancel());
    _changes = null;
    _generation++;
  }

  Future<void> _refresh() async {
    if (_poll == null || _refreshing || _writing) return;
    _refreshing = true;
    final generation = _generation;
    final output = _output;
    Future<void> read(String key, Future<Object?> request) async {
      Object? value;
      try {
        value = await request;
      } catch (error) {
        debugPrint('Sidebar $key: $error');
        if (key == 'layout') return;
      }
      if (!_disposed && _poll != null && generation == _generation) {
        _data[key] = value;
        notifyListeners();
      }
    }

    try {
      await Future.wait([
        read('uptimeSeconds', system.sidebarUptime()),
        read('sound', _settings.readSound()),
        read('network', _settings.readNetwork()),
        read('bluetooth', _settings.readBluetooth()),
        read('night-light', _settings.call('Get', ['night-light'])),
        read('power', _settings.readPower()),
        read('theme', _settings.call('Get', ['theme'])),
        read('keep-awake', _settings.readKeepAwake()),
        read('layout', _settings.readSidebarLayout()),
        if (output != null)
          read('brightness', _brightness(output))
        else
          read('brightness', Future.value()),
      ]);
    } finally {
      _refreshing = false;
      if (generation != _generation) unawaited(_refresh());
    }
  }

  Future<Map?> _brightness(String output) async {
    final data = await _settings.call('Get', ['display-brightness']);
    return (data['outputs'] as List?)?.whereType<Map>().firstWhereOrNull(
      (item) => item['output'] == output,
    );
  }

  Future<void> perform(Map args, String? output) async {
    if (_disposed || _writing) throw StateError('Sidebar controls are busy');
    final action = args['action'];
    final value = args['value'];
    final target = args['target'];
    _writing = true;
    _generation++;
    try {
      final (String key, Object? result) = switch (action) {
        'sidebar.brightness'
            when output != null &&
                output == target &&
                value is num &&
                value.isFinite &&
                value >= 0 &&
                value <= 100 =>
          ('brightness', await _brightnessResult(output, value.round())),
        'sidebar.output-volume' || 'sidebar.input-volume'
            when target is String &&
                value is num &&
                value.isFinite &&
                value >= 0 &&
                value <= 100 =>
          (
            'sound',
            await _settings.changeSound(
              'sound.${(action as String).substring(8)}',
              {'name': target, 'percent': value},
            ),
          ),
        'sidebar.output-muted' ||
        'sidebar.input-muted' when target is String && value is bool => (
          'sound',
          await _settings.changeSound(
            'sound.${(action as String).substring(8)}',
            {'name': target, 'muted': value},
          ),
        ),
        'sidebar.output-device' when target is String => (
          'sound',
          await _settings.changeSound(soundOutputDeviceSettingId, {
            'name': target,
          }),
        ),
        'sidebar.wifi' when value is bool => (
          'network',
          await _settings.setWifiEnabled(value),
        ),
        'sidebar.wifi-scan' => ('network', await _settings.scanWifi()),
        'sidebar.wifi-connect' when value is Map => (
          'network',
          await _settings.connectWifi(
            ssid: value['ssid'] as String?,
            uuid: value['uuid'] as String?,
            password: value['password'] as String?,
            hiddenSecurity: value['hidden_security'] as String?,
          ),
        ),
        'sidebar.wifi-disconnect' => (
          'network',
          await _settings.call('Set', [wifiDisconnectSettingId, 'disconnect']),
        ),
        'sidebar.wifi-forget' when target is String => (
          'network',
          await _settings.call('Set', [knownNetworkForgetSettingId, target]),
        ),
        'sidebar.bluetooth' ||
        'sidebar.bluetooth-scan' ||
        'sidebar.bluetooth-connect' ||
        'sidebar.bluetooth-disconnect' ||
        'sidebar.bluetooth-forget' ||
        'sidebar.bluetooth-pair' ||
        'sidebar.bluetooth-respond' ||
        'sidebar.bluetooth-cancel' when value is Map => (
          'bluetooth',
          await _settings.setBluetooth(
            action == 'sidebar.bluetooth'
                ? bluetoothEnabledSettingId
                : 'bluetooth.${(action as String).substring(18)}',
            Map<String, Object?>.from(value),
          ),
        ),
        'sidebar.night-light' when value is bool => (
          'night-light',
          await _settings.call('Set', ['night-light.e32be03e', '$value']),
        ),
        'sidebar.keep-awake' when value is bool => (
          'keep-awake',
          await _settings.setKeepAwake(value),
        ),
        'sidebar.dark' when value is bool => (
          'theme',
          await _settings.call('Set', [
            materialThemeModeSettingId,
            value ? 'dark' : 'light',
          ]),
        ),
        'sidebar.profile' when value is String => (
          'power',
          await _settings.setPower('power.5a4f0131', value),
        ),
        'sidebar.layout' when value is List && target is List => (
          'layout',
          await _settings.setSidebarLayout(
            List<String>.from(target),
            List<String>.from(value),
          ),
        ),
        'sidebar.session' when value is String => (
          '',
          await system
              .sidebarSessionAction(action: value)
              .then<Object?>((_) => null),
        ),
        _ => throw const FormatException('Invalid sidebar action'),
      };
      final state = result;
      if (state is Map &&
          state['error'] is String &&
          (state['error'] as String).isNotEmpty) {
        throw StateError(state['error'] as String);
      }
      if (!_disposed && key.isNotEmpty) {
        _data[key] = state;
        notifyListeners();
      }
    } finally {
      _writing = false;
      unawaited(_refresh());
    }
  }

  Future<Map?> _brightnessResult(String output, int percent) async {
    await _settings.call('Set', [
      'display.5d419889',
      jsonEncode({'output': output, 'value': '$percent'}),
    ]);
    return _brightness(output);
  }

  @override
  void dispose() {
    _disposed = true;
    close();
    unawaited(_settings.close());
    super.dispose();
  }
}

extension<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final item in this) {
      if (test(item)) return item;
    }
    return null;
  }
}
