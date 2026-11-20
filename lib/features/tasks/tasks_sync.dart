part of 'tasks_store.dart';

// Allow large accounts more time between complete passes over their lists.
Duration _pullInterval(int lists) => Duration(seconds: max(120, lists * 5));
Duration _fullInterval(int lists) =>
    Duration(seconds: max(1800, _pullInterval(lists).inSeconds * 6));

const _overlap = Duration(minutes: 2);
const _retryLimit = Duration(minutes: 3);

extension _TasksSync on TasksStore {
  Future<void> _accountChanged() {
    _readAccount = true;
    _accountSignal = true;
    _retryAt = null;
    return _run();
  }

  Future<void> _run() {
    if (_disposed || !_started || _disconnecting) return Future.value();
    if (_running case final current?) return current;
    if (_retryAt case final time? when time.isAfter(DateTime.now().toUtc())) {
      _schedule();
      return Future.value();
    }
    final run = Future<void>.microtask(_work);
    _running = run;
    _notify();
    return run;
  }

  Future<void> _work() async {
    try {
      while (!_disposed && !_disconnecting) {
        if (_readAccount) {
          _readAccount = false;
          _accountSignal = false;
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
        if (data.queueReadable &&
            data.edits.any((edit) => edit.phase == .sending)) {
          data.saveEdits(
            data.edits.map((edit) => edit.afterInterruption()).toList(),
            data.drafts,
          );
          _publish();
        }
        if (_nextEdit(data) case final edit? when data.queueReadable) {
          await _send(data, edit);
          continue;
        }
        final now = DateTime.now().toUtc();
        final due =
            _automatic && (_nextPull == null || !_nextPull!.isAfter(now));
        if (!due && !_pull && data.cache.checkpoint != null) return;
        final full =
            _full ||
            data.fullRequired ||
            data.cache.lastFull == null ||
            now.difference(data.cache.lastFull!) >=
                _fullInterval(data.cache.lists.length);
        _pull = false;
        _full = false;
        try {
          await _pullTasks(data, full: full);
        } on Object {
          _pull = true;
          _full |= full;
          rethrow;
        }
        data.fullRequired = false;
        _nextPull = _automatic
            ? DateTime.now().toUtc().add(_pullInterval(data.cache.lists.length))
            : null;
        _clearBackoff();
        _publish();
      }
    } on Object catch (error) {
      _handleFailure(error);
    } finally {
      _running = null;
      _notify();
      if (_accountSignal && _problem == .authRequired) {
        unawaited(_run());
      } else {
        _schedule();
      }
    }
  }

  Future<void> _readStatus() async {
    final status = await _client.googleAccountStatus();
    final subject = status.accountId;
    final same = _data?.id == subject;
    final hadGrant = _account?.tasks == true;
    final reconnect = _problem == .authRequired || _account?.pending == true;
    _account = status;
    if (!same) {
      _data = null;
      _aliases.clear();
      _publish();
      if (subject != null) {
        final data = _TaskAccount(subject, _root ?? _taskStateRoot());
        await data.read();
        _data = data;
      }
    }
    if (status.tasks && (!same || !hadGrant || reconnect)) {
      _pull |= reconnect || _automatic || _data?.cache.checkpoint == null;
    }
    _clearBackoff();
    _publish();
  }

  void _schedule() {
    _timer?.cancel();
    if (_disposed || !_started || _disconnecting) return;
    if (!_readAccount &&
        (_problem == .authRequired || _account?.pending == true)) {
      return;
    }
    final time = _retryAt ?? (_automatic ? _nextPull : null);
    if (time == null) return;
    final delay = time.difference(DateTime.now().toUtc());
    _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      unawaited(_run());
    });
  }

  void _clearBackoff() {
    _retryAt = null;
    _failures = 0;
    final queueError = _data?.queueReadable == false;
    if (queueError) {
      _setProblem(.error, 'Saved Tasks changes could not be loaded.');
    } else if (_problem != null) {
      _setProblem(null, null);
    }
  }

  void _handleFailure(Object error) {
    final code = error is GoogleTasksException ? error.code : null;
    if (code == 'auth') {
      _readAccount = _accountSignal;
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
      seconds: min(5 * (1 << min(_failures++, 6)), _retryLimit.inSeconds),
    );
    _retryAt = DateTime.now().toUtc().add(delay);
    _setProblem(
      offline ? .offline : .error,
      offline
          ? 'Offline'
          : storage
          ? 'Could not save Tasks data on this device.'
          : 'Couldn’t sync. Saved changes stay on this device.',
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

  static const _showAll = {
    'showCompleted': true,
    'showDeleted': true,
    'showHidden': true,
    'showAssigned': true,
  };

  Future<Map<String, _Json>> _listTasks(
    _TaskAccount data,
    String listId, {
    DateTime? updatedMin,
  }) => _pages(data, 'tasks.list', {
    'listId': listId,
    ..._showAll,
    if (updatedMin != null) 'updatedMin': updatedMin.toIso8601String(),
  });

  Future<void> _pullTasks(_TaskAccount data, {required bool full}) async {
    final checkpoint = DateTime.now().toUtc();
    final prior = data.cache;
    final lists = await _pages(data, 'lists.list', {});
    final tasks = <_TaskKey, _Json>{
      if (!full)
        for (final entry in prior.tasks.entries)
          if (lists.containsKey(entry.key.$1)) entry.key: entry.value,
    };
    // Core accepts one Tasks request at a time, including each page.
    for (final listId in lists.keys) {
      final updatedMin = !full && prior.lists.containsKey(listId)
          ? prior.checkpoint?.subtract(_overlap)
          : null;
      final page = await _listTasks(data, listId, updatedMin: updatedMin);
      for (final entry in page.entries) {
        tasks[(listId, entry.key)] = {...entry.value, 'listId': listId};
      }
    }
    String? defaultListId = prior.defaultListId;
    if (full || defaultListId == null || !lists.containsKey(defaultListId)) {
      final result = await _get(data, 'lists.get', {'listId': '@default'});
      defaultListId = result == null ? null : _id(result);
    }
    await data.saveCache(
      _TaskCache(
        lists: lists,
        tasks: tasks,
        defaultListId: defaultListId,
        lastSync: DateTime.now().toUtc(),
        checkpoint: checkpoint,
        lastFull: full ? checkpoint : prior.lastFull,
      ),
    );
  }

  Future<_Json?> _get(_TaskAccount data, String operation, _Json args) async {
    try {
      final value = await _call(data, operation, args);
      return value['deleted'] == true ? null : value;
    } on GoogleTasksException catch (error) {
      if (error.code == 'missing') return null;
      rethrow;
    }
  }

  _TaskEdit? _nextEdit(_TaskAccount data) {
    final blocked = <_TaskEdit>[];
    for (final edit in data.edits) {
      if (edit.phase == .queued &&
          !blocked.any((previous) => _ordersAfter(edit, previous))) {
        return edit;
      }
      blocked.add(edit);
    }
    return null;
  }

  bool _dependsOnInsertion(_TaskEdit edit, _TaskEdit before) {
    if (!before.inserts) return false;
    if (before.op == 'lists.insert') {
      return edit.affectedLists.contains(before.id);
    }
    return edit.affectedLists.contains(before.listId) &&
        [
          'taskId',
          'parent',
          'previous',
        ].any((field) => edit.args[field] == before.id);
  }

  bool _ordersAfter(_TaskEdit edit, _TaskEdit before) {
    if (_dependsOnInsertion(edit, before)) return true;
    if (edit.taskKey != null && edit.taskKey == before.taskKey) return true;
    if (before.op == 'tasks.move' &&
        edit.taskKey == (before.args['destinationTasklist'], before.taskId)) {
      return true;
    }
    if ((edit.bulk ||
            before.bulk ||
            (edit.taskKey == null && before.taskKey == null)) &&
        edit.affectedLists.any(before.affectedLists.contains)) {
      return true;
    }
    return false;
  }

  Future<void> _send(_TaskAccount data, _TaskEdit edit) async {
    final listId = edit.listId;
    final taskId = edit.taskId;
    final reads = edit.base.isNotEmpty;
    final args = {'listId': ?listId, 'taskId': ?taskId};
    var payload = edit.args;
    _Json? fresh;
    if (reads) {
      fresh = await _get(
        data,
        taskId == null ? 'lists.get' : 'tasks.get',
        args,
      );
      if (!data.edits.contains(edit) || _disconnecting || _readAccount) return;
      if (fresh == null && !edit.op.endsWith('.delete')) {
        await _rememberRemote(data, edit, null);
        _replaceEdit(
          data,
          edit,
          edit.change(
            .conflict,
            message: 'This item was deleted in Google Tasks.',
            conflicting: edit.body.keys.toList(),
          ),
        );
        return;
      }
      if (fresh != null) {
        final body = edit.body;
        final fields = body.keys.where((field) {
          final remote = _field(fresh!, field);
          return remote != _field(edit.base, field) &&
              remote != _field(body, field);
        }).toList();
        final moved =
            edit.op == 'tasks.move' &&
            (fresh['parent'] != edit.base['parent'] ||
                (fresh['position'] ?? '') != edit.base['position']);
        final changedForDelete =
            edit.op.endsWith('.delete') && fresh['etag'] != edit.base['etag'];
        if (moved || changedForDelete || fields.isNotEmpty) {
          await _rememberRemote(data, edit, fresh);
          _replaceEdit(
            data,
            edit,
            edit.change(
              .conflict,
              message: 'This item changed elsewhere.',
              remote: fresh,
              conflicting: fields,
            ),
          );
          return;
        }
        if (body.isNotEmpty) {
          payload = {
            ...payload,
            'body': {
              for (final entry in body.entries)
                if (_field(fresh, entry.key) != _field(body, entry.key))
                  entry.key: entry.value,
            },
          };
        }
      }
    }
    if (_disconnecting || _readAccount || !data.edits.contains(edit)) return;

    final noWriteNeeded =
        reads && fresh == null ||
        (edit.body.isNotEmpty && (payload['body'] as _Json).isEmpty);
    final inFlight = edit.change(.sending);
    _replaceEdit(data, edit, inFlight);
    var sent = false;
    try {
      final result = noWriteNeeded
          ? fresh ?? <String, dynamic>{}
          : await _call(data, edit.op, payload);
      sent = true;
      await _accept(data, inFlight, result);
      _clearBackoff();
    } on Object catch (error) {
      debugPrint('Tasks sync ${edit.op} failed: $error');
      if (!data.edits.contains(inFlight)) rethrow;
      final code = error is GoogleTasksException ? error.code : null;
      if (_requiresExplicitRetry(edit.op) &&
          (sent ||
              code == 'ambiguous' ||
              error is TimeoutException ||
              code == null && !noWriteNeeded)) {
        _replaceEdit(
          data,
          inFlight,
          inFlight.change(.ambiguous, message: _uncertainMessage),
        );
        _pull = true;
      } else if (code == 'auth' ||
          code == 'offline' ||
          code == 'retry' ||
          code == 'unavailable' ||
          sent ||
          error is TimeoutException ||
          error is FileSystemException) {
        _replaceEdit(data, inFlight, inFlight.change(.queued));
        rethrow;
      } else {
        _replaceEdit(
          data,
          inFlight,
          inFlight.change(
            .failed,
            message: error is GoogleTasksException
                ? error.message
                : 'Couldn’t sync this change.',
          ),
        );
      }
    }
  }

  void _replaceEdit(_TaskAccount data, _TaskEdit old, _TaskEdit next) {
    data.saveEdits([
      for (final edit in data.edits) identical(edit, old) ? next : edit,
    ], data.drafts);
    if (next.phase != .sending) _publish();
  }

  Future<void> _rememberRemote(
    _TaskAccount data,
    _TaskEdit edit,
    _Json? fresh,
  ) async {
    final prior = data.cache;
    if (edit.taskKey case final taskKey?) {
      final tasks = Map<_TaskKey, _Json>.of(prior.tasks);
      if (fresh == null) {
        tasks.remove(taskKey);
      } else {
        tasks[taskKey] = {...fresh, 'listId': taskKey.$1};
      }
      await data.saveCache(_updatedCache(prior, tasks: tasks));
    } else if (fresh != null) {
      await data.saveCache(
        _updatedCache(prior, lists: {...prior.lists, edit.listId!: fresh}),
      );
    }
  }

  Future<void> _accept(_TaskAccount data, _TaskEdit edit, _Json result) async {
    final prior = data.cache;
    final listId = edit.listId;
    final destination = edit.args['destinationTasklist'] as String? ?? listId;
    final lists = Map<String, _Json>.of(prior.lists);
    final tasks = Map<_TaskKey, _Json>.of(prior.tasks);
    String? realId;
    final taskKey = edit.taskKey;
    switch (edit.op) {
      case 'lists.insert' || 'lists.patch':
        realId = _id(result);
        lists[realId] = await _readBack(data, 'lists.get', {
          'listId': realId,
        }, result);
      case 'lists.delete':
        lists.remove(listId);
        tasks.removeWhere((key, _) => key.$1 == listId);
      case 'tasks.insert' || 'tasks.patch' || 'tasks.move':
        realId = _id(result);
        final confirmed = await _readBack(data, 'tasks.get', {
          'listId': destination,
          'taskId': realId,
        }, result);
        tasks.remove(taskKey);
        tasks[(destination!, realId)] = {...confirmed, 'listId': destination};
      case 'tasks.delete':
        tasks.remove(taskKey);
        if (edit.taskId case final id? when listId != null) {
          try {
            final current = await _get(data, 'tasks.get', {
              'listId': listId,
              'taskId': id,
            });
            if (current != null) {
              tasks[(listId, id)] = {...current, 'listId': listId};
            }
          } on Object {
            data.fullRequired = true;
          }
        }
    }

    // A list pull reads actual server side effects of moves, clear and deletes.
    final changesParent =
        (edit.op == 'tasks.delete' || edit.body.containsKey('status')) &&
        prior.tasks.entries.any(
          (entry) =>
              entry.key.$1 == listId &&
              entry.value['parent'] == edit.taskId &&
              entry.value['deleted'] != true,
        );
    if (edit.op == 'tasks.move' || edit.op == 'tasks.clear' || changesParent) {
      for (final id in edit.affectedLists.toSet()) {
        try {
          final remote = await _listTasks(data, id);
          tasks.removeWhere((key, _) => key.$1 == id);
          for (final entry in remote.entries) {
            tasks[(id, entry.key)] = {...entry.value, 'listId': id};
          }
        } on Object {
          data.fullRequired = true;
        }
      }
    }

    await data.saveCache(
      _updatedCache(
        prior,
        lists: lists,
        tasks: tasks,
        lastSync: DateTime.now().toUtc(),
      ),
    );
    final newKey = taskKey == null || realId == null || destination == null
        ? null
        : (destination, realId);
    final rekeyed = newKey != null && newKey != taskKey;
    final drafts = Map<_TaskKey, _TaskDraft>.of(data.drafts);
    if ((rekeyed ? drafts.remove(taskKey) : null) case final draft?) {
      drafts[newKey!] = _TaskDraft({
        ...draft.base,
        'listId': destination,
        'id': realId,
      }, draft.body);
    }
    data.saveEdits([
      for (final queued in data.edits)
        if (queued != edit)
          _remap(queued, edit, realId: realId, destination: destination),
    ], drafts);
    if (rekeyed) {
      final alias = newKey;
      // Moving a task back to an earlier list must not make an alias cycle.
      _aliases.remove(alias);
      _aliases.updateAll((_, key) => key == taskKey ? alias : key);
      _aliases[taskKey!] = alias;
    }
    _publish();
  }

  Future<_Json> _readBack(
    _TaskAccount data,
    String operation,
    _Json args,
    _Json response,
  ) async {
    try {
      return await _get(data, operation, args) ??
          {...response, 'deleted': true};
    } on Object {
      data.fullRequired = true;
      return response;
    }
  }

  _TaskEdit _remap(
    _TaskEdit queued,
    _TaskEdit sent, {
    required String? realId,
    required String? destination,
  }) {
    if (realId == null) return queued;
    final args = Map<String, dynamic>.of(queued.args);
    final base = Map<String, dynamic>.of(queued.base);
    if (sent.op == 'lists.insert') {
      for (final field in ['listId', 'destinationTasklist']) {
        if (args[field] == sent.id) args[field] = realId;
      }
      if (base['listId'] == sent.id) base['listId'] = realId;
      if (base['id'] == sent.id && queued.taskKey == null) base['id'] = realId;
    } else if (sent.taskKey case (final listId, final oldId)) {
      if (queued.taskKey == sent.taskKey ||
          (sent.op == 'tasks.move' && queued.taskKey == (destination, oldId))) {
        args['listId'] = destination;
        args['taskId'] = realId;
        base['listId'] = destination;
        base['id'] = realId;
      }
      if (queued.affectedLists.contains(listId) && listId == destination) {
        for (final field in ['parent', 'previous']) {
          if (args[field] == oldId) args[field] = realId;
        }
        if (base['parent'] == oldId) base['parent'] = realId;
      }
    }
    return queued.change(
      queued.phase,
      args: args,
      base: base,
      remote: queued.remote,
      message: queued.message,
      conflicting: queued.conflicting,
    );
  }

  void _publish() {
    final data = _data;
    if (data == null) {
      _lists = const [];
      _tasks = const [];
      _visible = const {};
      _notify();
      return;
    }
    final lists = Map<String, _Json>.of(data.cache.lists);
    final tasks = Map<_TaskKey, _Json>.of(data.cache.tasks);
    final pending = <_TaskKey>{};
    final errors = <_TaskKey, String>{};

    for (final edit in data.edits) {
      final listId = edit.listId;
      final key = edit.taskKey;
      final rolledBack = edit.phase == .failed || edit.phase == .ambiguous;
      if (key != null) {
        pending.add(key);
        if (edit.message case final message?) errors[key] = message;
      }
      switch (edit.op) {
        case 'lists.insert':
          if (!rolledBack) lists[edit.id] = {'id': edit.id, ...edit.body};
        case 'lists.patch':
          if (lists[listId] case final list? when !rolledBack) {
            lists[listId!] = {...list, ...edit.body};
          }
        case 'lists.delete':
          if (!rolledBack && edit.phase != .conflict) {
            lists.remove(listId);
          }
        case 'tasks.insert':
          tasks[key!] = {
            'id': key.$2,
            'listId': key.$1,
            'parent': edit.args['parent'],
            'position': _position(tasks, key.$1, edit.args['previous']),
            ...edit.body,
          };
        case 'tasks.patch':
          if (tasks[key] case final task?) {
            tasks[key!] = {...task, ...edit.body};
          }
        case 'tasks.move':
          if (tasks[key] case final task?
              when !rolledBack && edit.phase != .conflict) {
            final id = edit.args['destinationTasklist'] as String? ?? key!.$1;
            final moved = (id, key!.$2);
            tasks.remove(key);
            tasks[moved] = {
              ...task,
              'listId': id,
              'parent': edit.args['parent'],
              'position': _position(tasks, id, edit.args['previous']),
            };
            pending.add(moved);
          }
        case 'tasks.delete':
          if (!rolledBack && edit.phase != .conflict) tasks.remove(key);
        case 'tasks.clear':
          if (!rolledBack) {
            tasks.updateAll(
              (taskKey, task) =>
                  taskKey.$1 == listId && task['status'] == 'completed'
                  ? {...task, 'hidden': true}
                  : task,
            );
          }
      }
    }
    _lists = List.unmodifiable([
      for (final entry in lists.entries)
        if (entry.value['deleted'] != true)
          TaskList(
            id: entry.key,
            title: (entry.value['title'] as String?) ?? '',
            etag: entry.value['etag'] as String?,
            accountId: data.id,
            pending: !data.cache.lists.containsKey(entry.key),
          ),
    ]);
    final visible = <_TaskKey, GoogleTask>{
      for (final entry in tasks.entries)
        if (lists.containsKey(entry.key.$1) && entry.value['deleted'] != true)
          entry.key: _model(
            entry.value,
            pending: pending.contains(entry.key),
            accountId: data.id,
            error: errors[entry.key],
          ),
    };
    _visible = visible;
    _tasks = List.unmodifiable(visible.values);
    _notify();
  }

  String _position(
    Map<_TaskKey, _Json> tasks,
    String listId,
    Object? previous,
  ) {
    if (previous is! String) return '';
    return '${tasks[(listId, previous)]?['position'] ?? ''}0';
  }
}

_TaskCache _updatedCache(
  _TaskCache prior, {
  Map<String, _Json>? lists,
  Map<_TaskKey, _Json>? tasks,
  DateTime? lastSync,
}) => _TaskCache(
  lists: lists ?? prior.lists,
  tasks: tasks ?? prior.tasks,
  lastSync: lastSync ?? prior.lastSync,
  checkpoint: prior.checkpoint,
  lastFull: prior.lastFull,
  defaultListId: prior.defaultListId,
);
