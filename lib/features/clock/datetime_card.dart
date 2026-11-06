import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

class DatetimeCard extends StatelessWidget {
  const DatetimeCard({super.key, required this.data, required this.onSettings});

  final Map<String, Object?> data;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final millis = data['unixMillis'];
    final offset = data['utcOffsetSeconds'];
    final valid =
        millis is int &&
        millis.abs() < 8640000000000000 - Duration.millisecondsPerDay &&
        offset is int &&
        offset.abs() < Duration.secondsPerDay;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 16,
      children: [
        Row(
          mainAxisAlignment: .spaceBetween,
          children: [
            Text(
              'Datetime',
              style: _type(context, 24, colors.primaryFixed, .w700),
            ),
            IconButton.filledTonal(
              tooltip: 'Date and time settings',
              onPressed: onSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        if (valid)
          _CurrentDateTime(
            utc: DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
            offset: Duration(seconds: offset),
          )
        else
          const Text('Date and time unavailable'),
      ],
    );
  }
}

class _CurrentDateTime extends StatelessWidget {
  const _CurrentDateTime({required this.utc, required this.offset});

  final DateTime utc;
  final Duration offset;

  @override
  Widget build(BuildContext context) {
    // Use UTC arithmetic for the snapshot's civil fields across DST changes.
    final local = utc.add(offset);
    final today = DateTime.utc(local.year, local.month, local.day);
    final thursday = today.add(
      Duration(days: DateTime.thursday - today.weekday),
    );
    final week =
        thursday.difference(DateTime.utc(thursday.year)).inDays ~/ 7 + 1;
    final dayOfYear = today.difference(DateTime.utc(today.year)).inDays + 1;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 16,
      children: [
        _ClockHero(local: local, offset: offset),
        Row(
          crossAxisAlignment: .start,
          spacing: 8,
          children: [
            Expanded(child: _Stat('Week', '$week')),
            Expanded(child: _Stat('Day of year', '$dayOfYear')),
            Expanded(child: _Stat('UTC', _clock(utc))),
          ],
        ),
        _Calendar(today: today),
      ],
    );
  }
}

class _ClockHero extends StatelessWidget {
  const _ClockHero({required this.local, required this.offset});

