import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../bar_theme.dart';
import '../popups/bar_popup.dart';
import '../settings/bar_settings_entry.dart';
import 'weather_backend.dart';
import 'weather_controller.dart';
import 'weather_location_picker.dart';
import 'weather_presentation.dart';

part 'weather_forecast.dart';

class WeatherCard extends StatefulWidget {
  const WeatherCard({
    super.key,
    this.compact = false,
    this.onSettings,
    this.controller,
  });
  final VoidCallback? onSettings;
  final WeatherController? controller;
  final bool compact;

  @override
  State<WeatherCard> createState() => _WeatherCardState();
}

class _WeatherCardState extends State<WeatherCard> {
  late final _weather = widget.controller ?? WeatherController.instance;
  bool? _daily;
  bool _expanded = false;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _weather.showForecast();
  }

  @override
  void dispose() {
    _weather.hideForecast();
    super.dispose();
  }

  void _pick(bool value) => setState(() => _picking = value);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _weather,
    builder: (context, _) {
      if (widget.compact && !_weather.enabled) return const SizedBox.shrink();
      if (_picking) {
        return WeatherLocationPicker(
          controller: _weather,
          onClose: () => _pick(false),
        );
      }
      final format = WeatherFormat(context, _weather.settings);
      final snapshot = _weather.snapshot;
      final daily = _daily ?? (_weather.settings['forecast'] == 'daily');
      final full = !widget.compact || _expanded;
      final theme = Theme.of(context);
      if (!widget.compact) return _body(context, snapshot, format, daily, full);
      final scope = BarPopupScope.themeOf(context);
      final seed = currentWeatherSeed(_weather);
      final colors = seed == null
          ? theme.colorScheme
          : ColorScheme.fromSeed(
              seedColor: seed,
              brightness: theme.brightness,
              dynamicSchemeVariant: scope.styleVariant,
              contrastLevel: scope.contrast.level,
            );
      return Material(
        color: colors.surfaceContainerHigh,
        borderRadius: .circular(28),
        child: Theme(
          data: theme.copyWith(colorScheme: colors),
          child: Padding(
            padding: const .all(16),
            child: Builder(
              builder: (context) =>
                  _body(context, snapshot, format, daily, full),
            ),
          ),
        ),
      );
    },
  );

  Widget _body(
    BuildContext context,
    WeatherSnapshot? snapshot,
    WeatherFormat format,
    bool daily,
    bool full,
  ) {
    final location = _weather.location;
    final current = snapshot?.current;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final age = _weather.age;
    final currentOld =
        current != null &&
        DateTime.now().millisecondsSinceEpoch ~/ 1000 - current.validAt >
            6 * 3600;
    final stale = snapshot != null && _weather.stale;
    final subtitle = location == null ? '' : weatherRegion(location);
    final unavailable = _weather.result != null && snapshot == null;
    final today = snapshot == null
        ? ''
        : _dateLabel(
            format.localDateTime(
              DateTime.now().millisecondsSinceEpoch ~/ 1000,
              snapshot.timezone,
            ),
          );
    final todayWeather = snapshot?.daily
        .where((day) => day.date == today)
        .firstOrNull;
    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      spacing: 16,
      children: [
        if (stale)
          _WeatherBanner(
            title: _weather.rateLimited
                ? 'Updates paused · Try again later'
                : _weather.result?.error != null
                ? 'Couldn’t refresh · Showing saved weather'
                : 'Showing saved weather',
            detail: age == null ? null : 'Last retrieved ${format.age(age)}',
            icon: Icons.cloud_off_rounded,
            retry: _weather.canRefresh
                ? () => _weather.refresh(manual: true)
                : null,
          ),
        _WeatherHeader(
          title: snapshot == null ? 'Weather' : location!.name,
          subtitle: snapshot == null ? location?.name : subtitle,
          refresh: _weather.canRefresh
              ? () => _weather.refresh(manual: true)
              : null,
          busy: _weather.refreshing,
          settings:
              widget.onSettings ??
              () => unawaited(openBarSettings(page: 'weather')),
        ),
        if (snapshot == null)
          if (location == null)
            _WeatherMessage(
              icon: Icons.location_on_outlined,
              title: 'Choose a location',
              detail: 'Weather follows the place you choose. Search by city or postal code.',
              label: 'Add location',
              action: () => _pick(true),
            )
          else if (unavailable)
            _WeatherMessage(
              icon: Icons.cloud_off_rounded,
              title: _weather.rateLimited
                  ? 'Updates paused'
                  : 'Weather unavailable',
              detail: _weather.rateLimited ? 'Try again later.' : 'We could not load weather. Check your connection and try again.',
              label: 'Retry',
              action: _weather.canRefresh
                  ? () => _weather.refresh(manual: true)
                  : null,
            )
          else
            _WeatherMessage(
              icon: Icons.sync_rounded,
              title: 'Loading weather',
              detail: 'Getting the latest model forecast for ${location.name}…',
            )
        else ...[
          _WeatherHero(
            current: current,
            day: todayWeather,
            snapshot: snapshot,
            format: format,
            lastConditions: currentOld,
          ),
          if (full) ...[
            if (!stale &&
                (current == null ||
                    snapshot.hourly.isEmpty ||
                    snapshot.daily.isEmpty))
              const _WeatherBanner(
                title: 'Some forecast data is missing',
                detail: 'Missing fields are shown as —.',
                icon: Icons.info_outline_rounded,
              ),
            _WeatherMetrics(current: current, format: format),
            _ForecastTabs(
              daily: daily,
              onChange: (value) => setState(() => _daily = value),
            ),
            if (daily)
              _DailyForecast(days: snapshot.daily, today: today, format: format)
            else
              _HourlyForecast(
                key: ValueKey(location),
                snapshot: snapshot,
                format: format,
                lastConditions: currentOld,
              ),
          ],
          if (widget.compact)
            Align(
              alignment: .centerLeft,
              child: TextButton(
                onPressed: () {
                  setState(() => _expanded = !_expanded);
                },
                child: Text(_expanded ? 'Show less' : 'Show forecast'),
              ),
            ),
        ],
        Wrap(
          alignment: .spaceBetween,
          crossAxisAlignment: .center,
          spacing: 8,
          children: [
            if (snapshot != null && age != null)
              Text(
                'Retrieved ${format.age(age)}'
                '${current == null ? '' : ' · valid at ${format.time(current.validAt, snapshot.timezone)}'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            TextButton(
              onPressed: () => unawaited(
                Process.start('xdg-open', [
                  'https://open-meteo.com/',
                ], mode: .detached).then<void>(
                  (_) {},
                  onError: (Object error) {
                    debugPrint('Opening weather attribution: $error');
                  },
                ),
              ),
              style: TextButton.styleFrom(
                padding: .zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: .shrinkWrap,
              ),
              child: Text(snapshot == null ? weatherSource : 'Open-Meteo'),
            ),
          ],
        ),
      ],
    );
  }
}

