import 'dart:async';
import 'dart:math' as math;

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
    this.autofocus = true,
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
  final bool autofocus;

  @override
  State<CalendarGrid> createState() => _CalendarGridState();
}

class _CalendarGridState extends State<CalendarGrid> {
  final _focus = FocusNode(debugLabel: 'Calendar grid');
  Duration? _lastWheel;
  ({DateTime day, Offset position, PointerDeviceKind kind})? _lastClick;
  Timer? _doubleClickWindow;
  bool _showKeyboardFocus = false;

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
      if (!_showKeyboardFocus) setState(() => _showKeyboardFocus = true);
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

  void _click(DateTime day, TapUpDetails details) {
    final first = _lastClick;
    final doubleClick =
        first != null &&
        first.day == day &&
        first.kind == details.kind &&
        (first.position - details.globalPosition).distance <= kDoubleTapSlop;
    _doubleClickWindow?.cancel();
    if (_showKeyboardFocus) setState(() => _showKeyboardFocus = false);
    _focus.requestFocus();
    widget.onSelect(day);
    if (doubleClick) {
      _lastClick = null;
      widget.onOpenDay(day);
    } else {
      _lastClick = (
        day: day,
        position: details.globalPosition,
        kind: details.kind,
      );
      // Match completed taps without delaying single selection in the gesture arena.
      _doubleClickWindow = Timer(kDoubleTapTimeout, () => _lastClick = null);
    }
  }

  @override
  void dispose() {
    _doubleClickWindow?.cancel();
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
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
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
                height: math.max(
                  18.0,
                  MediaQuery.textScalerOf(context).scale(14),
                ),
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
                autofocus: widget.autofocus,
                onKeyEvent: _key,
                onFocusChange: (focused) => setState(() {
                  if (!focused) _showKeyboardFocus = true;
                }),
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
      focused: _showKeyboardFocus && _focus.hasFocus && day == widget.selected,
      onSelect: () {
        _focus.requestFocus();
        widget.onSelect(day);
      },
      onClick: (details) => _click(day, details),
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
    required this.onClick,
  });

  final DateTime day;
  final int count;
  final Iterable<Color> dots;
  final bool outside;
  final bool selected;
  final bool today;
  final bool focused;
  final VoidCallback onSelect;
  final GestureTapUpCallback onClick;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final date = MaterialLocalizations.of(context).formatFullDate(day);
    final shape = today
        ? MaterialShapeBorder(shape: MaterialShapes.cookie9Sided)
        : CircleBorder(
            side: selected
                ? BorderSide(color: colors.primary, width: 1.5)
                : .none,
          );
    final (color, weight) = switch ((today, selected, outside, day.weekday)) {
      (true, _, _, _) => (colors.onPrimary, FontWeight.w700),
      (_, true, _, _) => (colors.primary, FontWeight.w600),
      (_, _, true, _) => (
        colors.onSurface.withValues(alpha: .38),
        FontWeight.w400,
      ),
      (_, _, _, DateTime.saturday || DateTime.sunday) => (
        colors.onSurfaceVariant,
        FontWeight.w400,
      ),
      _ => (colors.onSurface, FontWeight.w400),
    };
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
        onTapUp: onClick,
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
                    shape: shape,
                  ),
                  child: CustomPaint(
                    foregroundPainter: focused
                        ? _DayFocus(colors.secondary, shape)
                        : null,
                    child: Center(
                      child: Text(
                        '${day.day}',
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          fontSize: 14,
                          height: 18 / 14,
                          letterSpacing: 0,
                          color: color,
                          fontWeight: weight,
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
  const _DayFocus(this.color, this.shape);
  final Color color;
  final ShapeBorder shape;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    shape.getOuterPath((Offset.zero & size).inflate(3)),
    Paint()
      ..color = color
      ..style = .stroke
      ..strokeWidth = 2,
  );

  @override
  bool shouldRepaint(_DayFocus oldDelegate) =>
      oldDelegate.color != color || oldDelegate.shape != shape;
}
