part of 'weather_card.dart';

class _ForecastTabs extends StatelessWidget {
  const _ForecastTabs({required this.daily, required this.onChange});
  final bool daily;
  final ValueChanged<bool> onChange;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      spacing: 3,
      children: [
        for (final (label, value, icon) in const [
          ('Hourly', false, Icons.schedule_rounded),
          ('7 days', true, Icons.calendar_today_outlined),
        ])
          Expanded(
            child: Semantics(
              selected: value == daily,
              child: FilledButton.icon(
                onPressed: () => onChange(value),
                style: FilledButton.styleFrom(
                  padding: const .symmetric(horizontal: 8, vertical: 10),
                  tapTargetSize: .shrinkWrap,
                  visualDensity: .standard,
                  textStyle: const TextStyle(
                    fontFamily: barFontFamily,
                    fontSize: 13,
                    fontWeight: .w400,
                  ),
                  minimumSize: const Size(0, 40),
                  foregroundColor: value == daily
                      ? colors.onPrimary
                      : colors.onSurfaceVariant,
                  backgroundColor: value == daily
                      ? colors.primary
                      : colors.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
                    borderRadius: value == daily
                        ? .circular(18)
                        : BorderRadius.horizontal(
                            left: Radius.circular(value ? 6 : 18),
                            right: Radius.circular(value ? 18 : 6),
                          ),
                  ),
                ),
                icon: Icon(icon, size: 18),
                label: Text(label, textAlign: .center),
              ),
            ),
          ),
      ],
    );
  }
}

class _HourlyForecast extends StatefulWidget {
  const _HourlyForecast({
    super.key,
    required this.snapshot,
    required this.format,
    required this.lastConditions,
  });
  final WeatherSnapshot snapshot;
  final WeatherFormat format;
  final bool lastConditions;

  @override
  State<_HourlyForecast> createState() => _HourlyForecastState();
}

