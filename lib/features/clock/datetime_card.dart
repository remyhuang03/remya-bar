import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../google/google_links.dart';
import '../tasks/tasks_block.dart';
import '../tasks/tasks_integration.dart';
import 'bar_clock.dart';
import 'calendar_agenda.dart';
import 'calendar_clock_hero.dart';
import 'calendar_dates.dart';
import 'calendar_grid.dart';
import 'calendar_integration.dart';
import 'calendar_links.dart';
import 'clock_card_controls.dart';

class DatetimeCard extends StatefulWidget {
  const DatetimeCard({
    super.key,
    required this.wide,
    required this.onCalendarSettings,
    required this.onTasksSettings,
    required this.onDateTimeSettings,
    required this.onClose,
  });

  final bool wide;
  final VoidCallback onCalendarSettings;
  final VoidCallback onTasksSettings;
  final VoidCallback? onDateTimeSettings;
  final VoidCallback onClose;

  @override
  State<DatetimeCard> createState() => _DatetimeCardState();
}

class _DatetimeCardState extends State<DatetimeCard> {
  final _integration = CalendarIntegration.shared;
  final _tasksIntegration = TasksIntegration.shared;
  final _agenda = GlobalKey<CalendarAgendaState>();
  late DateTime _now;
  DateTime? _day;
  bool? _week;
  Object? _defaultView;
  CalendarWindow? _window;
  String? _linkError;

  DateTime get _today => calendarDay(_now);
  DateTime get _selected => _day ?? _today;
  bool get _weekView => _week ?? _integration.weekByDefault;
  String? get _email => _integration.account?.email;

