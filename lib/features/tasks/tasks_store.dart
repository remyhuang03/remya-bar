import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:remya_client/remya_client.dart';

import 'tasks_models.dart';

export 'tasks_models.dart';

part 'tasks_storage.dart';
part 'tasks_sync.dart';

/// Shared by every Tasks placement in the GTK app's Flutter isolate.
class TasksStore extends ChangeNotifier {
  TasksStore({SettingsClient? client, Directory? stateDirectory})
    : _client = client ?? SettingsClient(),
      _ownsClient = client == null,
      _root = stateDirectory;

  static final shared = TasksStore();

  final SettingsClient _client;
  final bool _ownsClient;
  final Directory? _root;
  final _random = Random.secure();
  StreamSubscription<SettingsChange>? _changes;
  StreamSubscription<bool>? _serviceChanges;
  Timer? _timer;
  Future<void>? _running;
  bool _started = false;
  bool _disposed = false;
  bool _automatic = true;
  bool _readAccount = false;
  bool _accountSignal = false;
  bool _pull = false;
  bool _full = false;
  bool _disconnecting = false;
  bool _connecting = false;
  DateTime? _nextPull;
  DateTime? _retryAt;
  int _failures = 0;
  GoogleAccountStatus? _account;
  _TaskAccount? _data;
  TasksSyncState? _problem;
  String? _error;

  final _aliases = <_TaskKey, _TaskKey>{};
  List<TaskList> _lists = const [];
  List<GoogleTask> _tasks = const [];
  Map<_TaskKey, GoogleTask> _visible = const {};

  GoogleAccountStatus? get account => _account;
  String? get defaultListId => _data?.cache.defaultListId;
  DateTime? get lastSync => _data?.cache.lastSync?.toLocal();
  int get pendingCount => _data?.edits.length ?? 0;
  int get draftCount => _data?.drafts.length ?? 0;
  List<TaskList> get lists => _lists;
  List<GoogleTask> get tasks => _tasks;
  String? get error => _error;

  TasksSyncState get state {
    if (_problem case final problem?) return problem;
    if (_data == null || _account?.tasks != true) {
      if (_account == null || _connecting || _account?.pending == true) {
        return .loading;
      }
      return _data?.cache.lastSync == null ? .disconnected : .authRequired;
    }
    if (_data?.loaded != true || (_running != null && lastSync == null)) {
      return .loading;
    }
    if (_data!.edits.any((edit) => edit.phase == .conflict)) return .conflict;
    if (_data!.edits.any(
      (edit) => edit.phase == .failed || edit.phase == .ambiguous,
    )) {
      return .error;
    }
    return _running == null ? .ready : .syncing;
  }

  List<TasksConflict> get conflicts => [
    for (final edit in _data?.edits ?? const <_TaskEdit>[])
      if (edit.phase == .conflict)
        TasksConflict(
          id: edit.id,
          title: edit.title,
          task: _editTaskModel(edit),
          message: edit.message!,
          canKeepMine: edit.remote != null,
          fields: [
            for (final field in edit.conflicting)
              TasksConflictField(
                field,
                _field(edit.body, field),
                edit.remote == null ? null : _field(edit.remote!, field),
              ),
          ],
        ),
  ];

