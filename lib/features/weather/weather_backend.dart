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

  Future<
    ({
      api.WeatherLocation? location,
      List<api.WeatherLocation> saved,
      String revision,
    })
  >
  readLocation() async {
    final (:value, :revision) = await _preferences
        .readWeatherLocationPreference();
    final location = value.containsKey('name') ? _location(value) : null;
    final saved = ((value['saved'] as List?) ?? const [])
        .map(_location)
        .toList();
    if (location != null && !saved.contains(location)) {
      saved.insert(0, location);
    }
    return (location: location, saved: saved, revision: revision);
  }

  Future<void> saveLocation(
    api.WeatherLocation? location,
    List<api.WeatherLocation> saved,
    String revision,
  ) => _preferences.replace(barWeatherLocationKey, {
    if (location != null) ..._locationJson(location),
    if (saved.isNotEmpty) 'saved': saved.map(_locationJson).toList(),
  }, revision);

  Future<List<api.WeatherLocation>> search(
    String query, {
    required String language,
    String? countryCode,
  }) async {
    await SystemBackend.initialize();
    return api.weatherSearch(
      query: query,
      language: language,
      countryCode: countryCode,
    );
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

  Future<api.WeatherResult> cached(api.WeatherLocation location) async {
    await SystemBackend.initialize();
    return api.weatherCached(
      latitude: location.latitude,
      longitude: location.longitude,
    );
  }
}

api.WeatherLocation _location(Object? value) {
  final map = value as Map;
  return .new(
    id: map['id'] as int?,
    name: map['name'] as String,
    region: map['region'] as String?,
    country: map['country'] as String?,
    timezone: map['timezone'] as String?,
    latitude: (map['latitude'] as num).toDouble(),
    longitude: (map['longitude'] as num).toDouble(),
  );
}

Map<String, Object> _locationJson(api.WeatherLocation location) => {
  'name': location.name,
  'latitude': location.latitude,
  'longitude': location.longitude,
  'id': ?location.id,
  'region': ?location.region,
  'country': ?location.country,
  'timezone': ?location.timezone,
};
