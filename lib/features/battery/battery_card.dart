import 'package:material_ui/material_ui.dart';

import '../settings/remya_settings_installed.dart';

import '../../widgets/percent_text.dart';
import '../../widgets/wave_progress.dart';

class BatteryCard extends StatelessWidget {
  const BatteryCard({super.key, required this.data, required this.onAction});

  final Map<String, Object?> data;
  final ValueChanged<Map<String, Object?>> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final power = data['power'] is Map ? data['power'] as Map : const {};
    final watts = _number(data['powerWatts']);
    final health = _number(data['healthPercent']);
    final cycles = data['cycleCount'];
    final present = data['present'];
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 16,
      children: [
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: Text(
                'Battery',
                style: theme.textTheme.headlineSmall?.copyWith(
                  height: 1.25,
                  fontWeight: .bold,
                  color: _emphasis(theme),
                ),
              ),
            ),
            if (remyaSettingsInstalled())
              IconButton.filledTonal(
                tooltip: 'Power settings',
                onPressed: data['pending'] == true
                    ? null
                    : () => onAction(const {'action': 'battery.settings'}),
                icon: const Icon(Icons.settings_outlined),
              ),
          ],
        ),
        if (data['error'] case final String error)
          Text(
            error,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        if (present == true) ...[
          _BatteryHero(data: data, onBattery: power['onBattery']),
          Row(
            crossAxisAlignment: .start,
            spacing: 8,
            children: [
              Expanded(
                child: _Stat(
                  data['status'] == 'Charging' ? 'Charge rate' : 'Draw',
                  watts == null ? '—' : '${watts.toStringAsFixed(1)} W',
                ),
              ),
              Expanded(
                child: _Stat(
                  'Health',
                  health == null ? '—' : '${health.round()}%',
                  percent: health?.round(),
                ),
              ),
              Expanded(
                child: _Stat(
                  'Cycles',
                  cycles is int && cycles >= 0 ? '$cycles' : '—',
                ),
              ),
            ],
          ),
        ] else
          Text(
            present == false
                ? 'No battery detected'
                : 'Battery data unavailable',
          ),
        _PowerControls(
          power: power,
          pending: data['pending'] == true,
          onAction: onAction,
        ),
      ],
    );
  }
}

class _BatteryHero extends StatelessWidget {
  const _BatteryHero({required this.data, required this.onBattery});