Color? currentWeatherSeed(WeatherController weather) =>
    weather.settings['appearance'] == 'weather'
    ? weatherSeed(weather.snapshot?.current?.condition)
    : null;

String _dateLabel(DateTime local) =>
    '${local.year.toString().padLeft(4, '0')}'
    '-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';

class _WeatherHeader extends StatelessWidget {
  const _WeatherHeader({
    required this.title,
    this.subtitle,
    this.refresh,
    required this.busy,
    required this.settings,
  });
  final String title;
  final String? subtitle;
  final VoidCallback? refresh;
  final bool busy;
  final VoidCallback settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      spacing: 8,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            children: [
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: .bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              if (subtitle case final label? when label.isNotEmpty)
                Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: busy ? 'Refreshing weather' : 'Refresh weather',
          style: _actionStyle,
          onPressed: busy ? null : refresh,
          icon: busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded, size: 20),
        ),
        IconButton.filledTonal(
          tooltip: 'Weather settings',
          style: _actionStyle,
          onPressed: settings,
          icon: const Icon(Icons.settings_outlined, size: 20),
        ),
      ],
    );
  }

  static final _actionStyle = IconButton.styleFrom(
    fixedSize: const Size.square(40),
    minimumSize: const Size.square(40),
    tapTargetSize: .shrinkWrap,
  );
}

