import 'package:material_ui/material_ui.dart';

import 'bar_clock.dart';
import 'calendar_dates.dart';

class CalendarClockHero extends StatefulWidget {
  const CalendarClockHero({
    super.key,
    required this.showSeconds,
    required this.onSettings,
  });

  final bool showSeconds;
  final VoidCallback? onSettings;

  @override
  State<CalendarClockHero> createState() => _CalendarClockHeroState();
}

class _CalendarClockHeroState extends State<CalendarClockHero> {
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(CalendarClockHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showSeconds != widget.showSeconds) _subscribe();
  }

  void _subscribe() =>
      _now = barClockSource.attach(_tick, seconds: widget.showSeconds);

  void _tick(DateTime now) => setState(() => _now = now);

  @override
  void dispose() {
    barClockSource.detach(_tick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final local = _now;
    final offset = local.timeZoneOffset;
    final dayOfYear =
        calendarDay(local).difference(DateTime.utc(local.year)).inDays + 1;
    final colors = Theme.of(context).colorScheme;
    final foreground = colors.onPrimaryContainer;
    final minutes = offset.inMinutes.abs();
    final zone =
        'UTC${offset.isNegative ? '-' : '+'}'
        '${_pad(minutes ~/ 60)}:${_pad(minutes % 60)}';
    final date = const DefaultMaterialLocalizations().formatFullDate(local);
    final separator = date.indexOf(', ');
    return Container(
      padding: const .symmetric(horizontal: 20, vertical: 16),
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
                    if (widget.showSeconds)
                      TextSpan(
                        text: ' :${_pad(local.second)}',
                        style: TextStyle(
                          color: foreground.withValues(alpha: .7),
                          fontSize: 20,
                          letterSpacing: 0,
                        ),
                      ),
                  ],
                ),
                style: _type(context, 56, foreground, .w500).copyWith(
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
                Tooltip(
                  message: '${_clock(local.toUtc())} UTC',
                  child: Material(
                    color: colors.primary,
                    shape: const StadiumBorder(),
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: widget.onSettings,
                      child: Padding(
                        padding: const .symmetric(horizontal: 10, vertical: 3),
                        child: Text(
                          zone,
                          semanticsLabel: widget.onSettings == null
                              ? zone
                              : '$zone, Date and time settings',
                          style: _type(context, 12, colors.onPrimary, .w500),
                        ),
                      ),
                    ),
                  ),
                ),
                Text(
                  date.substring(0, separator),
                  style: _type(context, 16, foreground, .w500),
                ),
                Tooltip(
                  message: 'Day $dayOfYear of the year',
                  child: Text(
                    date.substring(separator + 2),
                    textAlign: .end,
                    style: _type(context, 12, foreground),
                  ),
                ),
              ],
            ),
          ),
        ],
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
