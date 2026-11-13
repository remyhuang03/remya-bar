import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:remya_client/remya_client.dart';

import '../settings/bar_display.dart';
import '../settings/bar_preferences.dart';

import '../../src/rust/system_bridge/api.dart' as system;

class SidebarBackend extends ChangeNotifier {
  SidebarBackend({SettingsClient? settings})
    : _settings = settings ?? SettingsClient();

  final SettingsClient _settings;
  late final _display = BarDisplay(_settings);
  late final _preferences = BarPreferences(client: _settings);
  final _queue = <_SidebarWrite>[];
  final _data = <String, Object?>{};
  Timer? _poll;
  StreamSubscription<SettingsChange>? _changes;
  String? _output;
  Map<String, Object?>? _confirmedBrightness;
  int _generation = 0;
  bool _refreshing = false;
  bool _writing = false;
  bool _disposed = false;

  Map<String, Object?> get data => Map.unmodifiable(_data);

  void open(String? output) {
    final wasClosed = _poll == null;
    if (_output != output) {
      _output = output;
      _generation++;
      _data.remove('brightness');
      _confirmedBrightness = null;
    }
    _changes ??= _settings.changes.listen(
      (change) {
        if (_poll == null) return;
        final key = switch (change.topic) {
          'theme' => 'theme',
          'sound' when change.value.containsKey('available') => 'sound',
          keepAwakeSettingId => 'keep-awake',
          _ => null,
        };
        if (_writing || _queue.isNotEmpty) return;
        if (key != null) {
          _generation++;
          _data[key] = change.value;
          notifyListeners();
          return;
        }
        if (change.topic == barNotificationsSettingId) {
          unawaited(_refresh());
          return;
        }
        if (barOsdSettingIds.contains(change.topic)) {
          unawaited(_readOsdPreferences());
          return;
        }
        if (const {
              'display-brightness',
              displayGammaSettingId,
            }.contains(change.topic) &&
            _applyBrightnessChange(change)) {
          return;
        }
        if (const {
          airplaneEnabledSettingId,
          airplaneWifiSettingId,
          'sound',
          'power',
          'network',
          'bluetooth',
          'night-light',
          'display-brightness',
          displayGammaSettingId,
          barSidebarLayoutSettingId,
        }.contains(change.topic)) {
          unawaited(_refresh());
        }
      },
      onError: (Object error) => debugPrint('Sidebar Settings changes: $error'),
    );
    _poll ??= Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
    if (wasClosed) unawaited(_readOsdPreferences());
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
    if (_disposed ||
        _poll == null ||
        _refreshing ||
        _writing ||
        _queue.isNotEmpty) {
      return;
    }
    _refreshing = true;
    final generation = _generation;
    final output = _output;
    Future<void> read(String key, Future<Object?> request) async {
      Object? value;
      try {
        value = await request;
      } catch (error) {
        debugPrint('Sidebar $key: $error');
        if (key == 'layout' || key == 'notification-dnd') return;
      }
      if (!_disposed && _poll != null && generation == _generation) {
        _data[key] = value;
        if (key == 'brightness') {
          _confirmedBrightness = value as Map<String, Object?>?;
        }
        notifyListeners();
      }
    }

    try {
      await Future.wait([
        read('uptimeSeconds', system.sidebarUptime()),
        read('sound', _settings.readSound()),
        read('network', _settings.readNetwork()),
        read('airplane', _settings.readAirplane()),
        read('bluetooth', _settings.readBluetooth()),
        read('night-light', _settings.call('Get', ['night-light'])),
        read('power', _settings.readPower()),
        read('theme', _settings.call('Get', ['theme'])),
        read('keep-awake', _settings.readKeepAwake()),
        read(
          'notification-dnd',
          _preferences.readDoNotDisturb().then((value) => {'value': value}),
        ),
        read('layout', _preferences.readSidebarLayout()),
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

  BarOsdPreferences _osd = const BarOsdPreferences();

  Future<void> _readOsdPreferences() async {
    try {
      final preferences = await _preferences.readOsd();
      if (_disposed || _poll == null) return;
      _osd = preferences;
      _data['osd'] = preferences.toJson();
      notifyListeners();
    } catch (error) {
      debugPrint('Sidebar OSD preferences: $error');
    }
  }

  Future<int?> _readGamma() async {
    try {
      return await _display.readGamma();
    } catch (error) {
      debugPrint('Sidebar software brightness: $error');
      return null;
    }
  }

  Future<Map<String, Object?>> _brightness(String output) async {
    final gamma = _readGamma();
    final hardware = await _settings.call('Get', [
      'display-brightness:$output',
    ]);
    return {...hardware, 'output': output, 'gamma': await gamma};
  }

  bool _applyBrightnessChange(SettingsChange change) {
    final confirmed = _confirmedBrightness;
    if (confirmed == null || _output == null) return false;
    final value = change.value;
    final outputs = value['outputs'];
    final update = switch (change.topic) {
      displayGammaSettingId => {'gamma': value['gamma']},
      _ when value['output'] == _output => value,
      _ when outputs is List =>
        outputs
            .whereType<Map>()
            .where((item) => item['output'] == _output)
            .firstOrNull,
      _ => null,
    };
    if (update != null) {
      _generation++;
      final state = {...confirmed, ...Map<String, Object?>.from(update)};
      state.remove('outputs');
      _confirmedBrightness = state;
      _data['brightness'] = state;
      notifyListeners();
    }
    return true;
  }

  Future<void> perform(Map args, String? output) {
    if (_disposed) return Future.error(StateError('Sidebar is disposed'));
    _generation++;
    _predict(args, output);
    final action = args['action'];
    if (const {
      'sidebar.output-volume',
      'sidebar.input-volume',
      'sidebar.brightness',
    }.contains(action)) {
      final queued = _queue
          .where(
            (write) =>
                write.args['action'] == action &&
                write.args['target'] == args['target'],
          )
          .firstOrNull;
      if (queued != null) {
        queued.args = Map.of(args);
        queued.output = output;
        notifyListeners();
        return queued.result.future;
      }
    }
    final write = _SidebarWrite(Map.of(args), output);
    _queue.add(write);
    if (!_writing) unawaited(_drain());
    notifyListeners();
    return write.result.future;
  }

  Future<void> _drain() async {
    _writing = true;
    try {
      while (_queue.isNotEmpty) {
        final write = _queue.removeAt(0);
        try {
          if (_disposed) throw StateError('Sidebar is disposed');
          await _perform(write.args, write.output);
          write.result.complete();
        } catch (error, stack) {
          write.result.completeError(error, stack);
        }
      }
    } finally {
      _writing = false;
      unawaited(_refresh());
    }
  }

  void _predict(Map args, String? output) {
    final action = args['action'];
    final value = args['value'];
    final target = args['target'];
    Map copy(Object? value) => value is Map ? {...value} : {};
    void patch(String key, Map fields) =>
        _data[key] = {...copy(_data[key]), ...fields};
    switch (action) {
      case 'sidebar.output-volume' ||
              'sidebar.input-volume' ||
              'sidebar.output-muted' ||
              'sidebar.input-muted'
          when target is String:
        final volume = (action as String).endsWith('-volume');
        final maximum = action == 'sidebar.output-volume' ? 150 : 100;
        if (volume
            ? value is! num || !value.isFinite || value < 0 || value > maximum
            : value is! bool) {
          return;
        }
        final sound = copy(_data['sound']);
        final system = copy(sound['system']);
        final direction = _direction(action);
        system['devices'] = [
          for (final device in (system['devices'] as List? ?? const []))
            if (device is Map &&
                device['name'] == target &&
                device['direction'] == direction)
              {...device, 'preferences': _soundPreferences(device, value)}
            else
              device,
        ];
        _data['sound'] = {...sound, 'system': system};
      case 'sidebar.brightness' when output != null && output == target:
        final confirmed = _confirmedBrightness;
        if (confirmed?['output'] != output) return;
        if (value case {'gamma': final int gamma} when _validGamma(gamma)) {
          patch('brightness', {
            'gamma': gamma,
            if (confirmed?['percent'] is num) 'percent': 1,
          });
        } else if (_validHardware(value)) {
          patch('brightness', {
            'percent': value,
            if (confirmed?['gamma'] is num) 'gamma': 100,
          });
        }
      case 'sidebar.wifi' when value is bool:
        patch('network', {'wifi_enabled': value});
      case 'sidebar.bluetooth'
          when value is Map &&
              value['adapter'] is String &&
              value['enabled'] is bool:
        final bluetooth = copy(_data['bluetooth']);
        bluetooth['adapters'] = [
          for (final adapter in (bluetooth['adapters'] as List? ?? const []))
            if (adapter is Map && adapter['id'] == value['adapter'])
              {...adapter, 'powered': value['enabled']}
            else
              adapter,
        ];
        _data['bluetooth'] = bluetooth;
      case 'sidebar.night-light' when value is bool:
        patch('night-light', {'enabled': value});
      case 'sidebar.keep-awake' when value is bool:
        patch('keep-awake', {'value': value});
      case 'sidebar.dnd' when value is bool:
        patch('notification-dnd', {'value': value});
      case 'sidebar.dark' when value is bool:
        final theme = copy(_data['theme']);
        _data['theme'] = {
          ...theme,
          'theme': {
            ...copy(theme['theme']),
            'theme_mode': value ? 'dark' : 'light',
          },
        };
      case 'sidebar.profile' when value is String:
        final power = copy(_data['power']);
        _data['power'] = {
          ...power,
          'system': {...copy(power['system']), 'profile': value},
        };
    }
  }

  /// Predicts [_setVolume] and [_setMuted] for one device.
  Map _soundPreferences(Map device, Object? value) {
    final previous = device['preferences'];
    final preferences = previous is Map ? {...previous} : {};
    final channels = (preferences['channels'] as List? ?? const [])
        .whereType<int>()
        .toList();
    final max = channels.fold(0, (a, b) => a > b ? a : b);
    void level(num percent) {
      final wanted = (percent * 65536 / 100).round();
      preferences['channels'] = [
        for (final channel in channels)
          max == 0 ? wanted : (channel * wanted / max).round(),
      ];
      preferences['muted'] = percent.round() == 0;
    }

    if (value is num) {
      level(value);
    } else if (value == false && (max * 100 / 65536).round() == 0) {
      level(_osd.volumeStep);
    } else {
      preferences['muted'] = value;
    }
    return preferences;
  }

  static String _direction(String action) =>
      action.startsWith('sidebar.output-') ? 'output' : 'input';

  /// Zero volume and mute are one state: reaching 0 mutes and any audible
  /// level unmutes.
  Future<Map<String, Object?>> _setVolume(
    String direction,
    String name,
    num percent,
  ) async {
    final silent = percent.round() == 0;
    var sound = await _settings.changeSound('sound.$direction-volume', {
      'name': name,
      'percent': silent ? 0 : percent,
    });
    if ((_soundDevice(sound, direction, name)?['muted'] == true) != silent) {
      sound = await _settings.changeSound('sound.$direction-muted', {
        'name': name,
        'muted': silent,
      });
    }
    return sound;
  }

  /// Unmuting a silent device restores one volume step.
  Future<Map<String, Object?>> _setMuted(
    String direction,
    String name,
    bool muted,
  ) async {
    if (!muted) {
      // _data already holds the prediction, so check the confirmed level.
      final current = await _settings.readSound();
      final channels = _soundDevice(current, direction, name)?['channels'];
      if (channels is List &&
          channels.whereType<int>().every(
            (value) => value * 100 / 65536 < .5,
          )) {
        return _setVolume(direction, name, _osd.volumeStep);
      }
    }
    return _settings.changeSound('sound.$direction-muted', {
      'name': name,
      'muted': muted,
    });
  }

  static Map? _soundDevice(Object? sound, String direction, String name) {
    final system = sound is Map ? sound['system'] : null;
    final devices = system is Map ? system['devices'] : null;
    if (devices is! List) return null;
    for (final device in devices) {
      if (device is Map &&
          device['name'] == name &&
          device['direction'] == direction) {
        final preferences = device['preferences'];
        return preferences is Map ? preferences : null;
      }
    }
    return null;
  }

  Future<void> _perform(Map args, String? output) async {
    final action = args['action'];
    final value = args['value'];
    final target = args['target'];
    final (String key, Object? result) = switch (action) {
      'sidebar.brightness' when output != null && output == target => (
        'brightness',
        await _brightnessResult(output, value),
      ),
      'sidebar.output-volume' || 'sidebar.input-volume'
          when target is String &&
              value is num &&
              value.isFinite &&
              value >= 0 &&
              value <= (action == 'sidebar.output-volume' ? 150 : 100) =>
        (
          'sound',
          await _setVolume(_direction(action as String), target, value),
        ),
      'sidebar.output-muted' || 'sidebar.input-muted'
          when target is String && value is bool =>
        ('sound', await _setMuted(_direction(action as String), target, value)),
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
      'sidebar.airplane' when value is bool => (
        'airplane',
        await _settings.setAirplaneEnabled(value),
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
      'sidebar.dnd' when value is bool => (
        'notification-dnd',
        await _preferences.setDoNotDisturb(value),
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
        await _replaceSidebarLayout(target, value),
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
    if (!_disposed &&
        key.isNotEmpty &&
        (key != 'brightness' || _output == output)) {
      _data[key] = state;
      for (final write in _queue) {
        _predict(write.args, write.output);
      }
      notifyListeners();
    }
  }

  Future<Object> _replaceSidebarLayout(List expected, List tiles) {
    if (!listEquals(
      expected,
      _preferences.lastValid('sidebar-layout') as List?,
    )) {
      throw StateError('Changed in another view. Reopen the editor.');
    }
    return _preferences.replace(
      'sidebar-layout',
      tiles,
      _preferences.revision('sidebar-layout'),
    );
  }

  bool _validHardware(Object? value) =>
      value is num && value.isFinite && value >= 1 && value <= 100;

  bool _validGamma(int value) => value >= _osd.gammaMin && value <= 100;

  Future<Map<String, Object?>> _brightnessResult(
    String output,
    Object? value,
  ) async {
    var state = _confirmedBrightness;
    if (state == null || state['output'] != output) {
      state = await _brightness(output);
    }
    final result = Map<String, Object?>.of(state);
    Future<void> hardware(int percent) async {
      if (result['percent'] == percent) return;
      final actual = await _display.setBrightness(output, percent);
      if (actual == null) {
        throw StateError('Missing hardware brightness readback');
      }
      result['percent'] = actual;
    }

    Future<void> software(int gamma) async {
      if (result['gamma'] != gamma) {
        result['gamma'] = await _display.setGamma(gamma);
      }
    }

    try {
      if (value case {'gamma': final int gamma}
          when _validGamma(gamma) && result['gamma'] is num) {
        if (result['percent'] is num) await hardware(1);
        await software(gamma);
      } else if (_validHardware(value) && result['percent'] is num) {
        if (result['gamma'] is num && result['gamma'] != 100) {
          await software(100);
        }
        await hardware((value as num).round());
      } else {
        throw const FormatException('Invalid sidebar brightness');
      }
      return result;
    } finally {
      if (_output == output) {
        _confirmedBrightness = result;
        _data['brightness'] = result;
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    close();
    unawaited(_settings.close());
    super.dispose();
  }
}

class _SidebarWrite {
  _SidebarWrite(this.args, this.output);

  Map args;
  String? output;
  final result = Completer<void>();
}
