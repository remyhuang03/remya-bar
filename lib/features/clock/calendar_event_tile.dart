part of 'calendar_agenda.dart';

class _EventTile extends StatefulWidget {
  const _EventTile({
    super.key,
    required this.event,
    required this.day,
    required this.now,
    required this.focusNode,
    required this.past,
    required this.live,
    required this.soon,
    required this.radius,
    required this.onOpen,
    required this.onJoin,
    required this.onHome,
  });

  final CalendarEvent event;
  final DateTime day;
  final DateTime now;
  final FocusNode? focusNode;
  final bool past;
  final bool live;
  final bool soon;
  final BorderRadius radius;
  final VoidCallback? onOpen;
  final VoidCallback? onJoin;
  final VoidCallback onHome;

  @override
  State<_EventTile> createState() => _EventTileState();
}

class _EventTileState extends State<_EventTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final colors = Theme.of(context).colorScheme;
    final labels = MaterialLocalizations.of(context);
    final fill = widget.past
        ? calendarReadableFill(
            Color.alphaBlend(
              event.fill.withValues(alpha: .45),
              colors.surfaceContainer,
            ),
          )
        : event.fill;
    final foreground = widget.past ? _pastForeground(fill) : Colors.white;
    final dashed =
        event.response == .awaitingReply || event.response == .tentative;
    final start = _time(labels, event.start);
    final end = _time(labels, event.end);
    final fullTime = event.allDay ? 'All day' : '$start – $end';
    final segment = event.allDay ? 'All day' : _segment(start, end);
    final location = calendarLocationLabel(event.location);
    final response = switch (event.response) {
      .awaitingReply => 'Awaiting reply',
      .tentative => 'Maybe',
      .declined => 'Declined',
      _ => '',
    };
    final live = widget.live ? _timeLeft(event.end.difference(widget.now)) : '';
    final allDayNote = event.allDay && event.duration.inDays > 1
        ? 'Day ${widget.day.difference(event.start).inDays + 1}/${event.duration.inDays}'
        : '';
    final meta = [
      response,
      segment,
      widget.live ? live : location,
    ].where((part) => part.isNotEmpty).join(' · ');
    final title = event.allDay && (allDayNote.isNotEmpty || response.isNotEmpty)
        ? [
            event.title,
            allDayNote,
            response,
          ].where((part) => part.isNotEmpty).join(' · ')
        : event.title;
    final semanticsLabel = [
      event.title,
      event.allDay ? 'All day' : '$start to $end',
      allDayNote,
      response,
      widget.live ? 'In progress, $live' : '',
      location,
      if (widget.onJoin != null) 'Has meeting link',
    ].where((part) => part.isNotEmpty).join(', ');
    void copy() => Clipboard.setData(
      ClipboardData(
        text:
            '${event.title}\n${widget.day.toIso8601String().split('T').first} · $fullTime',
      ),
    );
    final join = widget.onJoin;
    final open = widget.onOpen;
    final showChip = widget.live || widget.soon;
    return MenuAnchor(
      childFocusNode: widget.focusNode,
      menuChildren: [
        MenuItemButton(
          onPressed: open,
          child: const Text('Open in Google Calendar'),
        ),
        if (join != null)
          MenuItemButton(onPressed: join, child: const Text('Join meeting')),
        MenuItemButton(onPressed: copy, child: const Text('Copy title & time')),
        if (event.location.isNotEmpty)
          MenuItemButton(
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: event.location)),
            child: const Text('Copy location'),
          ),
        MenuItemButton(
          onPressed: widget.onHome,
          child: const Text('Google Calendar home'),
        ),
      ],
      builder: (context, menu, _) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
              FocusManager.instance.primaryFocus?.focusInDirection(.up),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
              FocusManager.instance.primaryFocus?.focusInDirection(.down),
          const SingleActivator(LogicalKeyboardKey.keyC): copy,
          const SingleActivator(LogicalKeyboardKey.keyJ): ?join,
          const SingleActivator(LogicalKeyboardKey.contextMenu): () =>
              menu.open(),
          const SingleActivator(LogicalKeyboardKey.f10, shift: true): () =>
              menu.open(),
        },
        child: GestureDetector(
          onSecondaryTapUp: (details) =>
              menu.open(position: details.localPosition),
          child: CustomPaint(
            foregroundPainter: _focused || dashed
                ? _TileOutline(
                    widget.radius,
                    _focused ? colors.secondary : event.rawColor,
                    dashed: dashed && !_focused,
                  )
                : null,
            child: Material(
              color: fill,
              clipBehavior: .antiAlias,
              borderRadius: widget.radius,
              child: Stack(
                children: [
                  Semantics(
                    label: semanticsLabel,
                    button: open != null,
                    child: InkWell(
                      onTap: open,
                      onFocusChange: (focused) =>
                          setState(() => _focused = focused),
                      focusNode: widget.focusNode,
                      onLongPress: () => menu.open(),
                      borderRadius: widget.radius,
                      child: Tooltip(
                        message: event.title,
                        waitDuration: const Duration(milliseconds: 600),
                        excludeFromSemantics: true,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: event.allDay ? 32 : 56,
                          ),
                          child: Padding(
                            padding: .fromLTRB(
                              14,
                              event.allDay ? 7 : 9,
                              (join != null ? 38 : 0) + 10,
                              event.allDay ? 7 : 9,
                            ),
                            child: Row(
                              spacing: 8,
                              children: [
                                Expanded(
                                  child: ExcludeSemantics(
                                    child: Column(
                                      mainAxisSize: .min,
                                      crossAxisAlignment: .start,
                                      children: [
                                        Text(
                                          title,
                                          maxLines: 1,
                                          overflow: .ellipsis,
                                          style: _agendaType(
                                            context,
                                            event.allDay ? 13 : 14,
                                            event.allDay ? 18 : 20,
                                            foreground,
                                            .w500,
                                          ),
                                        ),
                                        if (!event.allDay)
                                          Text(
                                            meta,
                                            maxLines: 1,
                                            overflow: .ellipsis,
                                            style: _agendaType(
                                              context,
                                              12,
                                              16,
                                              foreground,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (showChip)
                                  ExcludeSemantics(
                                    child: _EventChip(
                                      widget.live
                                          ? 'Now'
                                          : 'in ${_minutes(event.start.difference(widget.now))} min',
                                      fill,
                                      live: widget.live,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (join != null)
                    Positioned.fill(
                      left: null,
                      right: 4,
                      child: Center(
                        child: IconButton(
                          tooltip: 'Join meeting',
                          onPressed: join,
                          iconSize: 20,
                          padding: .zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 36,
                            height: 32,
                          ),
                          color: Colors.white,
                          icon: const Icon(Icons.videocam_outlined),
                        ),
                      ),
                    ),
                  if (widget.live)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        height: 3,
                        alignment: .centerLeft,
                        color: const Color(0x2E000000),
                        child: FractionallySizedBox(
                          widthFactor:
                              widget.now
                                  .difference(event.start)
                                  .inMicroseconds /
                              event.duration.inMicroseconds,
                          heightFactor: 1,
                          child: ColoredBox(color: event.rawColor),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _segment(String start, String end) {
    final event = widget.event;
    final day = widget.day;
    final startDay = _civilDate(event.start);
    final endDay = _civilDate(event.end);
    if (startDay == endDay) return '$start – $end';
    if (day == startDay) return 'from $start';
    if (day == endDay) return 'until $end';
    return 'Continues all day';
  }
}

class _TileOutline extends CustomPainter {
  const _TileOutline(this.radius, this.color, {required this.dashed});

  final BorderRadius radius;
  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = radius.toRRect(Offset.zero & size).deflate(dashed ? 1 : 2);
    final stroke = Paint()
      ..color = color
      ..style = .stroke
      ..strokeWidth = dashed ? 1.5 : 2;
    if (!dashed) {
      canvas.drawRRect(outline, stroke);
      return;
    }
    for (final edge in (Path()..addRRect(outline)).computeMetrics()) {
      for (var offset = 0.0; offset < edge.length; offset += 7) {
        canvas.drawPath(
          edge.extractPath(offset, math.min(offset + 4, edge.length)),
          stroke,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TileOutline old) =>
      old.radius != radius || old.color != color || old.dashed != dashed;
}

class _EventChip extends StatelessWidget {
  const _EventChip(this.label, this.fill, {required this.live});

  final String label;
  final Color fill;
  final bool live;

  @override
  Widget build(BuildContext context) => Container(
    padding: const .symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: live ? Colors.white : const Color(0x24141414),
      borderRadius: .circular(999),
    ),
    child: Text(
      label,
      style: _agendaType(context, 12, 16, live ? fill : Colors.white, .w500),
    ),
  );
}

int _minutes(Duration elapsed) =>
    (elapsed.inMicroseconds / Duration.microsecondsPerMinute).ceil();

String _timeLeft(Duration elapsed) {
  final minutes = _minutes(elapsed);
  if (minutes <= 0) return '<1 min left';
  if (minutes < 60) return '$minutes min left';
  final remainder = minutes % 60;
  return remainder == 0
      ? '${minutes ~/ 60} h left'
      : '${minutes ~/ 60} h $remainder min left';
}

Color _pastForeground(Color fill) {
  final limit = 4.5 * (fill.computeLuminance() + .05) - .05;
  for (var alpha = .45; alpha < 1; alpha += .05) {
    final color = Color.alphaBlend(Colors.white.withValues(alpha: alpha), fill);
    if (color.computeLuminance() >= limit) return color;
  }
  return Colors.white;
}
