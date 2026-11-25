import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import 'calendar_events.dart';
import 'clock_card_controls.dart';

part 'calendar_event_tile.dart';

class CalendarAgenda extends StatefulWidget {
  const CalendarAgenda({
    super.key,
    required this.selectedDay,
    required this.now,
    required this.events,
    required this.rangeDays,
    required this.foldFinished,
    required this.showDeclined,
    required this.onOpen,
    required this.onJoin,
    this.leading,
    this.placeholder,
    this.onKeyEvent,
  });

  final DateTime selectedDay;
  final DateTime now;
  final List<CalendarEvent> events;
  final int rangeDays;
  final bool foldFinished;
  final bool showDeclined;
  final ValueChanged<CalendarEvent> onOpen;
  final ValueChanged<CalendarEvent> onJoin;
  final Widget? leading;
  final Widget? placeholder;
  final FocusOnKeyEventCallback? onKeyEvent;

  @override
  State<CalendarAgenda> createState() => CalendarAgendaState();
}

class CalendarAgendaState extends State<CalendarAgenda> {
  final _scroll = ScrollController(keepScrollOffset: false);
  final _focus = FocusScopeNode(traversalEdgeBehavior: .parentScope);
  final _firstItem = FocusNode(debugLabel: 'First event on selected day');
  bool _expanded = false;
  bool _startFade = false;
  bool _endFade = false;
  late int _days = widget.rangeDays;

  void focusFirstEvent() {
    final context = _firstItem.context;
    if (context == null) return;
    _firstItem.requestFocus();
    Scrollable.ensureVisible(
      context,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 250),
      curve: Easing.emphasizedDecelerate,
    );
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_scrolled);
  }

  @override
  void didUpdateWidget(CalendarAgenda oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rangeDays != widget.rangeDays ||
        oldWidget.selectedDay != widget.selectedDay) {
      _days = widget.rangeDays;
      _startFade = false;
      _endFade = false;
    }
  }

  void _scrolled() {
    _updateFade(_scroll.position);
    if (_scroll.position.userScrollDirection == .reverse) _extendIfNeeded();
  }

  void _updateFade(ScrollMetrics metrics) {
    final start = metrics.extentBefore > 0;
    final end = metrics.extentAfter > 0;
    if (_startFade == start && _endFade == end) return;
    setState(() {
      _startFade = start;
      _endFade = end;
    });
  }

  void _extendIfNeeded() {
    if (widget.placeholder != null ||
        _days >= 60 ||
        !_scroll.hasClients ||
        _scroll.position.extentAfter > 56) {
      return;
    }
    setState(() => _days = math.min(60, _days + 14));
  }

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    _firstItem.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = _civilDate(widget.now);
    final order = {
      for (final (index, event) in widget.events.indexed) event: index,
    };
    final sorted =
        [
          for (final event in widget.events)
            if (widget.showDeclined || !event.declined) event,
        ]..sort((a, b) {
          if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
          if (a.allDay) {
            final span = b.duration.compareTo(a.duration);
            if (span != 0) return span;
          }
          final starts = a.start.compareTo(b.start);
          if (starts != 0) return starts;
          final duration = b.duration.compareTo(a.duration);
          return duration == 0 ? order[a]!.compareTo(order[b]!) : duration;
        });
    final groups = <DateTime, List<CalendarEvent>>{};
    for (var offset = 0; offset < _days; offset++) {
      final day = widget.selectedDay.add(Duration(days: offset));
      final items = [
        for (final event in sorted)
          if (event.occursOn(day)) event,
      ];
      if (offset == 0 || items.isNotEmpty) groups[day] = items;
    }
    final days = FocusScope(
      node: _focus,
      includeSemantics: false,
      onKeyEvent: widget.onKeyEvent,
      child: SliverMainAxisGroup(
        slivers: [
          if (widget.placeholder case final placeholder?)
            SliverToBoxAdapter(child: placeholder)
          else
            for (final MapEntry(:key, :value) in groups.entries)
              SliverLayoutBuilder(
                key: ValueKey(key),
                builder: (context, constraints) => SliverToBoxAdapter(
                  child: _AgendaDay(
                    day: key,
                    today: today,
                    now: widget.now,
                    selected: key == widget.selectedDay,
                    pinnedOffset: constraints.scrollOffset,
                    items: value,
                    firstItem: key == widget.selectedDay ? _firstItem : null,
                    emptyRange: groups.length == 1 && value.isEmpty
                        ? _days
                        : null,
                    foldFinished: widget.foldFinished && !_expanded,
                    onToggleFinished: () =>
                        setState(() => _expanded = !_expanded),
                    canCollapseFinished: widget.foldFinished,
                    onOpen: widget.onOpen,
                    onJoin: widget.onJoin,
                  ),
                ),
              ),
        ],
      ),
    );
    final scroll = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          _updateFade(notification.metrics);
          return false;
        },
        child: CustomScrollView(
          // A standalone agenda resets to the selected day without moving its grid.
          key: widget.leading == null
              ? ValueKey((widget.selectedDay, widget.rangeDays))
              : const ValueKey('shared-calendar-scroll'),
          controller: _scroll,
          slivers: [
            if (widget.leading case final leading?)
              SliverToBoxAdapter(child: leading),
            days,
          ],
        ),
      ),
    );
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent &&
            event.scrollDelta.dy > 0 &&
            _scroll.hasClients &&
            _scroll.position.extentAfter == 0) {
          _extendIfNeeded();
        }
      },
      child: ClockCardScrollFade(
        top: _startFade,
        bottom: _endFade,
        child: scroll,
      ),
    );
  }
}