  final DateTime local;
  final Duration offset;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = colors.onPrimaryContainer;
    final minutes = offset.inMinutes.abs();
    final zone =
        'UTC${offset.isNegative ? '-' : '+'}'
        '${_pad(minutes ~/ 60)}:${_pad(minutes % 60)}';
    final date = const DefaultMaterialLocalizations().formatFullDate(local);
    final separator = date.indexOf(', ');
    return Container(
      padding: const .all(20),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: .circular(28),
      ),
      child: Row(
        mainAxisAlignment: .spaceBetween,
        spacing: 8,
        children: [
          Flexible(
            flex: 13,
            child: FittedBox(
              fit: .scaleDown,
              alignment: .centerLeft,
              child: Text.rich(
                TextSpan(
                  text: _clock(local),
                  children: [
                    TextSpan(
                      text: ' :${_pad(local.second)}',
                      style: TextStyle(
                        color: foreground.withValues(alpha: .7),
                        fontSize: 24,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
                style: _type(context, 64, foreground, .w500).copyWith(
                  letterSpacing: -1.92,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          Flexible(
            flex: 7,
            child: Column(
              crossAxisAlignment: .end,
              spacing: 6,
              children: [
                Container(
                  padding: const .symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: .circular(999),
                  ),
                  child: Text(
                    zone,
                    style: _type(context, 12, colors.onPrimary, .w500),
                  ),
                ),
                Text(
                  date.substring(0, separator),
                  style: _type(context, 16, foreground, .w500),
                ),
                Text(
                  date.substring(separator + 2),
                  textAlign: .end,
                  style: _type(context, 12, foreground),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const .symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: .circular(20),
      ),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 2,
        children: [
          Text(label, style: _type(context, 12, colors.onSurfaceVariant)),
          Text(value, style: _type(context, 20, colors.primaryFixed, .w500)),
        ],
      ),
    );
  }
}

class _Calendar extends StatefulWidget {
  const _Calendar({required this.today});

  final DateTime today;

  @override
  State<_Calendar> createState() => _CalendarState();
}

class _CalendarState extends State<_Calendar> {
  DateTime? _browsedMonth;
  DateTime? _selectedDay;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final labels = MaterialLocalizations.of(context);
    final today = widget.today;
    final month = _browsedMonth ?? DateTime.utc(today.year, today.month);
    final leading = month.weekday - DateTime.monday;
    final days = DateTime.utc(month.year, month.month + 1, 0).day;
    final rows = (leading + days + 6) ~/ 7;
    return Container(
      padding: const .fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: .circular(24),
      ),
      child: Column(
        spacing: 4,
        children: [
          Padding(
            padding: const .only(left: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    labels.formatMonthYear(month),
                    style: _type(context, 16, colors.primaryFixed, .w500),
                  ),
                ),
                for (final delta in [-1, 1])
                  IconButton.filledTonal(
                    tooltip: delta < 0
                        ? labels.previousMonthTooltip
                        : labels.nextMonthTooltip,
                    onPressed: () => setState(() {
                      _browsedMonth = DateTime.utc(
                        month.year,
                        month.month + delta,
                      );
                    }),
                    icon: Icon(
                      delta < 0 ? Icons.chevron_left : Icons.chevron_right,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const .only(bottom: 4),
            child: Row(
              children: [
                for (var weekday = 1; weekday <= 7; weekday++)
                  Expanded(
                    child: Text(
                      labels.narrowWeekdays[weekday % 7],
                      textAlign: .center,
                      style: _type(context, 12, colors.onSurfaceVariant, .w500),
                    ),
                  ),
              ],
            ),
          ),
          Column(
            children: [
              for (var row = 0; row < rows; row++)
                Row(
                  children: [
                    for (var column = 0; column < 7; column++)
                      _buildDay(
                        DateTime.utc(
                          month.year,
                          month.month,
                          1 - leading + row * 7 + column,
                        ),
                        month,
                      ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDay(DateTime date, DateTime month) {
    final inMonth = date.month == month.month;
    return Expanded(
      child: _CalendarDay(
        date: date,
        outside: !inMonth,
        today: date == widget.today,
        selected: date == _selectedDay,
        marked: false,
        onTap: inMonth ? () => setState(() => _selectedDay = date) : null,
      ),
    );
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.date,
    required this.outside,
    required this.today,
    required this.selected,
    required this.onTap,
    required this.marked,
  });

  final DateTime date;
  final bool outside;
  final bool today;
  final bool selected;
  final VoidCallback? onTap;
  final bool marked;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final weekend = date.weekday >= DateTime.saturday;
    final color = switch ((today, outside, weekend)) {
      (true, _, _) => colors.onPrimary,
      (_, true, _) => colors.onSurfaceVariant.withValues(alpha: .38),
      (_, _, true) => colors.onSurfaceVariant,
      _ => colors.onSurface,
    };
    final shape = today
        ? MaterialShapeBorder(shape: MaterialShapes.cookie9Sided)
        : CircleBorder(
            side: selected ? BorderSide(color: colors.primary) : .none,
          );
    final label = MaterialLocalizations.of(context).formatFullDate(date);
    return Semantics(
      label: label,
      selected: selected || today,
      child: SizedBox(
        height: 42,
        child: InkWell(
          onTap: onTap,
          borderRadius: .circular(20),
          child: Column(
            spacing: 1,
            children: [
              SizedBox.square(
                dimension: 34,
                child: Center(
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: today ? colors.primary : null,
                      shape: shape,
                    ),
                    child: SizedBox.square(
                      dimension: 30,
                      child: Center(
                        child: ExcludeSemantics(
                          child: Text(
                            '${date.day}',
                            style: _type(
                              context,
                              14,
                              color,
                              today ? .w700 : .w400,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (marked)
                SvgPicture.asset(
                  today
                      ? 'assets/icons/datetime/today-dot.svg'
                      : 'assets/icons/datetime/event-dot.svg',
                  colorFilter: ColorFilter.mode(
                    today ? colors.primary : colors.tertiary,
                    .srcIn,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

TextStyle _type(
  BuildContext context,
  double size,
  Color color, [
  FontWeight weight = .w400,
]) => Theme.of(context).textTheme.bodyMedium!.copyWith(
  fontSize: size,
  color: color,
  fontWeight: weight,
  height: 1.2,
  letterSpacing: 0,
);

String _pad(int value) => value.toString().padLeft(2, '0');

String _clock(DateTime time) => '${_pad(time.hour)}:${_pad(time.minute)}';
