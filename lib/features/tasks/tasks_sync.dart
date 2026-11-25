part of 'tasks_store.dart';

const _overlap = Duration(minutes: 2);
const _fullInterval = Duration(minutes: 30);
const _retryMinutes = [1, 2, 5, 15];
const _showAll = {
  'showCompleted': true,
  'showDeleted': true,
  'showHidden': true,
  'showAssigned': true,
};

extension _TasksSync on TasksStore {
  Duration get _pullInterval => Duration(minutes: _openCards.isEmpty ? 15 : 5);

  Future<void> _accountChanged() {
    _readAccount = true;
    _retryAt = null;
    return _run();
  }

  Future<void> _run() {
    if (_disposed || !_started || _disconnecting != null) return Future.value();
    if (_running case final current?) return current;
    if (_retryAt case final time? when time.isAfter(DateTime.now().toUtc())) {
      _schedule();
      return Future.value();
    }
    return _running = Future<void>.microtask(_work);
  }

  Future<void> _work() async {
    try {
      while (!_disposed && _disconnecting == null) {
        if (_readAccount) {
          _readAccount = false;
          try {
            await _readStatus();
          } on Object {
            _readAccount = true;
            rethrow;
          }
        }
        if (_problem == .authRequired || _account?.pending == true) return;

        final data = _data;
        if (data == null || _account?.tasks != true) {
          _pull = false;
          _full = false;
          _nextPull = null;
          return;
        }
        if (_nextChange(data) case final change? when data.queueReadable) {
          await _send(data, change);
          continue;
        }
        final now = DateTime.now().toUtc();
        if (_nextPull case final next? when next.isAfter(now) && !_pull) return;

        final lastFull = data.cache.lastFull;
        final full =
            _full ||
            lastFull == null ||
            now.difference(lastFull) >= _fullInterval;
        _pull = false;
        _full = false;
        try {
          await _pullTasks(data, full: full);
        } on Object {
          _pull = true;
          _full |= full;
          rethrow;
        }
        _nextPull = data.cache.lastSync!.add(_pullInterval);
        _clearBackoff();
        _publish(full: full);
      }
    } on Object catch (error) {
      _handleFailure(error);
    } finally {
      _running = null;
      _notify();
      _schedule();
    }
  }

  Future<void> _readStatus() async {
    final status = await _client.googleAccountStatus();
    if (_disposed) return;
    final subject = status.accountId;
    final same = _data?.id == subject;
    final hadGrant = _account?.tasks == true;
    final reconnect = _problem == .authRequired || _account?.pending == true;
    _account = status;
    if (!same) {
      for (final key in _undos.keys.toList()) {
        _clearUndo(key);
      }
      _data = null;
      _nextPull = null;
      _workingOnError = null;
      _clearBackoff();
      _publish();
      if (subject != null) {
        final data = _TaskAccount(subject, _root ?? _taskStateRoot());
        await data.read();
        if (_disposed) return;
        _data = data;
      }
    }
    if (status.tasks && (!same || !hadGrant || reconnect)) {
      _pull = true;
    }
    if (reconnect && status.tasks) _clearBackoff();
    _publish();
  }

