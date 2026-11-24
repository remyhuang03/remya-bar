import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'bar_clock.dart';
import 'calendar_agenda.dart';
import 'calendar_clock_hero.dart';
import 'calendar_dates.dart';
import 'calendar_grid.dart';
import 'calendar_integration.dart';
import 'calendar_links.dart';

class DatetimeCard extends StatefulWidget {
  const DatetimeCard({
    super.key,
    required this.onSettings,
    required this.onDateTimeSettings,
    required this.onClose,
  });

  final VoidCallback onSettings;
  final VoidCallback? onDateTimeSettings;
  final VoidCallback onClose;

  @override
  State<DatetimeCard> createState() => _DatetimeCardState();
}

class _DatetimeCardState extends State<DatetimeCard> {
  final _integration = CalendarIntegration.shared;
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
      await openCalendarLink(uri);
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

  KeyEventResult _key(FocusNode node, KeyEvent event) {
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
        unawaited(_integration.refresh(force: true));
      case LogicalKeyboardKey.escape:
        widget.onClose();
      default:
        return .ignored;
    }
    return .handled;
  }

  @override
  void dispose() {
    barClockSource.detach(_tick);
    _integration.removeListener(_onIntegration);
    _integration.unwatch(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
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
          'offline' => switch (snapshot.syncedAt) {
            final synced? =>
              'Offline · synced at ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(synced.toLocal()))}',
            _ => 'Offline',
          },
          'unavailable' => 'Google Calendar unavailable',
          String() => 'Couldn’t refresh',
          _ => connected ? null : _integration.accountError,
        };
    final Widget? agenda = connected
        ? snapshot.loading
              ? const CalendarAgendaLoading()
              : snapshot.error != null && snapshot.syncedAt == null
              ? const Center(child: Text('Calendar events unavailable'))
              : CalendarAgenda(
                  key: _agenda,
                  selectedDay: _selected,
                  now: _now,
                  events: events,
                  rangeDays: prefs['agenda-range'] as int,
                  foldFinished: prefs['fold-finished'] == true,
                  showDeclined: prefs['show-declined'] == true,
                  onOpen: (event) => unawaited(
                    _open(calendarEventLink(event.htmlLink, _email)),
                  ),
                  onJoin: (event) => unawaited(_open(event.meetingLink)),
                  onHome: _home,
                  onNew: _new,
                )
        : _integration.hideConnectPrompt
        ? null
        : _ConnectCalendar(
            pending: _integration.account?.pending == true,
            configured: _integration.account?.configured != false,
            onConnect: () => unawaited(_integration.connect()),
            onCancel: () => unawaited(_integration.cancelAuthorization()),
            onDismiss: _integration.dismissConnectPrompt,
          );
    final header = [
      Row(
        children: [
          Expanded(
            child: Text(
              'Calendar',
              style: TextStyle(
                color: colors.primary,
                fontSize: 24,
                fontWeight: .w700,
                height: 29 / 24,
              ),
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'New event',
            onPressed: _new,
            icon: const Icon(Icons.add),
          ),
          IconButton.filledTonal(
            tooltip: 'Calendar settings',
            onPressed: widget.onSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      CalendarClockHero(
        showSeconds: prefs['show-seconds'] == true,
        onSettings: widget.onDateTimeSettings,
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
      ),
      if (error != null)
        _CalendarBanner(
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
              : () => unawaited(_integration.refresh(force: true)),
        ),
    ];
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _key,
      child: Padding(
        padding: const .all(24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (!connected) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: .stretch,
                  spacing: 16,
                  children: [...header, ?agenda],
                ),
              );
            }
            // Retain a reachable agenda when the output cannot fit pinned controls.
            final minHeight =
                (_weekView ? 112.0 : 292.0) +
                48 +
                98 +
                48 +
                160 +
                (error == null ? 0 : 64);
            final available = math.min(constraints.maxHeight, 880.0 - 48);
            final body = SizedBox(
              height: math.max(available, minHeight),
              child: Column(
                spacing: 16,
                crossAxisAlignment: .stretch,
                children: [
                  ...header,
                  Expanded(child: agenda!),
                ],
              ),
            );
            return available >= minHeight
                ? body
                : SingleChildScrollView(child: body);
          },
        ),
      ),
    );
  }
}

class _CalendarBanner extends StatelessWidget {
  const _CalendarBanner({
    required this.message,
    required this.icon,
    required this.action,
    required this.onAction,
  });

  final String message;
  final IconData icon;
  final String action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textStyle = theme.textTheme.bodySmall;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: .circular(16),
        color: colors.errorContainer,
      ),
      child: Padding(
        padding: const .fromLTRB(14, 0, 6, 0),
        child: Row(
          spacing: 8,
          children: [
            Icon(icon, size: 18, color: colors.onErrorContainer),
            Expanded(
              child: Text(
                message,
                style: textStyle?.copyWith(color: colors.onErrorContainer),
              ),
            ),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: colors.onErrorContainer,
                textStyle: textStyle?.copyWith(fontWeight: .w500),
              ),
              child: Text(action),
            ),
          ],
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
