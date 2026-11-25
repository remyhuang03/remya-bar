import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:remya_client/remya_client.dart';

import 'tasks_models.dart';
import 'tasks_preferences.dart';

export 'tasks_models.dart';

part 'tasks_storage.dart';
part 'tasks_sync.dart';

const _undoDuration = Duration(seconds: 8);

/// One account-bound snapshot and status queue for all clock cards.
class TasksStore extends ChangeNotifier {
  TasksStore({SettingsClient? client, Directory? stateDirectory})
    : _client = client ?? SettingsClient(),
      _ownsClient = client == null,
      _root = stateDirectory;

  static final shared = TasksStore();

  final SettingsClient _client;
  final bool _ownsClient;
  final Directory? _root;
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _openCards = <Object>{};
  final _undos = <_TaskKey, Timer>{};
  DBusClient? _systemBus;
  Timer? _timer;
  Future<void>? _running;
  Future<GoogleAccountStatus>? _disconnecting;
  bool _started = false;
  bool _disposed = false;
  bool _readAccount = false;
  bool _pull = false;
  bool _full = false;
  bool _connecting = false;
  DateTime? _nextPull;
  DateTime? _retryAt;
  int _failures = 0;
  GoogleAccountStatus? _account;
  _TaskAccount? _data;
  TasksSyncState? _problem;
  String? _error;
  String? _workingOnError;
  TasksPreferences _preferences = const TasksPreferences();

  List<TaskList> _lists = const [];
  Map<_TaskKey, GoogleTask> _tasks = const {};
  List<GoogleTask> _rows = const [];

  GoogleAccountStatus? get account => _account;
  DateTime? get lastSync => _data?.cache.lastSync?.toLocal();
  int get pendingCount => _data?.changes.length ?? 0;
  List<TaskList> get lists => _lists;
  List<GoogleTask> get tasks => _rows;
  Set<String> get workingOnIds =>
      Set.unmodifiable(_data?.workingOn ?? const <String>{});
  String? get error =>
      _error ??
      _workingOnError ??
      (_data?.queueReadable == false
          ? 'Saved Tasks changes could not be loaded.'
          : null);

  GoogleTask? get undoTask {
    for (final key in _undos.keys.toList().reversed) {
      if (_tasks[key] case final task?) return task;
    }
    return null;
  }

