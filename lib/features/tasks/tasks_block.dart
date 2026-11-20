import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import 'tasks_preferences.dart';
import 'tasks_store.dart';

part 'tasks_dialogs.dart';
part 'tasks_rows.dart';

/// A task list without an outer surface, shared by both popup hosts.
class TasksBlock extends StatefulWidget {
  const TasksBlock({
    super.key,
    required this.store,
    required this.preferences,
    required this.onSettings,
    required this.onSetDefaultList,
    this.compact = true,
    this.initialView,
    this.initialList,
  });

  final TasksStore store;
  final TasksPreferences preferences;
  final VoidCallback onSettings;
  final Future<void> Function(String) onSetDefaultList;
  final bool compact;
  final String? initialView;
  final String? initialList;

  @override
  State<TasksBlock> createState() => _TasksBlockState();
}

enum _View {
  today('Today'),
  upcoming('Upcoming'),
  all('All');

  const _View(this.label);
  final String label;
}

enum _Group {
  earlier('Earlier'),
  today('Today'),
  upcoming('Upcoming'),
  unscheduled('Unscheduled');

  const _Group(this.label);
  final String label;
}

typedef _TaskKey = ({String list, String task});

_TaskKey _key(GoogleTask task) => (list: task.listId, task: task.id);

class _TasksBlockState extends State<TasksBlock> {
  final _quickAdd = TextEditingController();
  final _quickFocus = FocusNode();
  final _search = TextEditingController();
  final _opened = <_TaskKey>{};
  late final _viewPreferences = ValueNotifier(_preferences);
  late _View _view;
  late bool _showCompleted;
  bool? _sortByDate;
  String? _listId;
  String? _accountId;
  GoogleTask? _recent;
  GoogleTask? _undo;
  String? _error;
  Timer? _noticeTimer;
  bool _adding = false;
  bool _connecting = false;
  bool _showHidden = false;

  TasksStore get _store => widget.store;
  TasksPreferences get _preferences => widget.preferences;
  List<TaskList> get _visibleLists => _store.lists
      .where(
        (list) =>
            _preferences.visibleLists.isEmpty ||
            _preferences.visibleLists.contains(list.id),
      )
      .toList();

  TaskList? get _destination {
    final account = _store.account?.accountId;
    final saved = _preferences.defaultListAccount == account
        ? _preferences.defaultList
        : '@default';
    final id = saved == '@default' ? _store.defaultListId : saved;
    return _store.lists.where((list) => list.id == id).firstOrNull;
  }

  bool get _manualOrder =>
      _listId != null && !(_sortByDate ?? (_preferences.sort == 'date'));

  @override
  void initState() {
    super.initState();
    _view = _View.values.byName(widget.initialView ?? _preferences.initialView);
    _showCompleted = _preferences.completedExpanded;
    _listId = widget.initialList;
    _accountId = _store.account?.accountId;
    _store.addListener(_onStoreChange);
  }