class _WeatherBanner extends StatelessWidget {
  const _WeatherBanner({
    required this.title,
    this.detail,
    required this.icon,
    this.retry,
  });
  final String title;
  final String? detail;
  final IconData icon;
  final VoidCallback? retry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.secondaryContainer,
      borderRadius: .circular(16),
      child: Padding(
        padding: const .all(12),
        child: Row(
          spacing: 12,
          children: [
            Icon(icon, size: 20),
            Expanded(
              child: Text(
                [title, ?detail].join('\n'),
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (retry != null)
              TextButton(onPressed: retry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _WeatherMessage extends StatelessWidget {
  const _WeatherMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.label,
    this.action,
  });
  final IconData icon;
  final String title;
  final String detail;
  final String? label;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const .symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 12,
        children: [
          Icon(icon, size: 32),
          Text(title, style: theme.textTheme.titleMedium),
          Text(
            detail,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (label != null)
            FilledButton.tonal(onPressed: action, child: Text(label!)),
        ],
      ),
    );
  }
}

class _WeatherHero extends StatelessWidget {
  const _WeatherHero({
    required this.current,
    required this.day,
    required this.snapshot,
    required this.format,
    required this.lastConditions,
  });
  final WeatherCurrent? current;
  final WeatherDay? day;
  final WeatherSnapshot snapshot;
  final WeatherFormat format;
  final bool lastConditions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final nextSun = switch ((day?.sunrise, day?.sunset)) {
      (final sunrise?, _) when sunrise > now => ('Sunrise', sunrise),
      (_, final sunset?) when sunset > now => ('Sunset', sunset),
      _ => (
        'Sunrise',
        snapshot.daily
            .where((day) => (day.sunrise ?? 0) > now)
            .firstOrNull
            ?.sunrise,
      ),
    };
    final solar = nextSun.$2;
    final condition = weatherCondition(
      current?.condition,
      current?.weatherCode,
    );
    final temperature = format.temperature(current?.temperatureC);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: .circular(28),
      ),
      child: Padding(
        padding: const .all(20),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: colors.onPrimaryContainer),
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: 12,
            children: [
              Row(
                spacing: 4,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      children: [
                        if (lastConditions) const Text('Last conditions'),
                        Semantics(
                          label: temperature == '—'
                              ? 'Temperature unavailable'
                              : '${temperature.replaceAll('°', '')} ${format.spokenUnit}',
                          excludeSemantics: true,
                          child: Text(
                            temperature,
                            style: theme.textTheme.displayLarge?.copyWith(
                              color: colors.onPrimaryContainer,
                              fontFamily: barFontFamily,
                              fontWeight: .w400,
                              fontSize: 64,
                              height: 1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          condition,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colors.onPrimaryContainer,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                  WeatherIcon(current?.condition, size: 88),
                ],
              ),
              Wrap(
                alignment: .spaceBetween,
                crossAxisAlignment: .center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text('Feels like ${format.temperature(current?.feelsLikeC)}'),
                  Text(
                    '${format.temperature(day?.highC)} / ${format.temperature(day?.lowC)}'
                    ' · ${nextSun.$1} ${solar == null ? '—' : format.time(solar, snapshot.timezone)}',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeatherMetrics extends StatelessWidget {
  const _WeatherMetrics({required this.current, required this.format});
  final WeatherCurrent? current;
  final WeatherFormat format;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final values = {
        'Humidity': format.probability(current?.humidityPercent),
        'Wind': format.wind(current?.windKmh, null),
        'Precipitation': format.probability(current?.precipitationProbability),
      };
      const gap = 8.0;
      final wide =
          constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) >=
          345;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final MapEntry(:key, :value) in values.entries)
            SizedBox(
              width: wide
                  ? (constraints.maxWidth - 2 * gap) / 3
                  : constraints.maxWidth,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: .circular(20),
                  color: theme.colorScheme.surfaceContainerHigh,
                ),
                child: Padding(
                  padding: const .symmetric(horizontal: 14, vertical: 14),
                  child: Tooltip(
                    message: value == '—'
                        ? 'Not available'
                        : key == 'Precipitation'
                        ? 'Precipitation probability'
                        : key == 'Wind' && current?.windDirection != null
                        ? 'Wind ${format.wind(current?.windKmh, current?.windDirection)}'
                        : '',
                    child: Semantics(
                      label:
                          '${key == 'Precipitation' ? 'Precipitation probability' : key}, '
                          '${value == '—'
                              ? 'unavailable'
                              : key == 'Wind'
                              ? format.wind(current?.windKmh, current?.windDirection)
                              : value}',
                      excludeSemantics: true,
                      child: Column(
                        crossAxisAlignment: .start,
                        children: [
                          Text(key, style: theme.textTheme.bodySmall),
                          Text(
                            value,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: .w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