  void _schedule() {
    _timer?.cancel();
    if (_disposed || !_started || _disconnecting != null) return;
    if (!_readAccount &&
        (_problem == .authRequired ||
            _account?.pending == true ||
            _account?.tasks != true)) {
      return;
    }
    final time =
        _retryAt ??
        (_readAccount || _pull ? DateTime.now().toUtc() : _nextPull);
    if (time == null) return;
    final delay = time.difference(DateTime.now().toUtc());
    _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      unawaited(_run());
    });
  }

  void _clearBackoff() {
    _retryAt = null;
    _failures = 0;
    _problem = null;
    _error = null;
  }

  void _handleFailure(Object error) {
    final code = error is GoogleTasksException ? error.code : null;
    if (code == 'auth') {
      _nextPull = null;
      _setProblem(.authRequired, 'Reconnect to sync your changes.');
      return;
    }
    final offline =
        code == 'offline' ||
        error is SocketException ||
        error is TimeoutException;
    final storage = error is FileSystemException || error is TasksEditException;
    final delay = Duration(
      minutes: _retryMinutes[min(_failures++, _retryMinutes.length - 1)],
    );
    _retryAt = DateTime.now().toUtc().add(delay);
    _setProblem(
      offline ? .offline : .error,
      offline
          ? 'Offline'
          : storage
          ? 'Could not save Tasks data on this device.'
          : 'Couldn’t sync. Your changes are saved on this device.',
    );
  }

  Future<_Json> _call(
    _TaskAccount data,
    String operation, [
    _Json args = const {},
  ]) => _client.googleTasksRequest(data.id, operation, args: args);

  Future<Map<String, _Json>> _pages(
    _TaskAccount data,
    String operation,
    _Json args,
  ) async {
    final entries = <String, _Json>{};
    final seenTokens = <String>{};
    String? pageToken;
    do {
      final page = await _call(data, operation, {
        ...args,
        'pageToken': ?pageToken,
      });
      final items = (page['items'] as List?) ?? const [];
      for (final entry in items.cast<_Json>()) {
        entries[_id(entry)] = entry;
      }
      pageToken = page['nextPageToken'] as String?;
      if (pageToken != null && !seenTokens.add(pageToken)) {
        throw const FormatException(
          'Google Tasks returned a repeated page token.',
        );
      }
    } while (pageToken != null && pageToken.isNotEmpty);
    return entries;
  }

  Future<void> _pullTasks(_TaskAccount data, {required bool full}) async {
    final checkpoint = DateTime.now().toUtc();
    final prior = data.cache;
    final lists = await _pages(data, 'lists.list', {});
    final tasks = <_TaskKey, _Json>{
      if (!full)
        for (final entry in prior.tasks.entries)
          if (lists.containsKey(entry.key.$1)) entry.key: entry.value,
    };
    // Core serializes Tasks requests, including pages.
    for (final listId in lists.keys) {
      final updatedMin = !full && prior.lists.containsKey(listId)
          ? prior.checkpoint?.subtract(_overlap)
          : null;
      final page = await _pages(data, 'tasks.list', {
        'listId': listId,
        ..._showAll,
        if (updatedMin != null) 'updatedMin': updatedMin.toIso8601String(),
      });
      for (final entry in page.entries) {
        tasks[(listId, entry.key)] = {...entry.value, 'listId': listId};
      }
    }
    if (full && data.workingOn.isNotEmpty) {
      final fetchedIds = tasks.keys.map((key) => key.$2).toSet();
      for (final key in prior.tasks.keys) {
        if (!data.workingOn.contains(key.$2) ||
            fetchedIds.contains(key.$2) ||
            !lists.containsKey(key.$1)) {
          continue;
        }
        final task = await _get(data, key);
        if (task != null) tasks[key] = {...task, 'listId': key.$1};
      }
    }
    await data.saveCache(
      _TaskCache(
        lists: lists,
        tasks: tasks,
        lastSync: DateTime.now().toUtc(),
        checkpoint: checkpoint,
        lastFull: full ? checkpoint : prior.lastFull,
      ),
    );
  }

  Future<_Json?> _get(_TaskAccount data, _TaskKey key) async {
    try {
      final result = await _call(data, 'tasks.get', {
        'listId': key.$1,
        'taskId': key.$2,
      });
      return result['deleted'] == true ? null : result;
    } on GoogleTasksException catch (error) {
      if (error.code == 'missing') return null;
      rethrow;
    }
  }

  _StatusChange? _nextChange(_TaskAccount data) {
    final seen = <_TaskKey>{};
    for (final change in data.changes) {
      if (seen.add(change.key) &&
          (change.phase == .queued || change.phase == .waiting)) {
        return change;
      }
    }
    return null;
  }

  Future<void> _send(_TaskAccount data, _StatusChange change) async {
    var active = change;
    try {
      final fresh = await _get(data, change.key);
      if (_disposed ||
          _disconnecting != null ||
          _readAccount ||
          !data.changes.contains(change)) {
        return;
      }
      if (fresh == null ||
          fresh['hidden'] == true ||
          fresh['assignmentInfo'] != null) {
        await _settle(data, change, fresh);
        _clearUndo(change.key);
        _clearBackoff();
        _publish();
        return;
      }
      final status = _completed(fresh['status']);
      if (status == null) {
        throw const FormatException('Invalid Google Task status');
      }
      if (status == change.base && status != change.completed) {
        final sending = change.withPhase(.sending);
        _replaceChange(data, change, sending);
        active = sending;
        final response = await _call(data, 'tasks.patch', {
          ...change.target,
          'body': {'status': _status(change.completed)},
        });
        if (_completed(response['status']) == null) {
          throw const FormatException('Invalid Google Task status response');
        }
        await _settle(data, active, {...fresh, ...response});
      } else {
        await _settle(data, change, fresh);
        if (status != change.completed ||
            (status != change.base && change.phase == .queued)) {
          _clearUndo(change.key);
        }
      }
      _clearBackoff();
      _publish();
    } on Object catch (error) {
      if (!data.changes.contains(active)) return;
      final superseded = data.changes.any(
        (other) => other != active && other.key == change.key,
      );
      final code = error is GoogleTasksException ? error.code : null;
      final retryable =
          code == null ||
          const {
            'auth',
            'offline',
            'retry',
            'unavailable',
            'ambiguous',
            'missing',
          }.contains(code);
      try {
        _replaceChange(
          data,
          active,
          superseded ? null : active.withPhase(retryable ? .waiting : .failed),
        );
      } on TasksEditException {
        // A failed journal update still needs a fresh status check before any retry.
        data.changes = [
          for (final change in data.changes)
            if (change == active) change.withPhase(.waiting) else change,
        ];
        _publish();
        rethrow;
      }
      if (!retryable) _clearBackoff();
      _publish();
      if (retryable) rethrow;
    }
  }

  void _replaceChange(
    _TaskAccount data,
    _StatusChange old,
    _StatusChange? next,
  ) {
    final changes = [
      for (final change in data.changes)
        if (change != old) change else ?next,
    ];
    data.saveChanges(changes);
  }

  Future<void> _settle(
    _TaskAccount data,
    _StatusChange change,
    _Json? remote,
  ) async {
    final prior = data.cache;
    final tasks = Map<_TaskKey, _Json>.of(prior.tasks);
    if (remote == null) {
      tasks[change.key] = {
        'id': change.key.$2,
        'listId': change.key.$1,
        'deleted': true,
      };
    } else {
      tasks[change.key] = {...remote, 'listId': change.key.$1};
    }
    await data.saveCache(
      _TaskCache(
        lists: prior.lists,
        tasks: tasks,
        lastSync: prior.lastSync,
        checkpoint: prior.checkpoint,
        lastFull: prior.lastFull,
      ),
    );
    _replaceChange(data, change, null);
  }

  void _pruneWorkingOn(_TaskAccount data, {required bool full}) {
    if (!data.workingOnReadable) {
      _workingOnError = 'Saved Working on tasks could not be loaded.';
      return;
    }
    if (data.workingOn.isEmpty) return;
    final keep = <String>{};
    for (final id in data.workingOn) {
      if (keep.length >= _preferences.workingOnLimit) break;
      final matches = data.cache.tasks.entries.where(
        (entry) => entry.key.$2 == id,
      );
      if (matches.isEmpty && !full ||
          matches.any((entry) {
            final key = entry.key;
            final task = entry.value;
            return task['deleted'] != true &&
                data.cache.lists.containsKey(key.$1) &&
                _listVisible(data, key.$1) &&
                (_completed(task['status']) != true ||
                    _undos.containsKey(key) ||
                    data.changes.any(
                      (change) =>
                          change.key == key &&
                          !change.completed &&
                          !change.failed,
                    ));
          })) {
        keep.add(id);
      }
    }
    try {
      if (keep.length != data.workingOn.length) data.saveWorkingOn(keep);
      _workingOnError = null;
    } on TasksEditException catch (error) {
      _workingOnError = error.message;
    }
  }

  void _publish({bool full = false}) {
    final data = _data;
    if (data == null || _account?.tasks != true) {
      _lists = const [];
      _tasks = const {};
      _rows = const [];
      _notify();
      return;
    }
    _pruneWorkingOn(data, full: full);
    final changes = {for (final change in data.changes) change.key: change};
    _lists = List.unmodifiable([
      for (final entry in data.cache.lists.entries)
        if (entry.value['deleted'] != true)
          TaskList(
            id: entry.key,
            title: (entry.value['title'] as String?) ?? '',
          ),
    ]);
    _tasks = {
      for (final entry in data.cache.tasks.entries)
        if (entry.value['deleted'] != true &&
            data.cache.lists.containsKey(entry.key.$1))
          entry.key: _model(
            entry.value,
            accountId: data.id,
            completed: changes[entry.key]?.failed == false
                ? changes[entry.key]!.completed
                : null,
            pending: changes[entry.key]?.failed == false,
            syncError: changes[entry.key]?.failed == true,
            completionUndoable: _undos.containsKey(entry.key),
          ),
    };
    _rows = List.unmodifiable(_tasks.values);
    _notify();
  }
}