  final Map<String, Object?> data;
  final Object? onBattery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final rawPercent = _number(data['percent']);
    final percent = rawPercent != null && rawPercent <= 100 ? rawPercent : null;
    final status = data['status'];
    final charging = status == 'Charging';
    final label = switch (status) {
      'Charging' => 'Charging',
      'Discharging' => 'On battery',
      'Full' => 'Fully charged',
      _ when onBattery == false => 'Plugged in',
      _ when onBattery == true => 'On battery',
      'Not charging' => 'Not charging',
      _ => 'Status unavailable',
    };
    final seconds = _number(data['secondsRemaining']);
    final estimate =
        seconds != null &&
            seconds >= 1 &&
            seconds <= 365 * Duration.secondsPerDay &&
            (charging || status == 'Discharging')
        ? Duration(seconds: seconds.round())
        : null;
    final finish = estimate == null
        ? null
        : MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(DateTime.now().add(estimate)),
            alwaysUse24HourFormat: true,
          );
    final big = theme.textTheme.displayLarge?.copyWith(
      color: colors.onPrimaryContainer,
      fontSize: 64,
      height: 68 / 64,
      letterSpacing: -1.28,
      fontWeight: .w500,
    );
    final charge = percent == null
        ? Text('—', style: big)
        : PercentText('${percent.round()}', style: big);
    final details = Column(
      crossAxisAlignment: .end,
      spacing: 8,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: .circular(999),
          ),
          child: Padding(
            padding: const .fromLTRB(8, 4, 12, 4),
            child: Row(
              mainAxisSize: .min,
              spacing: 4,
              children: [
                Image.asset(
                  'assets/icons/battery-card-status.png',
                  width: 16,
                  height: 16,
                  color: colors.onPrimary,
                ),
                Flexible(
                  child: Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 12,
                      height: 1.25,
                      color: colors.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (estimate != null) ...[
          Text(
            '${_durationLabel(estimate)} ${charging ? 'to full' : 'left'}',
            textAlign: .end,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colors.onPrimaryContainer,
              fontWeight: .w500,
              height: 1.25,
            ),
          ),
          Text(
            'Until about $finish',
            textAlign: .end,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onPrimaryContainer.withValues(alpha: .8),
              fontSize: 12,
              height: 1.25,
            ),
          ),
        ],
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: .circular(28),
      ),
      child: Padding(
        padding: const .all(20),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 16,
          children: [
            LayoutBuilder(
              builder: (context, constraints) =>
                  constraints.maxWidth /
                          MediaQuery.textScalerOf(context).scale(1) <
                      230
                  ? Column(
                      crossAxisAlignment: .start,
                      spacing: 8,
                      children: [charge, details],
                    )
                  : Row(
                      mainAxisAlignment: .spaceBetween,
                      spacing: 12,
                      children: [
                        charge,
                        Flexible(child: details),
                      ],
                    ),
            ),
            if (percent != null)
              SizedBox(
                height: 14,
                child: CustomPaint(
                  painter: WaveProgressPainter(
                    fraction: percent / 100,
                    active: colors.primary,
                    track: colors.surfaceContainerHighest,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.percent});

  final String label;
  final String value;
  final int? percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle = theme.textTheme.titleLarge?.copyWith(
      fontSize: 20,
      height: 1.25,
      fontWeight: .w500,
      color: _emphasis(theme),
    );
    return _BatteryTile(
      padding: const .symmetric(horizontal: 16, vertical: 12),
      child: _BatteryLabel(
        label: label,
        value: value,
        valueWidget: percent == null
            ? null
            : PercentText('$percent', style: valueStyle),
        valueStyle: valueStyle,
      ),
    );
  }
}

class _PowerControls extends StatelessWidget {
  const _PowerControls({
    required this.power,
    required this.pending,
    required this.onAction,
  });

  final Map power;
  final bool pending;
  final ValueChanged<Map<String, Object?>> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final threshold = power['threshold'];
    final available = power['available'] == true;
    final conflict = power['conflict'] == true;
    final editable = available && !conflict && !pending;
    final profiles = power['profiles'];
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 16,
      children: [
        Column(
          crossAxisAlignment: .stretch,
          children: [
            Text(
              'Power mode',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 14,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 4),
            _PowerModes(
              selected: power['profile'],
              available: editable && profiles is List
                  ? profiles.whereType<String>().toSet()
                  : const {},
              onAction: onAction,
            ),
            if (conflict || !available)
              Text(
                conflict
                    ? 'Review the power configuration in Settings.'
                    : 'Power controls unavailable',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
        _BatteryTile(
          padding: const .fromLTRB(16, 6, 12, 6),
          child: Row(
            spacing: 12,
            children: [
              Expanded(
                child: Padding(
                  padding: const .symmetric(vertical: 6),
                  child: _BatteryLabel(
                    label: switch (threshold) {
                      0 => 'Off',
                      100 => 'Always on',
                      final int value when value > 0 => 'Turns on at $value%',
                      _ => 'Unavailable',
                    },
                    labelPercent:
                        threshold is int && threshold > 0 && threshold < 100
                        ? threshold
                        : null,
                    value: 'Auto battery saver',
                    valueStyle: theme.textTheme.titleMedium?.copyWith(
                      color: _emphasis(theme),
                      fontSize: 16,
                      height: 1.25,
                    ),
                    valueFirst: true,
                  ),
                ),
              ),
              Semantics(
                label: 'Auto battery saver',
                child: Switch(
                  value: threshold is int && threshold > 0,
                  thumbIcon: .resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? const Icon(Icons.check, size: 16)
                        : null,
                  ),
                  onChanged: editable && threshold is int
                      ? (value) => onAction({
                          'action': 'battery.autoSaver',
                          'value': value,
                        })
                      : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PowerModes extends StatelessWidget {
  const _PowerModes({
    required this.selected,
    required this.available,
    required this.onAction,
  });

  static const modes = {
    'power-saver': 'Saver',
    'balanced': 'Balanced',
    'performance': 'Performance',
  };

  final Object? selected;
  final Set<String> available;
  final ValueChanged<Map<String, Object?>> onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
            330;
        final buttons = [
          for (final mode in modes.entries)
            Semantics(
              selected: selected == mode.key,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: selected == mode.key
                      ? colors.secondary
                      : colors.secondaryContainer,
                  foregroundColor: selected == mode.key
                      ? colors.onSecondary
                      : colors.onSecondaryContainer,
                  disabledBackgroundColor: selected == mode.key
                      ? colors.onSurface.withValues(alpha: .20)
                      : null,
                  minimumSize: const Size(0, 40),
                  visualDensity: .standard,
                  textStyle: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(fontSize: 14, height: 1.25),
                  padding: const .symmetric(horizontal: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: selected == mode.key || stacked
                        ? .circular(20)
                        : .horizontal(
                            left: const Radius.circular(8),
                            right: Radius.circular(
                              mode.key == 'performance' ? 20 : 8,
                            ),
                          ),
                  ),
                ),
                onPressed: !available.contains(mode.key)
                    ? null
                    : () {
                        if (selected != mode.key) {
                          onAction({
                            'action': 'battery.profile',
                            'value': mode.key,
                          });
                        }
                      },
                child: Text(mode.value, textAlign: .center),
              ),
            ),
        ];
        return stacked
            ? Column(crossAxisAlignment: .stretch, children: buttons)
            : Row(
                spacing: 2,
                children: [
                  for (final button in buttons) Expanded(child: button),
                ],
              );
      },
    );
  }
}

class _BatteryTile extends StatelessWidget {
  const _BatteryTile({required this.padding, required this.child});

  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: .circular(20),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
    ),
    child: Padding(padding: padding, child: child),
  );
}

class _BatteryLabel extends StatelessWidget {
  const _BatteryLabel({
    required this.label,
    required this.value,
    required this.valueStyle,
    this.valueFirst = false,
    this.valueWidget,
    this.labelPercent,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;
  final bool valueFirst;
  final Widget? valueWidget;
  final int? labelPercent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontSize: 12,
      height: 1.25,
    );
    final caption = labelPercent == null
        ? Text(label, style: labelStyle)
        : PercentText(
            '$labelPercent',
            prefix: 'Turns on at ',
            style: labelStyle,
          );
    final reading = valueWidget ?? Text(value, style: valueStyle);
    return Column(
      crossAxisAlignment: .start,
      spacing: 2,
      children: valueFirst ? [reading, caption] : [caption, reading],
    );
  }
}

Color _emphasis(ThemeData theme) => theme.brightness == .dark
    ? theme.colorScheme.primaryFixed
    : theme.colorScheme.onSurface;

double? _number(Object? value) =>
    value is num && value.isFinite && value >= 0 ? value.toDouble() : null;

String _durationLabel(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}m';
  return minutes > 0 ? '${minutes}m' : '<1m';
}
