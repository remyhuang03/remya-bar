import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:remya_client/remya_client.dart';

import '../settings/bar_preferences.dart';
import 'weather_backend.dart';

/// The bar, popup and settings views live in the same Flutter engine.
class WeatherController extends ChangeNotifier {
  WeatherController._() {
    _client.changes.listen((change) {
      switch (change.topic) {
        case 'remya-bar.weather':
          unawaited(_readSettings());
        case 'remya-bar.weather-location':
          unawaited(_readLocation());
        case barLayoutSettingId:
          unawaited(_readLayout());
      }
    }, onError: (Object _) {});
    _client.serviceAvailableChanges.listen((available) {
      if (available) unawaited(reload());
    }, onError: (Object _) {});
    unawaited(reload());
  }

  static final instance = WeatherController._();

  final _client = SettingsClient();
  late final _preferences = BarPreferences(client: _client);
  late final backend = WeatherBackend(_preferences);

  Map<String, Object> settings = weatherDefaults;
  WeatherLocation? location;
  List<WeatherLocation> saved = const [];
  WeatherResult? result;
  String? settingsError;
  String? locationError;
  String? _settingsRevision;
  String? _locationRevision;
  int _settingsRead = 0;
  int _locationRead = 0;
  int _layoutRead = 0;
  bool _inLayout = false;
  int _generation = 0;
  int _openCards = 0;
  int _failures = 0;
  Timer? _timer;
  bool refreshing = false;
  bool savingSettings = false;
  bool savingLocation = false;
  final _sinceManual = Stopwatch();
  final _sinceFailure = Stopwatch();
  Duration _retryDelay = Duration.zero;
  bool _retryAfterRequired = false;
  final _random = Random();

  bool get ready => _settingsRevision != null && _locationRevision != null;