class _AgendaDay extends StatelessWidget {
  const _AgendaDay({
    required this.day,
    required this.today,
    required this.now,
    required this.selected,
    required this.pinnedOffset,
    required this.items,
    required this.firstItem,
    required this.emptyRange,
    required this.foldFinished,
    required this.onToggleFinished,
    required this.canCollapseFinished,
    required this.onOpen,
    required this.onJoin,
  });

  final DateTime day;
  final DateTime today;
  final DateTime now;
  final bool selected;
  final double pinnedOffset;
  final List<CalendarEvent> items;
  final FocusNode? firstItem;
  final int? emptyRange;
  final bool foldFinished;
  final bool canCollapseFinished;
  final VoidCallback onToggleFinished;
  final ValueChanged<CalendarEvent> onOpen;
  final ValueChanged<CalendarEvent> onJoin;

  bool _running(CalendarEvent event) =>
      !event.allDay &&
      !event.declined &&
      !now.isBefore(event.start) &&
      now.isBefore(event.end);

  @override
  Widget build(BuildContext context) {
    final isToday = day == today;
    final timed = items.where((event) => !event.allDay);
    final earlier = isToday
        ? timed.where((event) => !event.end.isAfter(now)).toList()
        : const <CalendarEvent>[];
    final running = isToday && timed.any(_running);
    final next = isToday
        ? timed
              .where((event) => !event.declined && event.start.isAfter(now))
              .firstOrNull
        : null;
    final upcoming = next == null
        ? const Duration(hours: 2)
        : next.start.difference(now);
    final showEarlier = canCollapseFinished && earlier.length >= 2;
    final Widget? nowLine = isToday && !running && timed.isNotEmpty
        ? _NowLine(now)
        : null;
    final firstPending = nowLine == null
        ? null
        : timed.where((event) => !earlier.contains(event)).firstOrNull;
    final rows = <Object>[
      ...items.where((event) => event.allDay),
      for (final event in timed) ...[
        if (showEarlier && identical(event, earlier.first))
          _EarlierEvents(
            items: earlier,
            expanded: !foldFinished,
            onPressed: onToggleFinished,
            focusNode: foldFinished && earlier.length == items.length
                ? firstItem
                : null,
          ),
        if (identical(event, firstPending)) nowLine!,
        if (!showEarlier || !foldFinished || !earlier.contains(event)) event,
      ],
      if (firstPending == null) ?nowLine,
    ];
    final first = rows.whereType<CalendarEvent>().firstOrNull;
    return Padding(
      padding: const .only(bottom: 12),
      child: Stack(
        children: [
          Padding(
            padding: const .only(left: 56),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Column(
                crossAxisAlignment: .stretch,
                spacing: 2,
                children: [
                  if (items.isEmpty) _EmptyAgenda(days: emptyRange),
                  for (final (index, row) in rows.indexed)
                    if (row is CalendarEvent)
                      _EventTile(
                        key: ValueKey((row.calendarId, row.id)),
                        event: row,
                        day: day,
                        now: now,
                        focusNode: identical(row, first) ? firstItem : null,
                        past:
                            day.isBefore(today) ||
                            !row.allDay && !row.end.isAfter(now),
                        live: isToday && _running(row),
                        soon:
                            identical(row, next) && upcoming.inSeconds <= 3600,
                        radius: connectedClockRowRadius(
                          first:
                              index == 0 || rows[index - 1] is! CalendarEvent,
                          last:
                              index + 1 == rows.length ||
                              rows[index + 1] is! CalendarEvent,
                        ),
                        onOpen: row.htmlLink == null ? null : () => onOpen(row),
                        onJoin: row.meetingLink == null
                            ? null
                            : () => onJoin(row),
                      )
                    else
                      row as Widget,
                ],
              ),
            ),
          ),
          Positioned.fill(
            right: null,
            child: SizedBox(
              width: 44,
              child: LayoutBuilder(
                builder: (context, constraints) => Align(
                  alignment: .topLeft,
                  child: Transform.translate(
                    offset: Offset(
                      0,
                      pinnedOffset.clamp(0.0, constraints.maxHeight - 56),
                    ),
                    child: _DateBadge(day, today: isToday, selected: selected),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateBadge extends StatelessWidget {
  const _DateBadge(this.day, {required this.today, required this.selected});

  final DateTime day;
  final bool today;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final colors = Theme.of(context).colorScheme;
    final foreground = today ? colors.onPrimary : colors.onSurface;
    return Semantics(
      header: true,
      label: MaterialLocalizations.of(context).formatFullDate(day),
      excludeSemantics: true,
      child: Container(
        width: 44,
        height: 56,
        padding: const .all(4),
        decoration: BoxDecoration(
          color: today ? colors.primary : null,
          border: selected && !today
              ? Border.all(color: colors.primary, width: 1.5)
              : null,
          borderRadius: .circular(28),
        ),
        child: FittedBox(
          fit: .scaleDown,
          child: Column(
            mainAxisSize: .min,
            children: [
              Text(
                weekdays[day.weekday - 1],
                style: _agendaType(context, 12, 16, foreground),
              ),
              Text(
                '${day.day}',
                style: _agendaType(context, 20, 24, foreground, .w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EarlierEvents extends StatelessWidget {
  const _EarlierEvents({
    required this.items,
    required this.expanded,
    required this.onPressed,
    required this.focusNode,
  });

  final List<CalendarEvent> items;
  final bool expanded;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dots = {for (final item in items) item.calendarId: item.rawColor};
    return Material(
      color: colors.surfaceContainerHigh,
      borderRadius: .circular(12),
      child: InkWell(
        onTap: onPressed,
        focusNode: focusNode,
        borderRadius: .circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Padding(
            padding: const .symmetric(horizontal: 12, vertical: 4),
            child: Row(
              spacing: 4,
              children: [
                for (final color in dots.values.take(3))
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: color, shape: .circle),
                  ),
                Expanded(
                  child: Text(
                    '${items.length} earlier events',
                    style: _agendaType(context, 12, 16, colors.onSurface),
                  ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NowLine extends StatelessWidget {
  const _NowLine(this.now);

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final time = _time(MaterialLocalizations.of(context), now);
    return Semantics(
      label: 'Now, $time',
      excludeSemantics: true,
      child: Row(
        spacing: 4,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: .circle),
          ),
          Expanded(child: Divider(height: 12, color: color, thickness: 1)),
          Text(time, style: _agendaType(context, 11, 14, color)),
        ],
      ),
    );
  }
}

class _EmptyAgenda extends StatelessWidget {
  const _EmptyAgenda({required this.days});

  final int? days;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: .start,
      spacing: 12,
      children: [
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 56),
          padding: const .symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: .circular(16),
          ),
          child: Column(
            mainAxisAlignment: .center,
            crossAxisAlignment: .start,
            children: [
              Text(
                'No events',
                style: _agendaType(context, 14, 20, colors.onSurface, .w500),
              ),
              if (days case final range?)
                Text(
                  'The next $range days are free.',
                  style: _agendaType(context, 12, 16, colors.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class CalendarAgendaLoading extends StatefulWidget {
  const CalendarAgendaLoading({super.key});

  @override
  State<CalendarAgendaLoading> createState() => _CalendarAgendaLoadingState();
}

class _CalendarAgendaLoadingState extends State<CalendarAgendaLoading>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
    lowerBound: .55,
    upperBound: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHigh;
    return Semantics(
      label: 'Loading Calendar events',
      child: FadeTransition(
        opacity: _pulse,
        child: Column(
          mainAxisSize: .min,
          spacing: 12,
          children: [
            for (final count in [3, 2])
              Row(
                crossAxisAlignment: .start,
                spacing: 12,
                children: [
                  Container(
                    width: 44,
                    height: 56,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: .circular(28),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .stretch,
                      spacing: 2,
                      children: [
                        for (var index = 0; index < count; index++)
                          Container(
                            height: 56,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: connectedClockRowRadius(
                                first: index == 0,
                                last: index == count - 1,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

TextStyle _agendaType(
  BuildContext context,
  double size,
  double lineHeight,
  Color color, [
  FontWeight weight = .w400,
]) => Theme.of(context).textTheme.bodyMedium!.copyWith(
  color: color,
  fontSize: size,
  height: lineHeight / size,
  fontWeight: weight,
  letterSpacing: 0,
);

DateTime _civilDate(DateTime time) =>
    DateTime.utc(time.year, time.month, time.day);

String _time(MaterialLocalizations labels, DateTime time) => labels
    .formatTimeOfDay(TimeOfDay.fromDateTime(time), alwaysUse24HourFormat: true);