  @override
  void didUpdateWidget(TasksBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != _store) {
      oldWidget.store.removeListener(_onStoreChange);
      _store.addListener(_onStoreChange);
      _onStoreChange();
    }
    if (!_visibleLists.any((list) => list.id == _listId)) _listId = null;
    _viewPreferences.value = _preferences;
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChange);
    _viewPreferences.dispose();
    _noticeTimer?.cancel();
    _quickAdd.dispose();
    _quickFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onStoreChange() {
    setState(() {
      final account = _store.account?.accountId;
      if (account != _accountId) {
        _accountId = account;
        _listId = null;
        _showHidden = false;
        _noticeTimer?.cancel();
        _opened.clear();
        _quickAdd.clear();
        _search.clear();
        _undo = null;
        _recent = null;
        _error = null;
      }
      if (!_visibleLists.any((list) => list.id == _listId)) _listId = null;
    });
  }

  Future<bool> _run(Future<void> Function() action) async {
    final account = _accountId;
    try {
      await action();
      if (!mounted || account != _accountId) return false;
      if (_error != null) setState(() => _error = null);
      return true;
    } on Object catch (error) {
      if (mounted && account == _accountId) {
        setState(() => _error = _actionError(error));
      }
      return false;
    }
  }

  void _setNotice({GoogleTask? completed, GoogleTask? added}) {
    _noticeTimer?.cancel();
    setState(() {
      _undo = completed;
      _recent = added;
    });
    _noticeTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _undo = _recent = null);
    });
  }

  Future<void> _connect() async {
    setState(() => _connecting = true);
    await _run(_store.connect);
    if (mounted) setState(() => _connecting = false);
  }

  Future<void> _add() async {
    final list = _destination;
    final title = _quickAdd.text.trim();
    if (_adding || list == null || title.isEmpty) return;
    setState(() => _adding = true);
    try {
      GoogleTask? added;
      final saved = await _run(() async {
        added = await _store.addTask(list.id, title);
      });
      if (saved) {
        _quickAdd.clear();
        _quickFocus.requestFocus();
        _setNotice(added: added);
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _complete(GoogleTask task, bool completed) async {
    final account = _accountId;
    final attached = completed
        ? _store.tasks
              .where(
                (child) =>
                    child.listId == task.listId &&
                    child.parent == task.id &&
                    !child.deleted &&
                    !child.completed,
              )
              .length
        : 0;
    if (attached > 0) {
      final confirmed = await _confirm(
        context,
        title: 'Complete parent task?',
        message:
            '“${task.title}” has $attached incomplete ${attached == 1 ? 'subtask' : 'subtasks'}.',
        action: 'Complete task',
        destructive: false,
        store: _store,
      );
      if (!mounted || !confirmed || account != _accountId) return;
    }
    if (await _run(() => _store.editTask(task, {'completed': completed})) &&
        completed) {
      _setNotice(completed: task);
    }
  }

  Future<void> _undoCompletion() async {
    final previous = _undo;
    if (previous == null) return;
    final current = _store.findTask(previous.listId, previous.id);
    if (current == null || !current.completed) {
      _setNotice();
      return;
    }
    if (await _run(() => _store.editTask(current, {'completed': false}))) {
      _setNotice();
    }
  }

  Future<void> _selectList() async {
    final id = await _pick(
      context,
      title: 'Visible task list',
      store: _store,
      selected: _listId ?? '',
      choices: [
        (id: '', label: 'All lists'),
        for (final list in _visibleLists) (id: list.id, label: list.title),
      ],
    );
    if (id == null || !mounted) return;
    setState(() => _listId = id.isEmpty ? null : id);
  }

  Future<void> _selectDefaultList() async {
    final account = _accountId;
    final id = await _pick(
      context,
      title: 'Default list for new tasks',
      store: _store,
      selected: _destination?.id,
      choices: [
        for (final list in _store.lists)
          if (!list.pending) (id: list.id, label: list.title),
      ],
    );
    if (id != null &&
        mounted &&
        account == _accountId &&
        await _run(() => widget.onSetDefaultList(id))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _quickFocus.requestFocus();
      });
    }
  }

  Future<void> _viewAll({_View? view, String? list}) => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const .all(8),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(borderRadius: .all(.circular(32))),
      child: SizedBox(
        width: 420,
        child: Padding(
          padding: const .all(24),
          child: ValueListenableBuilder(
            valueListenable: _viewPreferences,
            builder: (_, preferences, _) => TasksBlock(
              store: _store,
              preferences: preferences,
              initialView: (view ?? _view).name,
              initialList: list ?? _listId,
              onSettings: widget.onSettings,
              onSetDefaultList: widget.onSetDefaultList,
              compact: false,
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _viewAdded() async {
    final recent = _recent;
    if (recent == null) return;
    final task = _store.findTask(recent.listId, recent.id);
    if (task == null) {
      await _viewAll(view: .all, list: recent.listId);
      return;
    }
    await _edit(task);
  }

  Future<void> _edit(GoogleTask task, {bool addSubtask = false}) =>
      showDialog<void>(
        context: context,
        builder: (_) =>
            _TaskEditor(store: _store, task: task, addSubtask: addSubtask),
      );

  Future<void> _manageLists() => showDialog<void>(
    context: context,
    builder: (_) => _ManageLists(
      store: _store,
      defaultList: () => _destination?.id,
      onSetDefaultList: widget.onSetDefaultList,
    ),
  );

  Future<void> _reviewChanges() => showDialog<void>(
    context: context,
    builder: (_) => _SyncIssues(store: _store),
  );

  Future<void> _bulkDelete(List<GoogleTask> tasks) async {
    final account = _accountId;
    final assigned = tasks.where((task) => task.assigned).length;
    final confirmed = await _confirm(
      context,
      title: 'Delete ${tasks.length} completed tasks?',
      message: [
        'Each task will be deleted separately. Failed deletions remain visible.',
        if (assigned > 0)
          '$assigned assigned tasks will also be deleted from their sources.',
      ].join(' '),
      action: 'Delete completed tasks',
      store: _store,
    );
    if (!confirmed || !mounted || account != _accountId) return;
    var failures = 0;
    final children = tasks.where((task) => task.parent != null);
    final parents = tasks.where((task) => task.parent == null);
    for (final task in [...children, ...parents]) {
      if (account != _accountId || !mounted) break;
      if (!await _run(() => _store.deleteTask(task))) failures++;
    }
    if (mounted && failures > 0 && account == _accountId) {
      setState(
        () =>
            _error = 'Could not queue $failures of ${tasks.length} deletions.',
      );
    }
  }

  Future<void> _rowAction(
    _TaskAction action,
    GoogleTask task,
    List<GoogleTask> children,
    List<GoogleTask> siblings,
  ) async {
    switch (action) {
      case .edit:
        await _edit(task);
      case .addChild:
        await _edit(task, addSubtask: true);
      case .move:
        await showDialog<bool>(
          context: context,
          builder: (_) => _MoveTask(store: _store, task: task),
        );
      case .moveOut:
        await _run(() => _store.moveTask(task));
      case .up:
      case .down:
        final index = siblings.indexWhere((other) => other.id == task.id);
        final target = action == .up ? index - 1 : index + 1;
        if (index != -1 && target >= 0 && target < siblings.length) {
          await _reorder(task, siblings[target], siblings);
        }
      case .delete:
        await _deleteTask(context, _store, task, children.length, _run);
      case .source:
        await _run(() => _openLink(task.sourceLink));
      case .external:
        await _run(() => _openGoogleTasks(task.webViewLink));
      case .issues:
        await _reviewChanges();
    }
  }

  Future<void> _reorder(
    GoogleTask task,
    GoogleTask target,
    List<GoogleTask> siblings,
  ) async {
    final from = siblings.indexWhere((row) => row.id == task.id);
    final to = siblings.indexWhere((row) => row.id == target.id);
    if (from < 0 || to < 0 || from == to) return;
    final next = [...siblings]..removeAt(from);
    final previous = to == 0 ? null : next[to - 1].id;
    await _run(
      () => _store.moveTask(task, parent: task.parent, previous: previous),
    );
  }

  bool _matchesDate(GoogleTask task, DateTime now) {
    final date = task.scheduled;
    return switch (_view) {
      .today =>
        date == null
            ? _preferences.todayIncludesUnscheduled
            : DateUtils.isSameDay(date, now),
      .upcoming => date != null && _group(date, now) == .upcoming,
      .all => true,
    };
  }

  bool _matchesSearch(GoogleTask task, String query) =>
      task.title.toLowerCase().contains(query) ||
      task.notes.toLowerCase().contains(query);

  _Group _group(DateTime? date, DateTime now) {
    if (date == null) return .unscheduled;
    final day = DateUtils.dateOnly(date);
    if (day == now) return .today;
    return day.isBefore(now) ? .earlier : .upcoming;
  }

  List<Object> _rows(
    List<GoogleTask> parents,
    Map<_TaskKey, List<GoogleTask>> children,
    DateTime now, {
    required bool groupByDate,
  }) {
    final rows = <Object>[];
    _Group? previous;
    for (final task in parents) {
      if (groupByDate) {
        final group = _group(task.scheduled, now);
        if (group != previous) rows.add(group);
        previous = group;
      }
      final remaining = [task];
      while (remaining.isNotEmpty) {
        final row = remaining.removeLast();
        rows.add(row);
        if (_opened.contains(_key(row))) {
          final subtasks = children[_key(row)];
          if (subtasks != null) remaining.addAll(subtasks.reversed);
        }
      }
    }
    return rows;
  }

  Widget _row(
    GoogleTask task,
    Map<_TaskKey, List<GoogleTask>> children,
    Map<_TaskKey, GoogleTask> active,
    Map<_TaskKey, List<GoogleTask>> siblingsByParent,
    Map<String, String> listNames,
    DateTime now,
  ) {
    final key = _key(task);
    final isChild = active.containsKey((
      list: task.listId,
      task: task.parent ?? '',
    ));
    final subtasks = children[key] ?? const <GoogleTask>[];
    final siblings =
        siblingsByParent[(list: task.listId, task: task.parent ?? '')] ??
        const <GoogleTask>[];
    final index = siblings.indexWhere((row) => row.id == task.id);
    final movable = _manualOrder && !task.pending && !task.hidden && index >= 0;
    return _TaskRow(
      key: ValueKey(key),
      task: task,
      childRow: isChild,
      dateLabel: task.scheduled == null
          ? null
          : _friendlyDate(context, task.scheduled!, now),
      listLabel: _listId == null ? listNames[task.listId] : null,
      children: subtasks,
      expanded: _opened.contains(key),
      onExpand: () => setState(() {
        if (!_opened.add(key)) _opened.remove(key);
      }),
      onOpen: () => _edit(task),
      onComplete: (value) => _complete(task, value),
      onAction: (action) => _rowAction(action, task, subtasks, siblings),
      moveEarlier: movable && index > 0,
      moveLater: movable && index + 1 < siblings.length,
      canDrag: movable,
      acceptsDrag: (key) {
        final other = active[key];
        return movable &&
            other != null &&
            other.listId == task.listId &&
            other.parent == task.parent &&
            other.id != task.id;
      },
      onDrop: (key) {
        final other = active[key];
        if (other != null) unawaited(_reorder(other, task, siblings));
      },
    );
  }

  Widget _connectionState() => switch (_store.state) {
    .disconnected => _TaskPrompt(
      icon: 'state-task',
      title: 'Connect Google Tasks',
      message:
          'Remya can view, edit and delete tasks with your Google account.',
      action: 'Connect Google Tasks',
      onPressed: _connecting ? null : _connect,
    ),
    .authRequired => _TaskPrompt(
      icon: 'state-offline',
      title: 'Reconnect to sync',
      message: _store.pendingCount > 0
          ? 'Your changes are saved on this device.'
          : 'Reconnect Google Tasks to get your lists.',
      action: 'Reconnect',
      onPressed: _connecting ? null : _connect,
    ),
    .error || .offline => _TaskPrompt(
      icon: 'state-error',
      title: 'Couldn’t sync your tasks',
      message: _store.error ?? 'Try again when you are ready.',
      action: 'Retry',
      onPressed: () => _run(_store.retry),
    ),
    _ => const _TaskPrompt(
      icon: 'state-sync',
      title: 'Getting your tasks',
      message: 'Loading your lists for the first time.',
      loading: true,
    ),
  };

  Widget? _syncBanner() {
    final pending = _store.pendingCount;
    final waiting =
        '$pending ${pending == 1 ? 'change' : 'changes'} waiting to sync';
    return switch (_store.state) {
      .offline => _TaskBanner(
        icon: 'offline',
        title: 'Offline',
        detail: waiting,
        action: 'Retry',
        onPressed: () => _run(_store.retry),
      ),
      .authRequired => _TaskBanner(
        icon: 'offline',
        title: 'Reconnect to sync',
        detail: pending > 0 ? waiting : null,
        action: 'Reconnect',
        onPressed: _connecting ? null : _connect,
      ),
      .error => _TaskBanner(
        title: 'Couldn’t sync',
        detail: pending > 0
            ? 'Your changes are saved on this device.'
            : _store.error,
        action: _store.issues.isEmpty ? 'Retry' : 'Review',
        onPressed: _store.issues.isEmpty
            ? () => _run(_store.retry)
            : _reviewChanges,
      ),
      .conflict => _TaskBanner(
        title: 'This task changed elsewhere.',
        action: 'Resolve',
        onPressed: _reviewChanges,
      ),
      _ => null,
    };
  }

  String _syncLabel(BuildContext context) {
    final last = _store.lastSync;
    if (_store.state == .syncing || _store.state == .loading) return 'Syncing…';
    if (last == null) return 'Waiting to sync';
    final local = MaterialLocalizations.of(context);
    final time = local.formatTimeOfDay(TimeOfDay.fromDateTime(last.toLocal()));
    final recent = DateTime.now().difference(last) < const Duration(minutes: 1);
    if (_store.state == .ready && recent) return 'Synced just now';
    final date = DateUtils.isSameDay(last.toLocal(), DateTime.now())
        ? 'today'
        : local.formatShortDate(last.toLocal());
    return 'Last synced $date at $time';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateUtils.dateOnly(DateTime.now());
    final visible = _visibleLists;
    final listNames = {for (final list in visible) list.id: list.title};
    final destination = _destination;
    final query = _search.text.trim().toLowerCase();
    final active = <_TaskKey, GoogleTask>{};
    final children = <_TaskKey, List<GoogleTask>>{};
    final siblings = <_TaskKey, List<GoogleTask>>{};
    for (final task in _store.tasks) {
      if (task.deleted ||
          (task.hidden && !_showHidden) ||
          (!_preferences.showAssigned && task.assigned) ||
          !listNames.containsKey(task.listId) ||
          (_listId != null && task.listId != _listId)) {
        continue;
      }
      active[_key(task)] = task;
      (siblings[(list: task.listId, task: task.parent ?? '')] ??= []).add(task);
      if (task.parent case final parent?) {
        (children[(list: task.listId, task: parent)] ??= []).add(task);
      }
    }
    for (final group in [...children.values, ...siblings.values]) {
      group.sort((a, b) => a.position.compareTo(b.position));
    }

    final parents = <GoogleTask>[];
    final completed = <GoogleTask>[];
    final undone = _undo == null
        ? null
        : _store.findTask(_undo!.listId, _undo!.id);
    final added = _recent == null
        ? null
        : _store.findTask(_recent!.listId, _recent!.id);
    final undo = undone == null ? null : _key(undone);
    final recent = added == null ? null : _key(added);
    final allCompleted = active.values
        .where((task) => task.completed && !task.pending)
        .toList();
    int matching = 0;
    for (final entry in active.entries) {
      final task = entry.value;
      if (task.parent != null &&
          active.containsKey((list: task.listId, task: task.parent!))) {
        continue;
      }
      final filtered =
          _matchesDate(task, now) &&
          (query.isEmpty ||
              _matchesSearch(task, query) ||
              (children[entry.key]?.any(
                    (child) => _matchesSearch(child, query),
                  ) ??
                  false));
      if (filtered && !task.completed) matching++;
      if (filtered || entry.key == undo || entry.key == recent) {
        (task.completed && entry.key != undo ? completed : parents).add(task);
      }
    }
    parents.sort((a, b) {
      if (_key(a) == recent) return -1;
      if (_key(b) == recent) return 1;
      if (!_manualOrder) {
        final group = _group(
          a.scheduled,
          now,
        ).index.compareTo(_group(b.scheduled, now).index);
        if (group != 0) return group;
        if (a.scheduled != null && b.scheduled != null) {
          final date = a.scheduled!.compareTo(b.scheduled!);
          if (date != 0) return date;
        }
      }
      return a.position.compareTo(b.position);
    });
    completed.sort((a, b) => a.position.compareTo(b.position));
    final limit = widget.compact
        ? widget.preferences.previewRows
        : parents.length;
    final rows = _rows(
      parents.take(limit).toList(),
      children,
      now,
      groupByDate: _view == .all && !_manualOrder,
    );
    if ((_showCompleted || _showHidden) && completed.isNotEmpty) {
      rows
        ..add('Completed')
        ..addAll(
          _rows(
            widget.compact ? completed.take(limit).toList() : completed,
            children,
            now,
            groupByDate: false,
          ),
        );
    }
    final headerCount = rows.whereType<_Group>().length;
    final rowIndexes = {
      for (var index = 0; index < rows.length; index++)
        if (rows[index] is GoogleTask) _key(rows[index] as GoogleTask): index,
    };
    final hasContent =
        _store.lists.isNotEmpty ||
        _store.lastSync != null ||
        _store.state == .ready;
    final banner = hasContent ? _syncBanner() : null;
    final actions = _TasksMenu(
      tooltip: 'Task options',
      icon: 'settings',
      items: [
        (label: 'Task settings', action: widget.onSettings),
        (label: 'Open in Google Tasks', action: () => _run(_openGoogleTasks)),
        if (hasContent) ...[
          (label: 'Manage lists', action: _manageLists),
          (
            label: 'Sync now',
            action: () => _run(() => _store.refresh(full: true)),
          ),
          if (_listId != null)
            (
              label: _manualOrder
                  ? 'Sort by Scheduled date'
                  : 'Sort by My order',
              action: () => setState(() => _sortByDate = _manualOrder),
            ),
          if (_listId != null && !_manualOrder)
            (label: 'Switch to My order to reorder', action: null),
          if (!widget.compact)
            (
              label: _showHidden
                  ? 'Hide archived completed tasks'
                  : 'Show hidden completed tasks',
              action: () => setState(() {
                _showHidden = !_showHidden;
                if (_showHidden) _showCompleted = true;
              }),
            ),
          if (allCompleted.isNotEmpty)
            (
              label: 'Delete completed tasks…',
              action: () => _bulkDelete(allCompleted),
            ),
          if (_store.issues.isNotEmpty || _store.conflicts.isNotEmpty)
            (label: 'Review sync issues', action: _reviewChanges),
        ],
      ],
    );
    final header = Column(
      crossAxisAlignment: .stretch,
      spacing: 12,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text(
                    'Tasks',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: .w700,
                      color: theme.colorScheme.primary,
                      height: 30 / 24,
                    ),
                  ),
                  const _TaskSupporting('Google Tasks'),
                ],
              ),
            ),
            actions,
            if (!widget.compact)
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const _TaskIcon('close', 20),
              ),
          ],
        ),
        if (hasContent) ...[
          _ListChoiceButton(
            label: listNames[_listId] ?? 'All lists',
            count: matching,
            onPressed: _selectList,
          ),
          SegmentedButton<_View>(
            showSelectedIcon: false,
            segments: [
              for (final view in _View.values)
                ButtonSegment(value: view, label: Text(view.label)),
            ],
            selected: {_view},
            onSelectionChanged: (selected) =>
                setState(() => _view = selected.single),
          ),
          ?banner,
          if (destination == null)
            OutlinedButton.icon(
              onPressed: _store.lists.isEmpty
                  ? _manageLists
                  : _selectDefaultList,
              icon: const _TaskIcon('add', 20),
              label: Text(
                _store.lists.isEmpty
                    ? 'Create list'
                    : 'Choose a list for new tasks',
              ),
            )
          else
            _QuickAdd(
              controller: _quickAdd,
              focusNode: _quickFocus,
              label: 'Add a task to ${destination.title}',
              saving: _adding,
              onSubmitted: _add,
            ),
          if (!widget.compact)
            _SearchField(
              controller: _search,
              hint: 'Search tasks',
              onChanged: () => setState(() {}),
            ),
        ],
      ],
    );

    final list = !hasContent
        ? _connectionState()
        : rows.isEmpty
        ? _emptyState(query, completed.isNotEmpty, destination != null)
        : ListView.builder(
            shrinkWrap: widget.compact,
            primary: false,
            itemCount: rows.length,
            findChildIndexCallback: (key) =>
                key is ValueKey<_TaskKey> ? rowIndexes[key.value] : null,
            itemBuilder: (context, index) => switch (rows[index]) {
              final GoogleTask task => _row(
                task,
                children,
                active,
                siblings,
                listNames,
                now,
              ),
              final _Group group => _SectionLabel(group.label),
              final String label => _SectionLabel(label),
              _ => const SizedBox.shrink(),
            },
          );

    final footer = Column(
      crossAxisAlignment: .stretch,
      spacing: 4,
      children: [
        if (_error case final error?)
          _TaskBanner(
            title: error,
            action: 'Dismiss',
            onPressed: () => setState(() => _error = null),
          ),
        if (_undo != null)
          _TaskBanner(
            title: 'Task completed',
            action: 'Undo',
            onPressed: _undoCompletion,
          )
        else if (_recent != null)
          _TaskBanner(
            title: 'Task added',
            action: 'View task',
            onPressed: _viewAdded,
          ),
        if (hasContent) ...[
          Wrap(
            alignment: .spaceBetween,
            crossAxisAlignment: .center,
            children: [
              TextButton.icon(
                icon: RotatedBox(
                  quarterTurns: _showCompleted ? 2 : 0,
                  child: const _TaskIcon('expand-small', 18),
                ),
                onPressed: completed.isEmpty
                    ? null
                    : () => setState(() {
                        _showCompleted = !_showCompleted;
                        if (!_showCompleted) _showHidden = false;
                      }),
                label: Text('Completed · ${completed.length}'),
              ),
              if (widget.compact)
                TextButton(onPressed: _viewAll, child: const Text('View all')),
            ],
          ),
          Wrap(
            alignment: .spaceBetween,
            crossAxisAlignment: .center,
            spacing: 8,
            children: [
              Row(
                mainAxisSize: .min,
                spacing: 8,
                children: [
                  const _TaskIcon('sync', 16),
                  Flexible(child: _TaskSupporting(_syncLabel(context))),
                ],
              ),
              TextButton(
                onPressed: _manageLists,
                child: const Text('Manage lists'),
              ),
            ],
          ),
        ],
      ],
    );

    if (!widget.compact) {
      return LayoutBuilder(
        builder: (_, constraints) {
          if (constraints.maxHeight <
              520 + (MediaQuery.textScalerOf(context).scale(16) - 16) * 16) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: .stretch,
                spacing: 12,
                children: [
                  header,
                  if (rows.isEmpty)
                    list
                  else
                    SizedBox(height: 200, child: list),
                  footer,
                ],
              ),
            );
          }
          return Column(
            crossAxisAlignment: .stretch,
            spacing: 12,
            children: [
              header,
              Expanded(
                child: rows.isEmpty ? SingleChildScrollView(child: list) : list,
              ),
              footer,
            ],
          );
        },
      );
    }
    final scaledHeight = MediaQuery.textScalerOf(context).scale(22) - 22;
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 12,
      children: [
        header,
        if (rows.isEmpty)
          list
        else
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: math.max(
                240,
                limit * (64 + scaledHeight * 2) + headerCount * 34 + 8,
              ),
            ),
            child: list,
          ),
        footer,
      ],
    );
  }

  Widget _emptyState(String query, bool completed, bool canAdd) {
    if (query.isNotEmpty) {
      return _TaskPrompt(
        icon: 'state-empty',
        title: 'No matching tasks',
        action: 'Clear search',
        onPressed: () => setState(_search.clear),
      );
    }
    if (completed) {
      return _TaskPrompt(
        icon: 'state-task',
        title: 'Everything is complete',
        message: 'Your completed tasks are still available.',
        action: 'View completed',
        onPressed: () => setState(() => _showCompleted = true),
      );
    }
    return _TaskPrompt(
      icon: 'state-empty',
      title: switch (_view) {
        .today => 'No tasks for today',
        .upcoming => 'No upcoming tasks',
        .all => 'No tasks yet',
      },
      message: 'Add a task or explore your other lists.',
      action: 'Add a task',
      onPressed: canAdd ? _quickFocus.requestFocus : null,
    );
  }
}
