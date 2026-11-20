import 'dart:async';

import 'package:remya_bar/features/settings/bar_preferences.dart';
import 'package:remya_bar/features/system/system_backend.dart';
import 'package:remya_bar/src/rust/system_bridge/api.dart' as api;

export 'package:remya_bar/src/rust/system_bridge/api.dart'
    show
        WeatherCondition,
        WeatherCurrent,
        WeatherDay,
        WeatherHour,
        WeatherLocation,
        WeatherResult,
        WeatherSnapshot,
        WeatherStatus;

class WeatherBackend {
  WeatherBackend(this._preferences);

  final BarPreferences _preferences;

  /// The location and revision belong to the same read.
  Future<({api.WeatherLocation? location, String revision})>
  readLocation() async {
    final (:value, :revision) = await _preferences
        .readWeatherLocationPreference();
    return (
      location: value.isEmpty
          ? null
          : api.WeatherLocation(
              id: value['id'] as int?,
              name: value['name'] as String,
              region: value['region'] as String?,
              country: value['country'] as String?,
              latitude: (value['latitude'] as num).toDouble(),
              longitude: (value['longitude'] as num).toDouble(),
            ),
      revision: revision,
    );
  }

  /// Use a null location to clear the selection, or supply a label and
  /// coordinates for a manually entered location.
  Future<void> saveLocation(api.WeatherLocation? location, String revision) =>
      _preferences.replace(barWeatherLocationKey, {
        if (location != null) ...{
          'name': location.name,
          'latitude': location.latitude,
          'longitude': location.longitude,
          'id': ?location.id,
          'region': ?location.region,
          'country': ?location.country,
        },
      }, revision);

  Future<List<api.WeatherLocation>> search(
    String query, {
    String language = 'en',
  }) async {
    await SystemBackend.initialize();
    return api.weatherSearch(query: query, language: language);
  }

  Future<api.WeatherResult> refresh(
    api.WeatherLocation location, {
    bool force = false,
  }) async {
    await SystemBackend.initialize();
    return api.weatherRefresh(
      latitude: location.latitude,
      longitude: location.longitude,
      force: force,
    );
  }

  /// Polls only while subscribed. Rust shares refreshes across views.
  Stream<api.WeatherResult> watch(api.WeatherLocation location) async* {
    yield await refresh(location);
    yield* Stream<void>.periodic(const Duration(minutes: 1))
        .asyncMap((_) => refresh(location));
  }
}