  List<TasksIssue> get issues => [
    for (final edit in _data?.edits ?? const <_TaskEdit>[])
      if (edit.phase == .failed || edit.phase == .ambiguous)
        TasksIssue(
          id: edit.id,
          operation: edit.op,
          title: edit.title,
          message: edit.message!,
          ambiguous: edit.phase == .ambiguous,
          task: _editTaskModel(edit),
        ),
  ];

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _changes = _client.changes.listen((change) {
      if (change.topic == googleAccountTopic) unawaited(_accountChanged());
    }, onError: (Object _) {});
    _serviceChanges = _client.serviceAvailableChanges.listen((available) {
      if (available) unawaited(_accountChanged());
    }, onError: (Object _) {});
    unawaited(_accountChanged());
  }

  void setAutomatic(bool value) {
    if (_automatic == value) return;
    _automatic = value;
    if (!_started) return;
    if (value) {
      _nextPull = DateTime.now().toUtc();
      unawaited(_run());
    } else {
      _nextPull = null;
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
    if (_connecting || _disconnecting) return;
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

  Future<void> disconnect() async {
    if (_disconnecting) return;
    _disconnecting = true;
    try {
      await _running;
      await _client.disconnectGoogleAccount();
    } finally {
      _disconnecting = false;
      await _accountChanged();
    }
  }

  Future<void> discardPendingChanges() async {
    final data = _editable();
    if (data.edits.any((edit) => edit.phase == .sending)) {
      throw const TasksEditException(
        'Wait for the current change to finish syncing.',
      );
    }
    data.saveEdits([], {});
    _publish();
  }

  Future<void> retry() {
    final data = _data;
    if (data != null && data.loaded) {
      data.saveEdits([
        for (final edit in data.edits)
          edit.phase == .failed ? edit.change(.queued) : edit,
      ], data.drafts);
    }
    _publish();
    return refresh();
  }

  /// An uncertain create is never retried. Discard it after checking Google.
  Future<void> discardIssue(TasksIssue issue) async {
    final data = _editable();
    final target = data.edits.where((edit) => edit.id == issue.id).firstOrNull;
    if (target == null ||
        (target.phase != .failed && target.phase != .ambiguous)) {
      return;
    }
    data.saveEdits([
      for (final edit in data.edits)
        if (edit != target)
          _dependsOnInsertion(edit, target)
              ? edit.change(
                  .failed,
                  message: 'The destination was never created in Google Tasks.',
                )
              : edit,
    ], data.drafts);
    _publish();
    unawaited(_run());
  }

  Future<void> resolveConflict(
    TasksConflict conflict, {
    required bool keepMine,
  }) async {
    final data = _editable();
    final edit = data.edits.where((edit) => edit.id == conflict.id).firstOrNull;
    if (edit == null || edit.phase != .conflict) return;
    if (keepMine && edit.remote == null) {
      throw const TasksEditException('This item was deleted in Google Tasks.');
    }
    final body = Map<String, dynamic>.of(edit.body);
    if (!keepMine) {
      body.removeWhere((field, _) => edit.conflicting.contains(field));
    }
    final keep = keepMine || (edit.remote != null && body.isNotEmpty);
    data.saveEdits([
      for (final queued in data.edits)
        if (queued != edit)
          queued
        else if (keep)
          edit.change(
            .queued,
            base: {
              ...edit.base,
              ...edit.remote!,
              for (final field in [
                'title',
                'notes',
                'due',
                'status',
                'parent',
                'position',
                'etag',
              ])
                field: edit.remote![field],
            },
            args: {...edit.args, if (edit.body.isNotEmpty) 'body': body},
          ),
    ], data.drafts);
    _publish();
    unawaited(_run());
  }

  GoogleTask? findTask(String listId, String taskId) {
    final key = (listId, taskId);
    return _visible[_aliases[key] ?? key];
  }

  Map<String, Object?>? draftFor(GoogleTask base) {
    if (base.accountId != _data?.id) return null;
    final draft = _data?.drafts[(base.listId, base.id)];
    if (draft == null) return null;
    return {
      if (draft.body.containsKey('title')) 'title': draft.body['title'],
      if (draft.body.containsKey('notes')) 'notes': draft.body['notes'],
      if (draft.body.containsKey('due'))
        'scheduled': googleScheduledDate(draft.body['due']),
      if (draft.body.containsKey('status'))
        'completed': draft.body['status'] == 'completed',
    };
  }

  GoogleTask? draftBaseFor(GoogleTask task) {
    if (task.accountId != _data?.id) return null;
    final draft = _data?.drafts[(task.listId, task.id)];
    if (draft == null) return null;
    return _model({
      ...?_data?.cache.tasks[(task.listId, task.id)],
      ...draft.base,
    }, accountId: task.accountId);
  }

  void saveDraft(GoogleTask base, Map<String, Object?> changes) {
    final data = _editable();
    _requireAccount(base.accountId);
    final next = Map<_TaskKey, _TaskDraft>.of(data.drafts);
    final key = (base.listId, base.id);
    if (changes.isEmpty) {
      next.remove(key);
    } else {
      next[key] = _TaskDraft(_baseline(base), _patch(changes, draft: true));
    }
    data.saveEdits(data.edits, next);
    _notify();
  }

  void discardDraft(GoogleTask base) {
    final data = _editable();
    _requireAccount(base.accountId);
    final next = Map<_TaskKey, _TaskDraft>.of(data.drafts)
      ..remove((base.listId, base.id));
    data.saveEdits(data.edits, next);
    _notify();
  }

  Future<GoogleTask> addTask(
    String listId,
    String title, {
    String? parent,
    String? previous,
    DateTime? scheduled,
  }) async {
    _requireList(listId);
    if (parent != null || previous != null) {
      _requirePosition(listId, parent, previous);
    }
    final id = _newId();
    _stage(
      _TaskEdit(id, 'tasks.insert', {
        'listId': listId,
        'parent': ?parent,
        'previous': ?previous,
        'body': {
          'title': _title(title, 1024),
          if (scheduled != null) 'due': googleScheduledDatePayload(scheduled),
        },
      }, {}),
    );
    return _visible[(listId, id)]!;
  }

  Future<void> editTask(
    GoogleTask base,
    Map<String, Object?> changes, {
    bool clearDraft = false,
  }) async {
    final current = _requireTask(base);
    if (current.sourceKind == 'DOCUMENT' && changes.containsKey('notes')) {
      throw const TasksEditException('Edit notes in the assigned Google Doc.');
    }
    final body = _patch(changes);
    final original = _baseline(base);
    body.removeWhere(
      (field, _) => _field(original, field) == _field(body, field),
    );
    if (body.isEmpty) {
      if (clearDraft) discardDraft(base);
      return;
    }
    _stage(
      _TaskEdit(_newId(), 'tasks.patch', {
        'listId': base.listId,
        'taskId': base.id,
        'body': body,
      }, original),
      clearDraft: clearDraft ? (base.listId, base.id) : null,
    );
  }

  Future<void> deleteTask(GoogleTask base) async {
    _requireTask(base);
    _stage(
      _TaskEdit(_newId(), 'tasks.delete', {
        'listId': base.listId,
        'taskId': base.id,
      }, _baseline(base)),
    );
  }

  Future<void> moveTask(
    GoogleTask base, {
    String? destinationListId,
    String? parent,
    String? previous,
  }) async {
    final task = _requireTask(base);
    final destination = destinationListId ?? base.listId;
    _requireList(destination);
    if (task.hidden && (parent != null || previous != null)) {
      throw const TasksEditException(
        'Hidden tasks can only move to the top of a list.',
      );
    }
    if (task.assigned && parent != null) {
      throw const TasksEditException('Assigned tasks cannot become subtasks.');
    }
    if (task.id == previous) {
      throw const TasksEditException(
        'Choose another task as the previous task.',
      );
    }
    _requirePosition(destination, parent, previous, moving: task);
    _stage(
      _TaskEdit(_newId(), 'tasks.move', {
        'listId': base.listId,
        'taskId': task.id,
        if (destination != base.listId) 'destinationTasklist': destination,
        'parent': ?parent,
        'previous': ?previous,
      }, _baseline(base)),
    );
  }

  Future<void> createList(String title) async {
    _stage(
      _TaskEdit(_newId(), 'lists.insert', {
        'body': {'title': _title(title, 1024)},
      }, {}),
    );
  }

  Future<void> renameList(TaskList base, String title) async {
    _requireAccount(base.accountId);
    _requireList(base.id);
    final name = _title(title, 1024);
    if (name == base.title) return;
    _stage(
      _TaskEdit(_newId(), 'lists.patch', {
        'listId': base.id,
        'body': {'title': name},
      }, _listBaseline(base)),
    );
  }

  Future<void> deleteList(TaskList base) async {
    _requireAccount(base.accountId);
    _requireList(base.id);
    _stage(
      _TaskEdit(_newId(), 'lists.delete', {
        'listId': base.id,
      }, _listBaseline(base)),
    );
  }

  Future<void> hideCompleted(String listId) async {
    _requireList(listId);
    _stage(_TaskEdit(_newId(), 'tasks.clear', {'listId': listId}, {}));
  }

  GoogleTask? _editTaskModel(_TaskEdit edit) {
    if (edit.taskKey case (final listId, final taskId)) {
      return findTask(listId, taskId) ??
          (edit.base.isEmpty
              ? null
              : _model(edit.base, error: edit.message, accountId: _data?.id));
    }
    return null;
  }

  _TaskAccount _editable() {
    final data = _data;
    if (_disconnecting || data == null || !data.loaded) {
      throw const TasksEditException('Connect Google Tasks to save changes.');
    }
    return data;
  }

  void _stage(_TaskEdit edit, {_TaskKey? clearDraft}) {
    final data = _editable();
    final drafts = Map<_TaskKey, _TaskDraft>.of(data.drafts)
      ..remove(clearDraft);
    data.saveEdits([...data.edits, edit], drafts);
    _publish();
    unawaited(_run());
  }

  String _newId() =>
      'local-${base64Url.encode(List<int>.generate(18, (_) => _random.nextInt(256)))}';

  void _requireList(String id) {
    if (!_lists.any((list) => list.id == id)) {
      throw const TasksEditException('Choose an available Google Tasks list.');
    }
  }

  void _requireAccount(String? accountId) {
    if (accountId == null || accountId != _data?.id) {
      throw const TasksEditException(
        'This item belongs to a different Google account.',
      );
    }
  }

  GoogleTask _requireTask(GoogleTask task) {
    _requireAccount(task.accountId);
    final current = _visible[(task.listId, task.id)];
    if (current == null || current.deleted) {
      throw const TasksEditException('This task is no longer available.');
    }
    return current;
  }

  void _requirePosition(
    String listId,
    String? parent,
    String? previous, {
    GoogleTask? moving,
  }) {
    if (previous != null) {
      final sibling = _visible[(listId, previous)];
      if (sibling == null ||
          sibling.hidden ||
          sibling.deleted ||
          sibling.parent != parent) {
        throw const TasksEditException('Choose a visible sibling task.');
      }
    }
    final seen = <String>{
      if (moving != null && moving.listId == listId) moving.id,
    };
    var ancestor = parent;
    while (ancestor != null) {
      final task = _visible[(listId, ancestor)];
      if (task == null ||
          task.deleted ||
          task.hidden ||
          task.assigned ||
          !seen.add(ancestor)) {
        throw const TasksEditException(
          'Choose a visible task that can have subtasks.',
        );
      }
      ancestor = task.parent;
    }
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
    unawaited(_changes?.cancel());
    unawaited(_serviceChanges?.cancel());
    if (_ownsClient) unawaited(_client.close());
    super.dispose();
  }
}

String _title(String title, int max) {
  final value = title.trim();
  if (value.isEmpty || value.runes.length > max) {
    throw TasksEditException('Enter a title between 1 and $max characters.');
  }
  return value;
}

_Json _patch(Map<String, Object?> changes, {bool draft = false}) {
  final body = <String, dynamic>{};
  for (final MapEntry(:key, :value) in changes.entries) {
    switch ((key, value)) {
      case ('title', final String title):
        body['title'] = draft ? title : _title(title, 1024);
      case ('notes', final String notes):
        if (!draft && notes.runes.length > 8192) {
          throw const TasksEditException(
            'Notes can contain up to 8192 characters.',
          );
        }
        body['notes'] = notes;
      case ('scheduled', final DateTime date):
        body['due'] = googleScheduledDatePayload(date);
      case ('scheduled', null):
        body['due'] = null;
      case ('completed', final bool completed):
        body['status'] = completed ? 'completed' : 'needsAction';
      default:
        throw const TasksEditException('This field cannot be edited in Remya.');
    }
  }
  return body;
}
