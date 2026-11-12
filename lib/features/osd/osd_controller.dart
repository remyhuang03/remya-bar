import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

import 'osd_slider.dart';

class OsdState {
  const OsdState({
    required this.type,
    required this.value,
    this.muted = false,
    this.preMuteValue,
    this.max = osdVolumeMax,
  });

  final OsdType type;
  final int value;
  final bool muted;
  final int? preMuteValue;
  final int max;

  Map<String, Object?> toData({double scale = 1.0}) => {
    'type': type.name,
    'value': value,
    'muted': muted,
    'preMuteValue': ?preMuteValue,
    'max': max,
    'scale': scale,
  };

  @override
  bool operator ==(Object other) =>
      other is OsdState &&
      other.type == type &&
      other.value == value &&
      other.muted == muted &&
      other.preMuteValue == preMuteValue &&
      other.max == max;

  @override
  int get hashCode => Object.hash(type, value, muted, preMuteValue, max);
}

class OsdController extends ChangeNotifier {
  OsdController({
    SettingsClient? settings,
    this.timeout = const Duration(milliseconds: 1500),
  }) : _settings = settings ?? SettingsClient(),
       _ownsSettings = settings == null;

  final SettingsClient _settings;
  final bool _ownsSettings;
  final Duration timeout;

  BarOsdPreferences preferences = const BarOsdPreferences();
  OsdState? state;

  String? _output;
  int _outputRevision = 0;
  int _serviceRevision = 0;
  final _shortcuts = <_ShortcutBatch>[];
  bool _drainingShortcuts = false;
  String? _volumeOutput;
  int? _volumePercent;
  bool? _volumeMuted;
  int? _preMuteVolume;

  int? _hwBrightness;
  bool _hardwareSupported = false;
  bool _brightnessInitialized = false;

  int? _gamma;

  bool _disposed = false;
  bool _writingVolume = false;
  bool _writingBrightness = false;
  Timer? _hideTimer;
  StreamSubscription<SettingsChange>? _changes;
  StreamSubscription<bool>? _serviceChanges;

  bool get visible => state != null;

  void start({String? output}) {
    if (_disposed || _changes != null) return;
    _output = output;
    _changes = _settings.changes.listen(
      _onSettingsChange,
      onError: (Object error) => debugPrint('OSD settings stream: $error'),
    );
    _serviceChanges = _settings.serviceAvailableChanges.listen(
      _onServiceChange,
      onError: (Object error) => debugPrint('OSD Settings owner: $error'),
    );
    unawaited(_initializeState());
  }

  void updateOutput(String? output) {
    if (_disposed || _output == output) return;
    _output = output;
    _resetBrightness();
    if (state?.type == .brightness) dismiss();
    unawaited(_refreshBrightness());
  }

  void _resetBrightness() {
    _outputRevision++;
    _hwBrightness = null;
    _hardwareSupported = false;
    _brightnessInitialized = false;
  }

  void _onServiceChange(bool available) {
    _serviceRevision++;
    _volumeOutput = null;
    _volumePercent = null;
    _volumeMuted = null;
    _preMuteVolume = null;
    _gamma = null;
    _resetBrightness();
    dismiss();
    if (available) unawaited(_initializeState());
  }

  Future<void> _initializeState() async {
    await Future.wait([
      _refreshPreferences(),
      _refreshSound(),
      _refreshBrightness(),
      _refreshGamma(),
    ]);
  }

  void _onSettingsChange(SettingsChange change) {
    if (_disposed) return;
    final topic = change.topic;
    if (barOsdSettingIds.contains(topic)) {
      unawaited(_refreshPreferences());
      return;
    }
    switch (topic) {
      case 'sound':
        if (!_writingVolume) {
          _applySoundPayload(change.value, showChanges: true);
        }
      case 'display-brightness' || 'display.5d419889':
        if (!_writingBrightness) {
          _applyBrightnessPayload(change.value, showChanges: true);
        }
      case 'display-gamma' || 'night-light':
        if (!_writingBrightness) {
          _applyGammaPayload(change.value, showChanges: true);
        }
    }
  }

  Future<void> _refreshPreferences() async {
    final revision = _serviceRevision;
    try {
      final next = await _settings.readBarOsdPreferences();
      if (_disposed || _serviceRevision != revision) return;
      preferences = next;
    } catch (error) {
      if (!_disposed) debugPrint('OSD preferences: $error');
    }
  }

  Future<void> _refreshSound() async {
    final revision = _serviceRevision;
    try {
      final sound = await _settings.readSound();
      if (_disposed || _serviceRevision != revision || _volumePercent != null) {
        return;
      }
      _applySoundPayload(sound);
    } catch (error) {
      if (!_disposed) debugPrint('OSD sound read: $error');
    }
  }

