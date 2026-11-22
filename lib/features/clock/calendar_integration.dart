import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:remya_client/remya_client.dart';

import '../settings/bar_preferences.dart';
import '../settings/bar_settings_controller.dart';
import 'calendar_dates.dart';
import 'calendar_events.dart';

typedef CalendarSource = ({
  String id,
  String name,
  String color,
  bool selected,
});

class CalendarSnapshot {
  const CalendarSnapshot({
    this.events = const [],
    this.syncedAt,
    this.error,
    this.loading = false,
  });

  final List<CalendarEvent> events;
  final DateTime? syncedAt;
  final String? error;
  final bool loading;
}

class CalendarIntegration extends ChangeNotifier {
  CalendarIntegration({SettingsClient? client})
    : _client = client ?? SettingsClient(),
      _ownsClient = client == null {
    settings = BarSettingsController(
      client: _client,
      keys: const ['calendar', 'calendar-last-view'],
      loadAiProviders: false,
    );
  }

  static final shared = CalendarIntegration();
  final SettingsClient _client;
  final bool _ownsClient;
  late final BarSettingsController settings;

  GoogleAccountStatus? account;
  bool accountRead = false;
  String? accountError;
  String? timezone;
  List<CalendarSource> calendars = const [];
  final _windows = <Object, CalendarWindow>{};
  final _snapshots = <CalendarWindow, CalendarSnapshot>{};
  final _running = <CalendarWindow, Future<void>>{};
  Future<void> _requestTail = Future.value();
  final _due = <CalendarWindow, DateTime>{};
  final _failures = <CalendarWindow, int>{};
  final _subscriptions = <StreamSubscription<Object?>>[];
  List<String>? _calendarIds;
  DBusClient? _systemBus;
  Timer? _timer;
  int _accountRead = 0;
  int _timeZoneRead = 0;
  int _generation = 0;
  bool _ready = false;
  bool _disposed = false;
  bool hideConnectPrompt = false;

  Map get preferences =>
      settings.values['calendar'] as Map? ?? calendarDefaults;
  bool get authRequired =>
      _snapshots.values.any((state) => state.error == 'auth');
  bool get connected => account?.calendar == true && account?.accountId != null;
  bool get weekByDefault => switch (preferences['default-view']) {
    'week' => true,
    'remember' => settings.values['calendar-last-view'] == 'week',
    _ => false,
  };

  CalendarSnapshot snapshot(CalendarWindow window) =>
      _snapshots[window] ?? CalendarSnapshot(loading: connected);

  bool visible(String id) {
    final source = calendars.where((source) => source.id == id).firstOrNull;
    return source == null ||
        barCalendarVisible(
          preferences,
          account?.accountId,
          id,
          source.selected,
        );
  }

  void retryAccount() => unawaited(_readAccount());

  List<String>? _selection() {
    final id = account?.accountId;
    if (id == null || preferences['calendar-account'] != id) return null;
    final hidden = preferences['hidden-calendars'] as List;
    final shown = preferences['shown-calendars'] as List;
    if ((hidden.isEmpty && shown.isEmpty) || calendars.isEmpty) return null;
    return [
      for (final source in calendars)
        if (barCalendarVisible(preferences, id, source.id, source.selected))
          source.id,
    ];
  }

  Future<void> start() async {
    if (_disposed || _subscriptions.isNotEmpty) return;
    settings.addListener(_settingsChanged);
    _subscriptions
      ..add(
        _client.changes.listen((change) {
          if (change.topic == googleAccountTopic) unawaited(_readAccount());
          if (change.topic == 'date-time') unawaited(_readTimezone());
        }, onError: (Object _) {}),
      )
      ..add(
        _client.serviceAvailableChanges.listen((available) {
          if (available) {
            unawaited(_readAccount());
            unawaited(_readTimezone());
          }
        }, onError: (Object _) {}),
      );
    await Future.wait([settings.start(), _readAccount(), _readTimezone()]);
    if (_disposed) return;
    _ready = true;
    final bus = _systemBus = DBusClient.system();
    _subscriptions.add(
      DBusSignalStream(
        bus,
        sender: 'org.freedesktop.login1',
        path: DBusObjectPath('/org/freedesktop/login1'),
        interface: 'org.freedesktop.login1.Manager',
        name: 'PrepareForSleep',
        signature: DBusSignature('b'),
      ).listen((signal) {
        if (!signal.values.single.asBoolean()) unawaited(refresh(force: true));
      }, onError: (Object _) {}),
    );
    const nm = 'org.freedesktop.NetworkManager';
    _subscriptions.add(
      DBusRemoteObject(
        bus,
        name: nm,
        path: DBusObjectPath('/org/freedesktop/NetworkManager'),
      ).propertiesChanged.listen((signal) {
        final state = signal.changedProperties['State'];
        if (signal.propertiesInterface == nm &&
            state is DBusUint32 &&
            state.value >= 60) {
          unawaited(refresh(force: true));
        }
      }, onError: (Object _) {}),
    );
    unawaited(refresh());
  }