  @override
  void initState() {
    super.initState();
    _now = barClockSource.attach(_tick, seconds: false);
    _defaultView = _integration.preferences['default-view'];
    _integration.addListener(_onIntegration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _watch();
  }

  void _tick(DateTime now) {
    setState(() => _now = now);
    _watch();
  }

  ({int first, int cutoff}) get _weekRule => calendarWeekRule(
    _integration.preferences['week-start'] as String,
    View.of(context).platformDispatcher.locale.toLanguageTag(),
  );

  void _watch() {
    final selected = _selected;
    final start = calendarWeekStart(
      DateTime.utc(selected.year, selected.month),
      _weekRule.first,
    );
    final next = calendarWindow(selected, start);
    if (_window == next) return;
    _window = next;
    // A popup can be created while the shared application is building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _window == next) _integration.watch(this, next);
    });
  }

  void _onIntegration() {
    final defaultView = _integration.preferences['default-view'];
    setState(() {
      if (_defaultView != defaultView) _week = null;
      _defaultView = defaultView;
    });
    _watch();
  }

  void _select(DateTime day) {
    if (day == _selected) return;
    setState(() => _day = day == _today ? null : day);
    _watch();
  }

  void _toggle() {
    final week = !_weekView;
    setState(() => _week = week);
    unawaited(_integration.rememberView(week));
  }

  Future<void> _open(Uri? uri) async {
    try {
      await openGoogleBrowser(uri);
      if (mounted && _linkError != null) setState(() => _linkError = null);
    } catch (_) {
      if (mounted) setState(() => _linkError = 'Could not open this link.');
    }
  }

  void _new() => unawaited(
    _open(calendarNewEvent(_selected, _now, _integration.timezone, _email)),
  );

  void _home() => unawaited(_open(calendarLink('r', _email)));

  void _openDay(DateTime day) => unawaited(
    _open(calendarLink('r/day/${day.year}/${day.month}/${day.day}', _email)),
  );

  void _refresh() => unawaited(_integration.refresh(force: true));

  KeyEventResult _calendarKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return .ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyT:
        _select(_today);
      case LogicalKeyboardKey.keyV:
        _toggle();
      case LogicalKeyboardKey.keyN:
        _new();
      case LogicalKeyboardKey.keyG:
        _home();
      case LogicalKeyboardKey.keyR:
        _refresh();
      default:
        return .ignored;
    }
    return .handled;
  }

  Widget _calendarFocus(Widget child) =>
      Focus(canRequestFocus: false, onKeyEvent: _calendarKey, child: child);

  Widget _tasks({required bool scrollable}) => FocusTraversalOrder(
    order: const NumericFocusOrder(0),
    child: ListenableBuilder(
      listenable: _tasksIntegration.settings,
      builder: (context, _) => TasksBlock(
        store: _tasksIntegration.store,
        preferences: _tasksIntegration.preferences,
        onSettings: widget.onTasksSettings,
        scrollable: scrollable,
        now: _now,
      ),
    ),
  );

  @override
  void dispose() {
    barClockSource.detach(_tick);
    _integration.removeListener(_onIntegration);
    _integration.unwatch(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = _integration.preferences;
    final snapshot = _integration.snapshot(_window!);
    final events = [
      for (final event in snapshot.events)
        if ((prefs['show-declined'] == true || !event.declined) &&
            _integration.visible(event.calendarId))
          event,
    ];
    final (first: first, cutoff: cutoff) = _weekRule;
    final connected = _integration.connected;
    final error =
        _linkError ??
        switch (snapshot.error) {
          'auth' => 'Google sign-in expired',
          'offline' => 'Offline',
          'unavailable' => 'Google Calendar unavailable',
          String() => 'Couldn’t refresh',
          _ => connected ? null : _integration.accountError,
        };
    final Widget? placeholder = connected
        ? snapshot.loading
              ? const CalendarAgendaLoading()
              : snapshot.error != null && snapshot.syncedAt == null
              ? const Text('Calendar events unavailable', textAlign: .center)
              : null
        : _integration.hideConnectPrompt
        ? const SizedBox.shrink()
        : _ConnectCalendar(
            pending: _integration.account?.pending == true,
            configured: _integration.account?.configured != false,
            onConnect: () => unawaited(_integration.connect()),
            onCancel: () => unawaited(_integration.cancelAuthorization()),
            onDismiss: _integration.dismissConnectPrompt,
          );
    final hero = FocusTraversalOrder(
      order: const NumericFocusOrder(2),
      child: CalendarClockHero(
        showSeconds: prefs['show-seconds'] == true,
        onSettings: widget.onDateTimeSettings,
      ),
    );
    final calendarHeader = Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      spacing: 16,
      children: [
        ClockCardHeader(
          title: 'Calendar',
          newTooltip: 'New event',
          googleLabel: 'Open in Google Calendar',
          onNew: _new,
          onGoogle: _home,
          onRefresh: _refresh,
          onSettings: widget.onCalendarSettings,
        ),
        CalendarGrid(
          today: _today,
          selected: _selected,
          firstWeekday: first,
          cutoffWeekday: cutoff,
          week: _weekView,
          showWeekNumbers: prefs['show-week-numbers'] == true,
          events: events,
          onSelect: _select,
          onOpenDay: _openDay,
          onToggle: _toggle,
          onAgenda: () => _agenda.currentState?.focusFirstEvent(),
          autofocus: false,
        ),
        if (error != null)
          ClockCardStatusBanner(
            message: error,
            icon: _linkError != null
                ? Icons.link_off
                : snapshot.error == 'offline'
                ? Icons.cloud_off_outlined
                : Icons.error_outline,
            action: _linkError != null
                ? 'Dismiss'
                : snapshot.error == 'auth'
                ? _integration.account?.pending == true
                      ? 'Cancel sign-in'
                      : 'Reconnect'
                : 'Retry',
            onAction: _linkError != null
                ? () => setState(() => _linkError = null)
                : snapshot.error == 'auth'
                ? _integration.account?.pending == true
                      ? () => unawaited(_integration.cancelAuthorization())
                      : () => unawaited(_integration.connect())
                : !connected
                ? _integration.retryAccount
                : _refresh,
          ),
      ],
    );

    Widget agenda({Widget? leading}) => CalendarAgenda(
      key: _agenda,
      selectedDay: _selected,
      now: _now,
      events: events,
      rangeDays: prefs['agenda-range'] as int,
      foldFinished: prefs['fold-finished'] == true,
      showDeclined: prefs['show-declined'] == true,
      onOpen: (event) =>
          unawaited(_open(calendarEventLink(event.htmlLink, _email))),
      onJoin: (event) =>
          unawaited(_open(googleAuthUser(event.meetingLink, _email))),
      leading: leading,
      placeholder: placeholder,
      onKeyEvent: leading == null ? null : _calendarKey,
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(secondary: WidgetOrderTraversalPolicy()),
        child: LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            height: math.min(clockCardMaxHeight, constraints.maxHeight),
            child: Padding(
              padding: const .all(24),
              child: LayoutBuilder(
                builder: (context, body) {
                  final scale = MediaQuery.textScalerOf(context);
                  final heroFits = body.maxHeight >= scale.scale(112);
                  if (!widget.wide) {
                    final scroll = FocusTraversalOrder(
                      order: const NumericFocusOrder(1),
                      child: agenda(
                        leading: Column(
                          crossAxisAlignment: .stretch,
                          spacing: 16,
                          children: [
                            if (!heroFits) hero,
                            _tasks(scrollable: false),
                            _calendarFocus(calendarHeader),
                            const SizedBox.shrink(),
                          ],
                        ),
                      ),
                    );
                    return heroFits
                        ? Column(
                            crossAxisAlignment: .stretch,
                            spacing: 16,
                            children: [
                              hero,
                              Expanded(child: scroll),
                            ],
                          )
                        : scroll;
                  }

                  final calendarChrome =
                      math.max(48.0, scale.scale(29)) +
                      (_weekView ? 112 : 292) +
                      math.max(0.0, scale.scale(14) - 18) +
                      32 +
                      (error == null
                          ? 0
                          : math.max(48.0, scale.scale(56)) + 16);
                  return Row(
                    crossAxisAlignment: .stretch,
                    spacing: 24,
                    children: [
                      Expanded(
                        child: heroFits
                            ? Column(
                                crossAxisAlignment: .stretch,
                                spacing: 16,
                                children: [
                                  hero,
                                  Expanded(
                                    child: LayoutBuilder(
                                      builder: (context, bounds) =>
                                          bounds.maxHeight >= scale.scale(136)
                                          ? _tasks(scrollable: true)
                                          : SingleChildScrollView(
                                              child: _tasks(scrollable: false),
                                            ),
                                    ),
                                  ),
                                ],
                              )
                            : SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: .stretch,
                                  spacing: 16,
                                  children: [hero, _tasks(scrollable: false)],
                                ),
                              ),
                      ),
                      Expanded(
                        child: FocusTraversalOrder(
                          order: const NumericFocusOrder(1),
                          child: body.maxHeight > calendarChrome
                              ? _calendarFocus(
                                  Column(
                                    crossAxisAlignment: .stretch,
                                    spacing: 16,
                                    children: [
                                      calendarHeader,
                                      Expanded(child: agenda()),
                                    ],
                                  ),
                                )
                              : agenda(
                                  leading: Padding(
                                    padding: const .only(bottom: 16),
                                    child: _calendarFocus(calendarHeader),
                                  ),
                                ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectCalendar extends StatelessWidget {
  const _ConnectCalendar({
    required this.pending,
    required this.configured,
    required this.onConnect,
    required this.onCancel,
    required this.onDismiss,
  });

  final bool pending;
  final bool configured;
  final VoidCallback onConnect;
  final VoidCallback onCancel;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const .all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: .circular(24),
      ),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 12,
        children: [
          Container(
            padding: const .all(12),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: .circular(16),
            ),
            child: Icon(
              Icons.event_available,
              color: colors.onPrimaryContainer,
            ),
          ),
          Text(
            'Connect Google Calendar',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            pending
                ? 'Finish signing in in your browser.'
                : configured
                ? 'See your events under the clock. New events and edits open in Google Calendar.'
                : 'Google sign-in is unavailable on this installation.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Wrap(
            spacing: 8,
            children: [
              if (pending)
                OutlinedButton(
                  onPressed: onCancel,
                  child: const Text('Cancel sign-in'),
                )
              else
                FilledButton(
                  onPressed: configured ? onConnect : null,
                  child: const Text('Connect'),
                ),
              TextButton(onPressed: onDismiss, child: const Text('Not now')),
            ],
          ),
        ],
      ),
    );
  }
}