class _HourlyForecastState extends State<_HourlyForecast> {
  final _scroll = ScrollController();
  int? _selected;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollWithWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.kind != .mouse ||
        event.scrollDelta.dx != 0 ||
        !_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    final delta = axisDirectionIsReversed(position.axisDirection)
        ? -event.scrollDelta.dy
        : event.scrollDelta.dy;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    // At either edge, let the wheel continue scrolling the card vertically.
    if (target == position.pixels) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      position.pointerScroll(delta);
      event.respond(allowPlatformDefault: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.snapshot.current;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final hours = [
      if (current != null)
        WeatherHour(
          validAt: current.validAt,
          temperatureC: current.temperatureC,
          condition: current.condition,
          weatherCode: current.weatherCode,
          precipitationProbability: current.precipitationProbability,
        ),
      ...widget.snapshot.hourly.where(
        (hour) =>
            hour.validAt > (current?.validAt ?? 0) &&
            (!widget.lastConditions || hour.validAt > now),
      ),
    ];
    if (hours.isEmpty) return const Text('Hourly forecast unavailable');
    final format = widget.format;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = hours.any((hour) => hour.validAt == _selected)
        ? _selected
        : hours.first.validAt;
    final list = Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        scrollDirection: .horizontal,
        controller: _scroll,
        padding: const .only(bottom: 12),
        child: Row(
          spacing: 4,
          children: [
            for (final hour in hours)
              Builder(
                builder: (context) {
                  final active = hour.validAt == selected;
                  final time = hour.validAt == current?.validAt
                      ? widget.lastConditions
                            ? 'Last'
                            : 'Now'
                      : format.forecastHour(
                          hour.validAt,
                          widget.snapshot.timezone,
                        );
                  final temperature = format.temperature(hour.temperatureC);
                  final precip = format.probability(
                    hour.precipitationProbability,
                  );
                  return Semantics(
                    selected: active,
                    button: true,
                    onTap: () => setState(() => _selected = hour.validAt),
                    label:
                        '$time, ${weatherCondition(hour.condition, hour.weatherCode)}, '
                        '${format.temperature(hour.temperatureC, withUnit: true)}, '
                        'precipitation probability $precip, '
                        'precipitation amount ${format.precipitation(hour.precipitationMm)}',
                    excludeSemantics: true,
                    child: Material(
                      color: active
                          ? colors.primaryContainer
                          : Colors.transparent,
                      borderRadius: .circular(30),
                      child: InkWell(
                        borderRadius: .circular(30),
                        onTap: () => setState(() => _selected = hour.validAt),
                        onFocusChange: (focused) {
                          if (focused) {
                            Scrollable.ensureVisible(
                              context,
                              alignmentPolicy: .keepVisibleAtEnd,
                            );
                          }
                        },
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 58,
                            minHeight: 128,
                          ),
                          child: Padding(
                            padding: const .symmetric(
                              horizontal: 4,
                              vertical: 12,
                            ),
                            child: Column(
                              mainAxisAlignment: .spaceAround,
                              spacing: 4,
                              children: [
                                Text(time, style: theme.textTheme.bodySmall),
                                WeatherIcon(hour.condition, size: 32),
                                Text(
                                  temperature,
                                  style: theme.textTheme.titleMedium,
                                ),
                                Tooltip(
                                  message: hour.precipitationMm == null
                                      ? 'Precipitation amount not available'
                                      : 'Precipitation amount ${format.precipitation(hour.precipitationMm)}',
                                  child: Text(
                                    precip,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
    return Listener(onPointerSignal: _scrollWithWheel, child: list);
  }
}

class _DailyForecast extends StatelessWidget {
  const _DailyForecast({
    required this.days,
    required this.today,
    required this.format,
  });
  final List<WeatherDay> days;
  final String today;
  final WeatherFormat format;

  @override
  Widget build(BuildContext context) {
    final forecast = days
        .where((day) => day.date.compareTo(today) >= 0)
        .toList();
    if (forecast.isEmpty) return const Text('Daily forecast unavailable');
    final range = [
      for (final day in forecast) ...[?day.lowC, ?day.highC],
    ];
    final low = range.isEmpty ? 0.0 : range.reduce(math.min);
    final high = range.isEmpty ? 0.0 : range.reduce(math.max);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      children: [
        for (final day in forecast)
          Builder(
            builder: (context) {
              final label = day.date == today
                  ? 'Today'
                  : format.weekday(day.date);
              final minTemp = format.temperature(day.lowC);
              final maxTemp = format.temperature(day.highC);
              final precip = format.probability(day.precipitationProbability);
              return Semantics(
                label:
                    '$label, ${weatherCondition(day.condition, day.weatherCode)}, '
                    'precipitation probability $precip, low ${format.temperature(day.lowC, withUnit: true)}, '
                    'high ${format.temperature(day.highC, withUnit: true)}, '
                    'precipitation amount ${format.precipitation(day.precipitationMm)}',
                excludeSemantics: true,
                child: Padding(
                  padding: const .symmetric(vertical: 6),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final textScale = MediaQuery.textScalerOf(context)
                          .scale(1);
                      final track = constraints.maxWidth / textScale >= 300;
                      final labelStyle = theme.textTheme.bodySmall;
                      return Row(
                        spacing: 6,
                        children: [
                          Expanded(flex: 2, child: Text(label)),
                          WeatherIcon(day.condition, size: 32),
                          Expanded(
                            child: Tooltip(
                              message: day.precipitationMm == null
                                  ? 'Precipitation amount not available'
                                  : 'Precipitation amount ${format.precipitation(day.precipitationMm)}',
                              child: Text(precip, style: labelStyle),
                            ),
                          ),
                          Expanded(child: Text(minTemp, textAlign: .end)),
                          if (track)
                            Expanded(
                              flex: 5,
                              child: _RangeTrack(
                                start: day.lowC == null || high == low
                                    ? null
                                    : (day.lowC! - low) / (high - low),
                                end: day.highC == null || high == low
                                    ? null
                                    : (day.highC! - low) / (high - low),
                                background: colors.surfaceContainerHigh,
                                foreground: colors.primary,
                              ),
                            ),
                          Expanded(child: Text(maxTemp, textAlign: .end)),
                        ],
                      );
                    },
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _RangeTrack extends StatelessWidget {
  const _RangeTrack({
    this.start,
    this.end,
    required this.background,
    required this.foreground,
  });
  final double? start;
  final double? end;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Container(
      height: 6,
      decoration: BoxDecoration(color: background, borderRadius: .circular(3)),
      child: Stack(
        children: [
          if (start case final left? when end != null && end! >= left)
            Positioned(
              top: 0,
              bottom: 0,
              left: constraints.maxWidth * left,
              right: constraints.maxWidth * (1 - end!),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: foreground,
                  borderRadius: .circular(3),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