  void _settingsChanged() {
    final ids = _selection();
    if (!listEquals(ids, _calendarIds)) {
      _calendarIds = ids;
      _generation++;
      _due.clear();
      unawaited(refresh());
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _readTimezone() async {
    final read = ++_timeZoneRead;
    try {
      final result = await _client.call('Get', ['date-time']);
      if (!_disposed && read == _timeZoneRead) {
        timezone = result['timezone'] as String?;
      }
    } catch (_) {
      // Keep using UTC timestamps for hand-off if timedated is unavailable.
    }
  }

  Future<void> _readAccount() async {
    final read = ++_accountRead;
    try {
      final next = await _client.googleAccountStatus();
      if (_disposed || read != _accountRead) return;
      final changed =
          account?.accountId != next.accountId ||
          account?.calendar != next.calendar;
      final reauthorized =
          account?.pending == true && !next.pending && next.error == null;
      account = next;
      accountRead = true;
      accountError = next.error;
      if (changed) {
        _generation++;
        calendars = const [];
        _calendarIds = null;
        _snapshots.clear();
        _due.clear();
        _failures.clear();
      } else if (reauthorized) {
        _snapshots.removeWhere((_, snapshot) => snapshot.error == 'auth');
      }
      notifyListeners();
      if (changed || reauthorized) unawaited(refresh(force: true));
    } catch (_) {
      if (_disposed || read != _accountRead) return;
      accountRead = true;
      accountError = 'Could not read the Google account.';
      notifyListeners();
    }
  }

  Future<void> connect() async {
    try {
      await _client.connectGoogleCalendar();
      await _readAccount();
    } catch (_) {
      if (_disposed) return;
      accountError = 'Could not start Google Calendar sign-in.';
      notifyListeners();
    }
  }

  Future<void> cancelAuthorization() async {
    try {
      await _client.cancelGoogleAuthorization();
      await _readAccount();
    } catch (_) {
      if (_disposed) return;
      accountError = 'Could not cancel Google sign-in.';
      notifyListeners();
    }
  }

  void dismissConnectPrompt() {
    hideConnectPrompt = true;
    notifyListeners();
  }

  void watch(Object view, CalendarWindow window) {
    if (_windows[view] == window) return;
    final wasOpen = _windows.isNotEmpty;
    _windows[view] = window;
    if (!wasOpen) {
      final last = _snapshots[window]?.syncedAt;
      if (last != null && DateTime.now().difference(last).inSeconds >= 60) {
        _due.remove(window);
      }
    }
    unawaited(refresh());
  }

  void unwatch(Object view) {
    _windows.remove(view);
    _schedule();
  }

  Future<void> rememberView(bool week) async {
    final value = week ? 'week' : 'month';
    if (preferences['default-view'] == 'remember' &&
        settings.values['calendar-last-view'] != value) {
      await settings.write('calendar-last-view', value);
    }
  }

  Iterable<CalendarWindow> get _activeWindows {
    if (_windows.isNotEmpty) return _windows.values.toSet();
    final today = calendarDay(DateTime.now());
    final rule = calendarWeekRule(
      preferences['week-start'] as String,
      PlatformDispatcher.instance.locale.toLanguageTag(),
    );
    return {
      calendarWindow(
        today,
        calendarWeekStart(DateTime.utc(today.year, today.month), rule.first),
      ),
    };
  }

  Future<void> refresh({bool force = false}) async {
    if (_disposed || !_ready || !connected) return;
    if (force) _due.clear();
    final now = DateTime.now();
    await Future.wait([
      for (final window in _activeWindows)
        if (!(_due[window]?.isAfter(now) ?? false))
          _running[window] ??= _enqueue(window),
    ]);
    _schedule();
  }

  Future<void> _enqueue(CalendarWindow window) {
    // Core serializes calendar requests for a Google account.
    return _requestTail = _requestTail
        .then((_) async {
          if (!_disposed && connected && _activeWindows.contains(window)) {
            await _fetch(window);
          }
        })
        .whenComplete(() {
          _running.remove(window);
          _schedule();
        });
  }

  Future<void> _fetch(CalendarWindow window) async {
    final id = account!.accountId!;
    final generation = _generation;
    final ids = _calendarIds;
    bool current() => !_disposed && generation == _generation;
    Future<Map<String, dynamic>> read({bool cacheOnly = false}) =>
        _client.googleCalendarRequest(
          accountId: id,
          timeMin: calendarBoundary(window.start),
          timeMax: calendarBoundary(window.end),
          calendarIds: ids,
          cacheOnly: cacheOnly,
        );

    if (_snapshots[window]?.syncedAt == null) {
      try {
        final cached = await read(cacheOnly: true);
        if (current()) _accept(window, cached);
      } catch (_) {
        // A period that has never been fetched has no cache.
      }
    }
    if (!current()) return;
    try {
      final response = await read();
      if (!current()) return;
      _accept(window, response);
      if (current()) _setDue(window, _snapshots[window]?.error);
    } catch (error) {
      if (!current()) return;
      final code = error is GoogleCalendarException ? error.code : 'retry';
      final last = _snapshots[window];
      _snapshots[window] = CalendarSnapshot(
        events: last?.events ?? const [],
        syncedAt: last?.syncedAt,
        error: code,
      );
      _setDue(window, code);
      notifyListeners();
    }
  }

  void _accept(CalendarWindow window, Map<String, dynamic> json) {
    final sources = [
      for (final row in json['calendars'] as List)
        if (row case {'id': final String id, 'summary': final String name})
          (
            id: id,
            name: name,
            color: row['backgroundColor'] as String? ?? '#70757A',
            selected: row['selected'] == true,
          ),
    ];
    final events = [
      for (final row in json['events'] as List) ?CalendarEvent.parse(row),
    ];
    calendars = List.unmodifiable(sources);
    final order = {
      for (var i = 0; i < calendars.length; i++) calendars[i].id: i,
    };
    events.sort(
      (a, b) => (order[a.calendarId] ?? 0).compareTo(order[b.calendarId] ?? 0),
    );
    if (_snapshots.length >= 12 && !_snapshots.containsKey(window)) {
      final evict = _snapshots.keys
          .where((key) => !_windows.containsValue(key))
          .firstOrNull;
      _snapshots.remove(evict);
      _due.remove(evict);
      _failures.remove(evict);
    }
    _snapshots[window] = CalendarSnapshot(
      events: List.unmodifiable(events),
      syncedAt: DateTime.tryParse(json['syncedAt'] as String? ?? ''),
      error: json['error'] as String?,
    );
    final ids = _selection();
    if (!listEquals(ids, _calendarIds)) {
      _calendarIds = ids;
      _generation++;
      _due.clear();
    }
    notifyListeners();
  }

  void _setDue(CalendarWindow window, String? error) {
    final int minutes;
    if (error == null) {
      _failures.remove(window);
      minutes = _windows.isEmpty ? 15 : 5;
    } else {
      final failures = _failures.update(
        window,
        (count) => (count + 1).clamp(0, 3),
        ifAbsent: () => 0,
      );
      minutes = const [1, 2, 5, 15][failures];
    }
    _due[window] = DateTime.now().add(Duration(minutes: minutes));
  }

  void _schedule() {
    _timer?.cancel();
    if (_disposed || !_ready || !connected) return;
    final now = DateTime.now();
    DateTime? earliest;
    for (final window in _activeWindows) {
      if (_running.containsKey(window)) continue;
      final due = _due[window] ?? now;
      if (earliest == null || due.isBefore(earliest)) earliest = due;
    }
    if (earliest != null) _timer = Timer(earliest.difference(now), refresh);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    settings.removeListener(_settingsChanged);
    settings.dispose();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_systemBus?.close());
    if (_ownsClient) unawaited(_client.close());
    super.dispose();
  }
}
