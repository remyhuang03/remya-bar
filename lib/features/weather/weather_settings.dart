import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';

import '../settings/bar_settings_tiles.dart';
import 'weather_controller.dart';
import 'weather_location_picker.dart';
import 'weather_presentation.dart';

class WeatherSettings extends StatelessWidget {
  const WeatherSettings({super.key});

  void _pick(BuildContext context) => unawaited(
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const .all(24),
            child: WeatherLocationPicker(
              onClose: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final weather = WeatherController.instance;
    return ListenableBuilder(
      listenable: weather,
      builder: (context, _) {
        final settings = weather.settings;
        final location = weather.location;
        final busy = weather.savingSettings || !weather.ready;
        final format = WeatherFormat(context, settings);
        final followWeather = settings['appearance'] == 'weather';
        Widget toggle(
          String title,
          String key, {
          String? detail,
          bool allowed = true,
        }) => settingTile(
          title,
          detail: detail,
          control: Switch(
            value: settings[key] == true,
            onChanged: busy || !allowed
                ? null
                : (value) => weather.writeSettings({key: value}),
          ),
        );
        Widget choice<T extends Object>(
          String title,
          String key,
          Map<T, String> options, {
          String? detail,
        }) => settingTile(
          title,
          detail: detail,
          control: SettingChoice<T>(
            selected: settings[key] as T,
            choices: options,
            onSelected: busy
                ? null
                : (value) => weather.writeSettings({key: value}),
          ),
        );

        return Column(
          crossAxisAlignment: .stretch,
          spacing: 16,
          children: [
            for (final error in {
              weather.settingsError,
              weather.locationError,
            }.nonNulls)
              SettingsErrorCard(
                message: error,
                actionLabel: 'Reload',
                onRetry: weather.reload,
              ),
            SettingsGroup(
              title: 'Weather',
              children: [
                settingTile(
                  'Location',
                  detail: location == null
                      ? 'Choose a location'
                      : [
                          location.name,
                          weatherRegion(location),
                        ].where((label) => label.isNotEmpty).join(' · '),
                  control: FilledButton.tonal(
                    onPressed:
                        weather.locationRevision == null ||
                            weather.savingLocation
                        ? null
                        : () => _pick(context),
                    child: Text(location == null ? 'Add location' : 'Change'),
                  ),
                ),
              ],
            ),
            if (weather.saved.isNotEmpty)
              SettingsGroup(
                title: 'Saved locations',
                children: [
                  for (final entry in weather.saved)
                    settingTile(
                      entry.name,
                      detail: [
                        if (sameWeatherLocation(location, entry)) 'Active',
                        if (weatherRegion(entry).isNotEmpty)
                          weatherRegion(entry),
                      ].join(' · '),
                      control: Wrap(
                        spacing: 4,
                        crossAxisAlignment: .center,
                        children: [
                          if (!sameWeatherLocation(location, entry))
                            TextButton(
                              onPressed: weather.savingLocation
                                  ? null
                                  : () => weather.select(
                                      entry,
                                      weather.locationRevision!,
                                    ),
                              child: const Text('Use location'),
                            ),
                          IconButton(
                            tooltip: 'Remove ${entry.name}',
                            onPressed: weather.savingLocation
                                ? null
                                : () => weather.remove(entry),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            SettingsGroup(
              title: 'Units',
              children: [
                choice('Temperature', 'temperature', const {
                  'system': 'System',
                  'c': '°C',
                  'f': '°F',
                }, detail: 'Temperature unit · ${format.unit}'),
                choice('Wind speed', 'wind', const {
                  'km/h': 'km/h',
                  'm/s': 'm/s',
                  'mph': 'mph',
                  'kn': 'kn',
                }),
                choice(
                  'Precipitation',
                  'precipitation',
                  const {'mm': 'mm', 'in': 'in'},
                  detail: 'Precipitation probability is always shown as a percentage',
                ),
              ],
            ),
            SettingsGroup(
              title: 'Appearance',
              children: [
                choice('Weather appearance', 'appearance', const {
                  'weather': 'Follow weather',
                  'app': 'Use app theme',
                }),
                toggle(
                  'Color the weather pill',
                  'color-pill',
                  allowed: followWeather,
                ),
                choice('Pill content', 'pill', const {
                  'both': 'Icon + temperature',
                  'icon': 'Icon only',
                  'temperature': 'Temperature only',
                }),
                toggle(
                  'Show unit in pill',
                  'show-unit',
                  allowed: settings['pill'] != 'icon',
                ),
                choice('Default forecast', 'forecast', const {
                  'hourly': 'Hourly',
                  'daily': '7 days',
                }),
              ],
            ),
            SettingsGroup(
              title: 'Updates',
              children: [
                choice('Refresh interval', 'interval', const {
                  15: '15 min',
                  30: '30 min',
                  60: '60 min',
                }),
                toggle(
                  'Background refresh',
                  'background',
                  detail:
                      'Update the forecast while the weather card is closed',
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