  TasksSyncState get state {
    if (_problem case final problem?) return problem;
    if (_workingOnError != null ||
        _data?.queueReadable == false ||
        _data?.changes.any((change) => change.failed) == true) {
      return .error;
    }
    if (_account == null || _connecting || _account?.pending == true) {
      return .loading;
    }
    if (_account?.tasks != true || _account?.accountId == null) {
      return .disconnected;
    }
    if (_data == null || lastSync == null) return .loading;
    return _running == null ? .ready : .syncing;
  }

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _subscriptions
      ..add(
        _client.changes.listen((change) {
          if (change.topic == googleAccountTopic) unawaited(_accountChanged());
        }, onError: (Object _) {}),
      )
      ..add(
        _client.serviceAvailableChanges.listen((available) {
          if (available) unawaited(_accountChanged());
        }, onError: (Object _) {}),
      );
    if (_ownsClient) _watchEnvironment();
    unawaited(_accountChanged());
  }

  void _watchEnvironment() {
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
        if (!signal.values.single.asBoolean()) unawaited(refresh());
      }, onError: (Object _) {}),
    );
    const manager = 'org.freedesktop.NetworkManager';
    _subscriptions.add(
      DBusRemoteObject(
        bus,
        name: manager,
        path: DBusObjectPath('/org/freedesktop/NetworkManager'),
      ).propertiesChanged.listen((signal) {
        final state = signal.changedProperties['State'];
        if (signal.propertiesInterface == manager &&
            state is DBusUint32 &&
            state.value >= 60) {
          unawaited(refresh());
        }
      }, onError: (Object _) {}),
    );
  }

  void setPreferences(TasksPreferences preferences) {
    _preferences = preferences;
    _publish();
  }

  void setCardOpen(Object owner, bool open) {
    final wasOpen = _openCards.isNotEmpty;
    if (open) {
      _openCards.add(owner);
    } else {
      _openCards.remove(owner);
    }
    if (wasOpen == _openCards.isNotEmpty) return;
    if (_data?.cache.lastSync case final last?) {
      _nextPull = last.add(_pullInterval);
      if (open &&
          DateTime.now().difference(last) >= const Duration(seconds: 60)) {
        _pull = true;
      }
    }
    if (open && _pull) {
      unawaited(_run());
    } else {
      _schedule();
    }
  }

  Future<void> refresh({bool full = false}) {
    if (!_started) start();
    _readAccount = true;
    _pull = true;
    _full |= full;
    _retryAt = null;
    return _run();
  }

  Future<void> connect() async {
    if (_connecting || _disconnecting != null) return;
    _connecting = true;
    _notify();
    try {
      await _client.connectGoogleTasks();
      await _accountChanged();
    } on Object {
      _setProblem(.error, 'Could not open Google authorization.');
      rethrow;
    } finally {
      _connecting = false;
      _notify();
    }
  }

  Future<void> cancelAuthorization() async {
    await _client.cancelGoogleAuthorization();
    await _accountChanged();
  }

  Future<GoogleAccountStatus> disconnect({SettingsClient? client}) =>
      _disconnecting ??= Future<GoogleAccountStatus>.microtask(() async {
        final connector = client ?? _client;
        final account = _account?.accountId;
        try {
          await _running;
          if (account != null &&
              (await connector.googleAccountStatus()).accountId != account) {
            throw const TasksEditException(
              'The connected Google account changed.',
            );
          }
          return await connector.disconnectGoogleAccount();
        } finally {
          _disconnecting = null;
          await _accountChanged();
        }
      });

  Future<void> discardPendingChanges() async {
    final data = _editable();
    if (data.changes.any((change) => change.phase == .sending)) {
      throw const TasksEditException(
        'Wait for the current change to finish syncing.',
      );
    }
    final keys = data.changes.map((change) => change.key).toList();
    data.saveChanges([]);
    for (final key in keys) {
      _clearUndo(key);
    }
    _publish();
  }

  Future<void> retry() async {
    final data = _data;
    if (data != null && data.changes.any((change) => change.phase == .failed)) {
      data.saveChanges([
        for (final change in data.changes)
          if (change.phase == .failed) change.withPhase(.waiting) else change,
      ]);
    }
    await refresh();
  }

  GoogleTask? findTask(String listId, String taskId) =>
      _tasks[(listId, taskId)];

  Future<void> toggleWorkingOn(GoogleTask task) async {
    final data = _editable();
    final current = _requireTask(task, data);
    final ids = data.workingOn.toSet();
    if (!ids.remove(current.id)) {
      if (!_preferences.workingOnEnabled ||
          current.completed ||
          current.hidden ||
          current.scheduled == null ||
          !_listVisible(data, current.listId)) {
        throw const TasksEditException(
          'This task cannot be added to Working on.',
        );
      }
      if (ids.length >= _preferences.workingOnLimit) {
        throw const TasksEditException('Remove a task from Working on first.');
      }
      ids.add(current.id);
    }
    data.saveWorkingOn(ids);
    _publish();
  }

  Future<void> setCompleted(GoogleTask task, bool completed) async {
    final data = _editable();
    final current = _requireTask(task, data);
    if (current.assigned || current.hidden) {
      throw const TasksEditException('This task is read-only.');
    }
    if (!completed) {
      _undoCompletion(data, current.key);
      return;
    }
    if (current.completed) return;
    final previous = data.changes
        .where((change) => change.key == current.key)
        .lastOrNull;
    final change = _StatusChange(
      current.key,
      previous?.completed == true ? previous!.base : current.completed,
      true,
    );
    _queueChange(data, change);
    _clearUndo(current.key);
    _undos[current.key] = Timer(_undoDuration, () {
      _clearUndo(current.key);
      _publish();
    });
    _publish();
    unawaited(_run());
  }

  Future<void> undoCompletion() async {
    if (undoTask case final task?) _undoCompletion(_editable(), task.key);
  }

  void _undoCompletion(_TaskAccount data, _TaskKey key) {
    if (!_undos.containsKey(key)) return;
    final matching = data.changes.where((change) => change.key == key);
    final original = matching.lastOrNull;
    final cachedCompleted =
        _completed(data.cache.tasks[key]?['status']) == true;
    if (original?.phase == .queued &&
        matching.length == 1 &&
        !cachedCompleted) {
      data.saveChanges(
        data.changes.where((change) => change.key != key).toList(),
      );
    } else {
      _queueChange(data, _StatusChange(key, true, false));
    }
    _clearUndo(key);
    _publish();
    unawaited(_run());
  }

  void _queueChange(_TaskAccount data, _StatusChange next) {
    data.saveChanges([
      for (final change in data.changes)
        if (change.key != next.key || change.phase == .sending) change,
      next,
    ]);
  }

  void _clearUndo(_TaskKey key) => _undos.remove(key)?.cancel();

  _TaskAccount _editable() {
    final data = _data;
    if (_disconnecting != null || data == null) {
      throw const TasksEditException('Connect Google Tasks to save changes.');
    }
    return data;
  }

  GoogleTask _requireTask(GoogleTask task, _TaskAccount data) {
    if (task.accountId != data.id) {
      throw const TasksEditException(
        'This item belongs to a different Google account.',
      );
    }
    final current = _tasks[task.key];
    if (current == null) {
      throw const TasksEditException('This task is no longer available.');
    }
    return current;
  }

  bool _listVisible(_TaskAccount data, String list) {
    final visible = _preferences.visibleListsFor(data.id);
    return visible.isEmpty || visible.contains(list);
  }

  void _setProblem(TasksSyncState? problem, String? message) {
    _problem = problem;
    _error = message;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    for (final timer in _undos.values) {
      timer.cancel();
    }
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_systemBus?.close());
    if (_ownsClient) unawaited(_client.close());
    super.dispose();
  }
}
