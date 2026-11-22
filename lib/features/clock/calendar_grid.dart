import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'calendar_dates.dart';
import 'calendar_events.dart';

class CalendarGrid extends StatefulWidget {
  const CalendarGrid({
    super.key,
    required this.today,
    required this.selected,
    required this.firstWeekday,
    required this.cutoffWeekday,
    required this.week,
    required this.showWeekNumbers,
    required this.events,
    required this.onSelect,
    required this.onOpenDay,
    required this.onToggle,
    required this.onAgenda,
  });

  final DateTime today;
  final DateTime selected;
  final int firstWeekday;
  final int cutoffWeekday;
  final bool week;
  final bool showWeekNumbers;
  final List<CalendarEvent> events;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<DateTime> onOpenDay;
  final VoidCallback onToggle;
  final VoidCallback onAgenda;

  @override
  State<CalendarGrid> createState() => _CalendarGridState();
}

class _CalendarGridState extends State<CalendarGrid> {
  final _focus = FocusNode(debugLabel: 'Calendar grid');
  Duration? _lastWheel;

  DateTime _period(int step) => widget.week
      ? calendarDaysFrom(widget.selected, step * 7)
      : calendarMonthFrom(widget.selected, step);

  void _move(int step) => widget.onSelect(_period(step));

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return .ignored;
    }
    final day = widget.selected;
    final week = calendarWeekStart(day, widget.firstWeekday);
    final next = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => calendarDaysFrom(day, -1),
      LogicalKeyboardKey.arrowRight => calendarDaysFrom(day, 1),
      LogicalKeyboardKey.arrowUp => calendarDaysFrom(day, -7),
      LogicalKeyboardKey.arrowDown => calendarDaysFrom(day, 7),
      LogicalKeyboardKey.pageUp => _period(-1),
      LogicalKeyboardKey.pageDown => _period(1),
      LogicalKeyboardKey.home => week,
      LogicalKeyboardKey.end => calendarDaysFrom(week, 6),
      _ => null,
    };
    if (next != null) {
      widget.onSelect(next);
      return .handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      widget.onAgenda();
      return .handled;
    }
    return .ignored;
  }

  void _scroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    final previous = _lastWheel;
    _lastWheel = event.timeStamp;
    if (previous == null ||
        event.timeStamp - previous > const Duration(milliseconds: 120)) {
      _move(event.scrollDelta.dy.sign.toInt());
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final labels = MaterialLocalizations.of(context);
    final selected = widget.selected;
    final first = widget.firstWeekday;
    final month = DateTime.utc(selected.year, selected.month);
    final start = calendarWeekStart(widget.week ? selected : month, first);
    final currentWeek = calendarWeekStart(widget.today, first);
    final weekStyle = TextStyle(fontSize: 11, color: colors.onSurfaceVariant);
    final rows = widget.week ? 1 : 6;
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          GestureBinding.instance.pointerSignalResolver.register(
            event,
            _scroll,
          );
        }
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: .circular(24),
        ),
        child: Padding(
          padding: const .fromLTRB(8, 2, 10, 8),
          child: Column(
            children: [
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: .centerLeft,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: const .symmetric(horizontal: 10),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: .w500,
                            ),
                          ),
                          onPressed: widget.onToggle,
                          child: Row(
                            mainAxisSize: .min,
                            children: [
                              Flexible(
                                child: Text(
                                  labels.formatMonthYear(month),
                                  overflow: .ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                widget.week
                                    ? Icons.expand_more
                                    : Icons.expand_less,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (selected != widget.today)
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const .symmetric(horizontal: 8),
                          minimumSize: const Size(0, 32),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                        onPressed: () => widget.onSelect(widget.today),
                        child: const Text('Today'),
                      ),
                    for (final step in [-1, 1])
                      IconButton.filledTonal(
                        tooltip: widget.week
                            ? (step == -1 ? 'Previous week' : 'Next week')
                            : (step == -1
                                  ? labels.previousMonthTooltip
                                  : labels.nextMonthTooltip),
                        style: IconButton.styleFrom(
                          fixedSize: const Size.square(32),
                          minimumSize: const Size.square(32),
                        ),
                        iconSize: 18,
                        onPressed: () => _move(step),
                        icon: Icon(
                          step == -1 ? Icons.chevron_left : Icons.chevron_right,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: 18,
                child: Row(
                  children: [
                    if (widget.showWeekNumbers)
                      SizedBox(
                        width: 24,
                        child: Center(child: Text('W', style: weekStyle)),
                      ),
                    for (var column = 0; column < 7; column++)
                      Expanded(
                        child: Center(
                          child: Text(
                            calendarWeekdays[(first - 1 + column) % 7],
                            style: weekStyle.copyWith(fontSize: 12),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Focus(
                focusNode: _focus,
                autofocus: true,
                onKeyEvent: _key,
                onFocusChange: (_) => setState(() {}),
                child: Column(
                  children: [
                    for (var row = 0; row < rows; row++)
                      _row(
                        context,
                        calendarDaysFrom(start, row * 7),
                        currentWeek,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, DateTime start, DateTime currentWeek) {
    final colors = Theme.of(context).colorScheme;
    final current = start == currentWeek;
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          if (widget.showWeekNumbers)
            SizedBox(
              width: 24,
              child: Center(
                child: Text(
                  '${calendarWeekNumber(start, widget.cutoffWeekday)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: current ? .w600 : .w500,
                    color: current
                        ? colors.primary
                        : colors.onSurface.withValues(alpha: .6),
                  ),
                ),
              ),
            ),
          for (var column = 0; column < 7; column++)
            Expanded(child: _cell(calendarDaysFrom(start, column))),
        ],
      ),
    );
  }

  Widget _cell(DateTime day) {
    final events = widget.events.where((event) => event.occursOn(day)).toList();
    final dots = <String, Color>{};
    for (final event in events) {
      dots.putIfAbsent(event.calendarId, () => event.rawColor);
      if (dots.length == 3) break;
    }
    return _DayCell(
      day: day,
      count: events.length,
      dots: dots.values,
      outside: !widget.week && day.month != widget.selected.month,
      selected: day == widget.selected,
      today: day == widget.today,
      focused:
          _focus.hasFocus &&
          day == widget.selected &&
          FocusManager.instance.highlightMode == FocusHighlightMode.traditional,
      onSelect: () {
        _focus.requestFocus();
        widget.onSelect(day);
      },
      onOpen: () {
        _focus.requestFocus();
        widget.onSelect(day);
        widget.onOpenDay(day);
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.count,
    required this.dots,
    required this.outside,
    required this.selected,
    required this.today,
    required this.focused,
    required this.onSelect,
    required this.onOpen,
  });

  final DateTime day;
  final int count;
  final Iterable<Color> dots;
  final bool outside;
  final bool selected;
  final bool today;
  final bool focused;
  final VoidCallback onSelect;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final date = MaterialLocalizations.of(context).formatFullDate(day);
    return Semantics(
      label:
          '$date, $count ${count == 1 ? 'event' : 'events'}'
          '${selected ? ', selected' : ''}',
      selected: selected,
      button: true,
      onTap: onSelect,
      child: InkWell(
        excludeFromSemantics: true,
        canRequestFocus: false,
        borderRadius: .circular(18),
        onTap: onSelect,
        onDoubleTap: onOpen,
        child: ExcludeSemantics(
          child: Column(
            mainAxisAlignment: .center,
            spacing: 1,
            children: [
              SizedBox.square(
                dimension: 30,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: today
                        ? colors.primary
                        : selected
                        ? colors.primary.withValues(alpha: .12)
                        : null,
                    shape: today
                        ? MaterialShapeBorder(
                            shape: MaterialShapes.cookie9Sided,
                          )
                        : CircleBorder(
                            side: selected
                                ? BorderSide(color: colors.primary, width: 1.5)
                                : .none,
                          ),
                  ),
                  child: CustomPaint(
                    foregroundPainter: focused
                        ? _DayFocus(colors.secondary)
                        : null,
                    child: Center(
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 14,
                          color: today
                              ? colors.onPrimary
                              : outside
                              ? colors.onSurface.withValues(alpha: .38)
                              : colors.onSurface,
                          fontWeight: today ? .w700 : .w400,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 4,
                child: Row(
                  mainAxisSize: .min,
                  spacing: 3,
                  children: [
                    for (final color in dots)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          shape: .circle,
                          color: outside ? color.withValues(alpha: .38) : color,
                        ),
                        child: const SizedBox.square(dimension: 4),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayFocus extends CustomPainter {
  const _DayFocus(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawCircle(
    size.center(.zero),
    size.shortestSide / 2 + 1,
    Paint()
      ..color = color
      ..style = .stroke
      ..strokeWidth = 2,
  );

  @override
  bool shouldRepaint(_DayFocus oldDelegate) => oldDelegate.color != color;
}