  void _applySoundPayload(
    Map<String, Object?> sound, {
    bool showChanges = false,
  }) {
    final system = sound['system'];
    final defaultOutput = system is Map ? system['default_output'] : null;
    final devices = system is Map ? system['devices'] : null;
    final device = devices is List
        ? devices.whereType<Map>().firstWhereOrNull(
            (item) =>
                item['name'] == defaultOutput && item['direction'] == 'output',
          )
        : null;
    final prefs = device?['preferences'];
    final channels = prefs is Map ? prefs['channels'] : null;
    final values = channels is List
        ? channels.whereType<int>().toList()
        : <int>[];
    if (sound['available'] != true ||
        defaultOutput is! String ||
        values.isEmpty) {
      _volumePercent = null;
      return;
    }
    final percent = (values.reduce(math.max) * 100 / 65536).round().clamp(
      0,
      150,
    );
    final muted = (prefs as Map)['muted'] == true;
    final hadBaseline = _volumePercent != null;
    final changed =
        _volumeOutput != defaultOutput ||
        _volumePercent != percent ||
        _volumeMuted != muted;
    if (!muted || _volumeOutput != defaultOutput) _preMuteVolume = percent;
    _volumeOutput = defaultOutput;
    _volumePercent = percent;
    _volumeMuted = muted;
    if (showChanges && hadBaseline && changed) _showVolume();
  }

  Future<void> _refreshBrightness() async {
    final output = _output;
    final revision = _outputRevision;
    if (output == null || output.isEmpty) return;
    try {
      final response = await _settings.call('Get', [
        'display-brightness:$output',
      ]);
      if (_disposed || _outputRevision != revision || _brightnessInitialized) {
        return;
      }
      _applyBrightnessPayload(response);
    } catch (error) {
      if (!_disposed) debugPrint('OSD brightness read: $error');
    }
  }

  int? _applyBrightnessPayload(
    Map<String, Object?> payload, {
    bool showChanges = false,
  }) {
    final output = _output;
    if (output == null || output.isEmpty) return null;
    final outputs = payload['outputs'];
    final item = payload['output'] == output
        ? payload
        : outputs is List
        ? outputs.whereType<Map>().firstWhereOrNull(
            (item) => item['output'] == output,
          )
        : null;
    if (item == null) return null;
    final rawPercent = item['percent'];
    final percent = rawPercent is int && rawPercent >= 0 && rawPercent <= 100
        ? rawPercent
        : null;
    final changed = _brightnessInitialized && _hwBrightness != percent;
    if (item.containsKey('backend')) {
      _hardwareSupported =
          item['backend'] == 'backlight' || item['backend'] == 'ddc';
      _brightnessInitialized = true;
    }
    _hwBrightness = percent;
    if (showChanges && changed && percent != null) {
      _show(OsdState(type: .brightness, value: percent));
    }
    return percent;
  }

  Future<void> _refreshGamma() async {
    final revision = _serviceRevision;
    try {
      final response = await _settings.call('Get', ['display-gamma']);
      if (_disposed || _serviceRevision != revision || _gamma != null) return;
      _applyGammaPayload(response);
    } catch (error) {
      if (!_disposed) debugPrint('OSD gamma read: $error');
    }
  }

  int? _applyGammaPayload(
    Map<String, Object?> payload, {
    bool showChanges = false,
  }) {
    final raw = payload['gamma'];
    if (raw is! int || raw < 1 || raw > 100) return null;
    final changed = _gamma != null && _gamma != raw;
    _gamma = raw;
    if (showChanges && changed) {
      _show(OsdState(type: .gamma, value: raw));
    }
    return raw;
  }

  Future<void> handleShortcut(String action) {
    if (_disposed) return Future.value();
    final pending = _shortcuts.lastOrNull;
    if (pending != null &&
        action != 'VolumeMute' &&
        pending.action == action &&
        pending.output == _outputRevision &&
        pending.service == _serviceRevision) {
      pending.count++;
      return pending.done.future;
    }
    final batch = _ShortcutBatch(action, _outputRevision, _serviceRevision);
    _shortcuts.add(batch);
    if (!_drainingShortcuts) unawaited(_drainShortcuts());
    return batch.done.future;
  }

  Future<void> _drainShortcuts() async {
    _drainingShortcuts = true;
    while (_shortcuts.isNotEmpty) {
      final batch = _shortcuts.removeAt(0);
      try {
        if (!_disposed && _serviceRevision == batch.service) {
          switch (batch.action) {
            case 'VolumeUp':
              await _changeVolume(preferences.volumeStep * batch.count);
            case 'VolumeDown':
              await _changeVolume(-preferences.volumeStep * batch.count);
            case 'VolumeMute':
              await _changeVolume(null);
            case 'BrightnessUp' when _outputRevision == batch.output:
              await _adjustBrightness(preferences.brightnessStep, batch.count);
            case 'BrightnessDown' when _outputRevision == batch.output:
              await _adjustBrightness(-preferences.brightnessStep, batch.count);
          }
        }
        batch.done.complete();
      } catch (error, stack) {
        batch.done.completeError(error, stack);
      }
      if (!_disposed) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    }
    _drainingShortcuts = false;
  }