  bool get enabled => _inLayout;
  bool get _automatic => settings['background'] == true || _openCards > 0;
  int get minutes => settings['interval'] as int;
  WeatherSnapshot? get snapshot => result?.snapshot;
  Duration? get age => snapshot == null
      ? null
      : DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(snapshot!.fetchedAt * 1000),
        );
  bool get stale =>
      result?.error != null ||
      (age?.inMinutes ?? 0) >=
          (settings['background'] == true ? max(30, minutes * 2) : 30);
  bool get canRefresh =>
      enabled &&
      location != null &&
      !refreshing &&
      !(_retryAfterRequired && _sinceFailure.elapsed < _retryDelay) &&
      (!_sinceManual.isRunning || _sinceManual.elapsed.inSeconds >= 60);

  bool get rateLimited => result?.error?.contains('HTTP 429') == true;

  Future<void> reload() async {
    await Future.wait([_readSettings(), _readLocation(), _readLayout()]);
  }

  Future<void> _readLayout() async {
    final request = ++_layoutRead;
    try {
      final layout = await _preferences.readLayout();
      if (request != _layoutRead) return;
      final next = !layout.hidden.contains('weather');
      if (next != _inLayout) {
        _inLayout = next;
        _reset();
        notifyListeners();
      }
    } catch (_) {
      // Retain the last known layout state until the next signal or reload.
    }
  }

  Future<void> _readSettings() async {
    if (savingSettings) return;
    final request = ++_settingsRead;
    try {
      final value = await _preferences.read('weather') as Map<String, Object>;
      if (request != _settingsRead || savingSettings) return;
      _applySettings(value, _preferences.revision('weather'));
    } catch (error) {
      if (request != _settingsRead || savingSettings) return;
      settingsError = 'Could not load weather settings.';
      notifyListeners();
    }
  }

  void _applySettings(Map<String, Object> value, String revision) {
    final changed = !mapEquals(settings, value) || _settingsRevision == null;
    final automatic = _automatic;
    final interval = minutes;
    settings = value;
    _settingsRevision = revision;
    settingsError = null;
    if (changed && (automatic != _automatic || interval != minutes)) {
      _schedule();
    }
    notifyListeners();
  }

  Future<void> writeSettings(Map<String, Object> updates) async {
    final revision = _settingsRevision;
    if (revision == null || savingSettings) return;
    savingSettings = true;
    notifyListeners();
    try {
      final value = await _preferences.replace('weather', {
        ...settings,
        ...updates,
      }, revision) as Map<String, Object>;
      _applySettings(value, _preferences.revision('weather'));
    } catch (error) {
      settingsError = 'Could not save weather settings. Reload and try again.';
    } finally {
      savingSettings = false;
      notifyListeners();
    }
  }

  Future<void> _readLocation() async {
    if (savingLocation) return;
    final request = ++_locationRead;
    try {
      final value = await backend.readLocation();
      if (request != _locationRead || savingLocation) return;
      _applyLocation(value);
    } catch (error) {
      if (request != _locationRead || savingLocation) return;
      locationError = 'Could not load weather locations.';
      notifyListeners();
    }
  }

  void _applyLocation(
    ({WeatherLocation? location, List<WeatherLocation> saved, String revision})
    value,
  ) {
    final changed = location != value.location;
    location = value.location;
    saved = value.saved;
    _locationRevision = value.revision;
    locationError = null;
    if (changed) _reset();
    notifyListeners();
  }

  Future<bool> select(WeatherLocation selected, String revision) =>
      _saveLocation(
        selected,
        [
          selected,
          ...saved.where((value) => !sameWeatherLocation(value, selected)),
        ].take(50).toList(),
        revision,
      );

  Future<bool> remove(WeatherLocation entry) => _saveLocation(
    sameWeatherLocation(location, entry) ? null : location,
    saved.where((value) => !sameWeatherLocation(value, entry)).toList(),
    _locationRevision!,
  );

  String? get locationRevision => _locationRevision;

  Future<bool> _saveLocation(
    WeatherLocation? next,
    List<WeatherLocation> history,
    String revision,
  ) async {
    if (savingLocation) return false;
    savingLocation = true;
    locationError = null;
    notifyListeners();
    try {
      await backend.saveLocation(next, history, revision);
      _applyLocation(await backend.readLocation());
      return true;
    } catch (error) {
      locationError = 'Could not save the location. Reload and try again.';
      return false;
    } finally {
      savingLocation = false;
      notifyListeners();
    }
  }

  void showForecast() {
    _openCards++;
    if (_openCards == 1 && settings['background'] != true) _schedule();
  }

  void hideForecast() {
    _openCards--;
    if (!_automatic) _schedule();
  }

  void _reset() {
    final generation = ++_generation;
    result = null;
    refreshing = false;
    _failures = 0;
    _sinceFailure.stop();
    _retryAfterRequired = false;
    _sinceManual
      ..stop()
      ..reset();
    _timer?.cancel();
    final selected = location;
    if (!enabled || selected == null) return;
    unawaited(_loadCached(selected, generation));
  }

  Future<void> _loadCached(WeatherLocation selected, int generation) async {
    try {
      final value = await backend.cached(selected);
      if (generation != _generation) return;
      if (!refreshing && result == null && value.snapshot != null) {
        result = value;
      }
    } catch (_) {
      if (generation != _generation) return;
    }
    _schedule();
    notifyListeners();
  }

  void _schedule() {
    _timer?.cancel();
    if (!enabled || location == null || refreshing) return;
    final waiting = _failures > 0 && _sinceFailure.elapsed < _retryDelay;
    final cacheAge = age;
    final expired =
        cacheAge == null ||
        cacheAge.isNegative ||
        cacheAge.inMinutes >= minutes;
    if (_automatic && !waiting && (expired || _failures > 0)) {
      _timer = Timer(Duration.zero, () => unawaited(refresh()));
      return;
    }
    // Update timestamps and button cooldown even when background fetching is off.
    _timer = Timer(const Duration(seconds: 15), () {
      if ((age?.inHours ?? 0) >= 24) {
        result = WeatherResult(status: .unavailable, error: result?.error);
      }
      notifyListeners();
      _schedule();
    });
  }

  Future<void> refresh({bool manual = false}) async {
    final selected = location;
    if (!enabled || selected == null || refreshing || (manual && !canRefresh)) {
      return;
    }
    final generation = _generation;
    _timer?.cancel();
    refreshing = true;
    if (manual) {
      _sinceManual
        ..reset()
        ..start();
    }
    notifyListeners();
    WeatherResult value;
    try {
      value = await backend.refresh(selected, force: manual);
    } catch (error) {
      final cached = (age?.inHours ?? 24) < 24 ? snapshot : null;
      value = WeatherResult(
        status: cached == null ? .unavailable : .stale,
        snapshot: cached,
        error: error.toString(),
      );
    }
    if (generation != _generation) return;
    refreshing = false;
    result = value;
    if (value.snapshot != null && value.error == null) {
      _failures = 0;
      _sinceFailure.stop();
      _retryAfterRequired = false;
    } else {
      const delays = [1, 2, 5, 15];
      final retryAfter = int.tryParse(
        value.error?.split('; retry after ').last ?? '',
      );
      _retryAfterRequired = rateLimited || retryAfter != null;
      _retryDelay = retryAfter != null
          ? Duration(seconds: retryAfter.clamp(1, 86400))
          : Duration(
              minutes: rateLimited
                  ? 15
                  : delays[min(_failures, delays.length - 1)],
              seconds: _random.nextInt(16),
            );
      _failures++;
      _sinceFailure
        ..reset()
        ..start();
    }
    _schedule();
    notifyListeners();
  }
}

bool sameWeatherLocation(WeatherLocation? a, WeatherLocation b) =>
    a != null &&
    (a.id != null && b.id != null
        ? a.id == b.id
        : a.latitude == b.latitude && a.longitude == b.longitude);

String weatherRegion(WeatherLocation location) =>
    [location.region, location.country].nonNulls.toSet().join(', ');