  void _showVolume() {
    final percent = _volumePercent;
    if (percent == null) return;
    _show(
      OsdState(
        type: .volume,
        value: percent,
        muted: _volumeMuted == true || percent == 0,
        preMuteValue: _preMuteVolume,
        max: math.max(preferences.volumeMax, percent),
      ),
    );
  }

  /// Zero volume and mute are one state: stepping down to 0 mutes, and
  /// unmuting or stepping up from 0 restores at least one step.
  Future<void> _changeVolume(int? delta) async {
    final revision = _serviceRevision;
    if (_volumePercent == null) await _refreshSound();
    final current = _volumePercent;
    if (_disposed || _serviceRevision != revision || current == null) return;
    _writingVolume = true;
    try {
      final muted = _volumeMuted == true || current == 0;
      // An externally raised level above the ceiling is kept, not cut.
      final ceiling = math.max(preferences.volumeMax, current);
      final target = switch (delta) {
        null when muted && current == 0 => preferences.volumeStep,
        null => current,
        _ => (current + delta).clamp(0, ceiling),
      };
      final mute = delta == null ? !muted : target == 0 || (muted && delta < 0);
      Future<bool> write(String id, Map<String, Object?> value) async {
        final sound = await _settings.changeSound(id, value);
        if (_disposed || _serviceRevision != revision) return false;
        _applySoundPayload(sound);
        return true;
      }

      if (target != current &&
          !await write(soundOutputVolumeSettingId, {'percent': target})) {
        return;
      }
      if ((_volumeMuted == true) != mute &&
          !await write(soundOutputMutedSettingId, {'muted': mute})) {
        return;
      }
      _showVolume();
    } catch (error) {
      if (!_disposed && _serviceRevision == revision) {
        _volumePercent = null;
        debugPrint('OSD volume write: $error');
      }
    } finally {
      _writingVolume = false;
    }
  }

  Future<void> _adjustBrightness(int delta, int count) async {
    final revision = _outputRevision;
    final output = _output;
    if (output == null || output.isEmpty) return;
    if (!_brightnessInitialized) await _refreshBrightness();
    if (_disposed || _outputRevision != revision || !_brightnessInitialized) {
      return;
    }
    if (_gamma == null) await _refreshGamma();
    _writingBrightness = true;
    try {
      while (count > 0 && !_disposed && _outputRevision == revision) {
        final gamma = _gamma;
        if (gamma == null) return;
        final brightness = _hwBrightness;
        final hardware =
            _hardwareSupported &&
            brightness != null &&
            gamma == 100 &&
            (delta > 0 || brightness > 1);
        final current = hardware ? brightness : gamma;
        final floor = hardware ? 1 : math.min(gamma, preferences.gammaMin);
        final limit = delta > 0 ? 100 : floor;
        final type = hardware ? OsdType.brightness : OsdType.gamma;
        if (current == limit) {
          _show(OsdState(type: type, value: current));
          return;
        }
        final steps = math.min(
          count,
          ((limit - current).abs() / delta.abs()).ceil(),
        );
        final target = (current + steps * delta).clamp(floor, 100);
        final key = hardware
            ? 'display-brightness:$output'
            : displayGammaSettingId;
        final response = await _settings.call('Set', [key, '$target']);
        if (_disposed || _outputRevision != revision) return;
        final actual = hardware
            ? _applyBrightnessPayload(response)
            : _applyGammaPayload(response);
        if (actual == null) throw StateError('Missing brightness readback');
        _show(OsdState(type: type, value: actual));
        count -= steps;
      }
    } catch (error) {
      if (!_disposed && _outputRevision == revision) {
        _brightnessInitialized = false;
        _hwBrightness = null;
        _gamma = null;
        debugPrint('OSD brightness write: $error');
      }
    } finally {
      _writingBrightness = false;
    }
  }

  void _show(OsdState next) {
    if (_disposed) return;
    final changed = state != next;
    state = next;
    _hideTimer?.cancel();
    _hideTimer = Timer(timeout, dismiss);
    if (changed) notifyListeners();
  }

  void dismiss() {
    if (_disposed || state == null) return;
    _hideTimer?.cancel();
    _hideTimer = null;
    state = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _hideTimer?.cancel();
    unawaited(_changes?.cancel());
    unawaited(_serviceChanges?.cancel());
    if (_ownsSettings) unawaited(_settings.close());
    super.dispose();
  }
}

class _ShortcutBatch {
  _ShortcutBatch(this.action, this.output, this.service);

  final String action;
  final int output;
  final int service;
  final done = Completer<void>();
  int count = 1;
}
