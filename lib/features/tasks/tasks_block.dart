import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import 'tasks_links.dart';
import 'tasks_preferences.dart';
import 'tasks_store.dart';

part 'tasks_card.dart';
part 'tasks_dialogs.dart';
part 'tasks_rows.dart';
part 'tasks_status.dart';

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

enum _Section { completed }

typedef _TaskKey = ({String list, String task});

_TaskKey _key(GoogleTask task) => (list: task.listId, task: task.id);

class _TasksBlockState extends State<TasksBlock> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
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
  bool _connecting = false;
  bool _showHidden = false;
  bool _showSearch = false;

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
    _search.dispose();
    _searchFocus.dispose();
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
        _search.clear();
        _showSearch = false;
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
    if (list == null) return;
    final account = _accountId;
    final added = await showDialog<GoogleTask>(
      context: context,
      builder: (_) => _AccountGuard(
        store: _store,
        child: _AddTaskDialog(store: _store, list: list),
      ),
    );
    if (mounted && account == _accountId && added != null) {
      _setNotice(added: added);
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

  KeyEventResult _addShortcut(FocusNode node, KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.keyN ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed ||
        keyboard.isShiftPressed ||
        _destination == null ||
        FocusManager.instance.primaryFocus?.context
                ?.findAncestorWidgetOfExactType<EditableText>() !=
            null) {
      return .ignored;
    }
    unawaited(_add());
    return .handled;
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
    if (id != null && mounted && account == _accountId) {
      await _run(() => widget.onSetDefaultList(id));
    }
  }

  Future<void> _viewAll({_View? view, String? list}) => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: .zero,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(borderRadius: .all(.circular(32))),
      clipBehavior: .antiAlias,
      child: SizedBox(
        width: 420,
        height: double.infinity,
        child: Padding(
          padding: const .all(24),
          child: Align(
            alignment: .topCenter,
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
        await _run(() => openTaskLink(task.sourceLink));
      case .external:
        await _run(() => openGoogleTasks(task.webViewLink));
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

  void _toggleArchived() => setState(() {
    _showHidden = !_showHidden;
    if (_showHidden) _showCompleted = true;
  });

  bool _matchesDate(GoogleTask task, DateTime now) {
    final date = task.scheduled;
    return switch (_view) {
      .today =>
        date == null
            ? _preferences.todayIncludesUnscheduled
            : DateUtils.isSameDay(date, now),
      .upcoming => date != null && _taskGroup(date, now) == .upcoming,
      .all => true,
    };
  }

  bool _matchesSearch(GoogleTask task, String query) =>
      task.title.toLowerCase().contains(query) ||
      task.notes.toLowerCase().contains(query);

  Widget _row(
    GoogleTask task,
    Map<_TaskKey, List<GoogleTask>> children,
    Map<_TaskKey, GoogleTask> active,
    Map<_TaskKey, List<GoogleTask>> siblingsByParent,
    Map<String, String> listNames,
    DateTime now,
    BorderRadius corners,
    bool hasNextTask,
  ) {
    final key = _key(task);
    final parent = active[(list: task.listId, task: task.parent ?? '')];
    final subtasks = children[key] ?? const <GoogleTask>[];
    final siblings =
        siblingsByParent[(list: task.listId, task: task.parent ?? '')] ??
        const <GoogleTask>[];
    final index = siblings.indexWhere((row) => row.id == task.id);
    final movable = _manualOrder && !task.pending && !task.hidden && index >= 0;
    return _TaskRow(
      key: ValueKey(key),
      task: task,
      childRow: parent != null,
      corners: corners,
      hasNextTask: hasNextTask,
      dateLabel:
          task.scheduled != null &&
              !DateUtils.isSameDay(task.scheduled, parent?.scheduled)
          ? _friendlyDate(context, task.scheduled!, now)
          : null,
      listLabel: _listId == null && parent == null
          ? listNames[task.listId]
          : null,
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

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: _addShortcut,
    child: _buildBlock(context),
  );

  Widget _buildBlock(BuildContext context) {
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
    var matching = 0;
    var matchingCompleted = 0;
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
      if (filtered) {
        if (task.completed) {
          matchingCompleted++;
        } else {
          matching++;
        }
      }
      if (filtered || entry.key == undo || entry.key == recent) {
        (task.completed && entry.key != undo ? completed : parents).add(task);
      }
    }
    parents.sort((a, b) {
      if (_key(a) == recent) return -1;
      if (_key(b) == recent) return 1;
      if (!_manualOrder) {
        final group = _taskGroup(
          a.scheduled,
          now,
        ).index.compareTo(_taskGroup(b.scheduled, now).index);
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
    final rows = _taskRows(
      parents.take(limit).toList(),
      children,
      now,
      groupByDate: _view == .all && !_manualOrder,
      opened: _opened,
    );
    final showCompleted = _showCompleted && completed.isNotEmpty;
    final hasTaskRows = rows.isNotEmpty || showCompleted;
    if (completed.isNotEmpty) rows.add(_Section.completed);
    if (showCompleted) {
      rows.addAll(
        _taskRows(
          widget.compact ? completed.take(limit).toList() : completed,
          children,
          now,
          groupByDate: false,
          opened: _opened,
        ),
      );
    }
    final headerCount = rows.where((row) => row is! GoogleTask).length;
    final rowIndexes = {
      for (var index = 0; index < rows.length; index++)
        if (rows[index] is GoogleTask) _key(rows[index] as GoogleTask): index,
    };
    final hasContent =
        _store.lists.isNotEmpty ||
        _store.lastSync != null ||
        _store.state == .ready;
    final status = _TasksStatus(
      _store,
      onConnect: _connecting ? null : _connect,
      onRetry: () => _run(_store.retry),
      onReview: _reviewChanges,
    );
    final header = Column(
      crossAxisAlignment: .stretch,
      spacing: widget.compact ? 12 : 16,
      children: [
        _TasksHeader(
          listMenu: hasContent
              ? _ListSelectMenu(
                  label: listNames[_listId] ?? 'All lists',
                  count: matching,
                  selectedId: _listId,
                  lists: visible,
                  onSelected: (id) => setState(() => _listId = id),
                  onManage: _manageLists,
                  sortLabel: _listId == null
                      ? null
                      : _manualOrder
                      ? 'Sort by Scheduled date'
                      : 'Sort by My order',
                  onSort: () => setState(() => _sortByDate = _manualOrder),
                  archived: widget.compact
                      ? null
                      : (showing: _showHidden, toggle: _toggleArchived),
                )
              : null,
          syncing: hasContent && status.syncing,
          onSync: hasContent
              ? () => _run(() => _store.refresh(full: true))
              : null,
          onSettings: widget.onSettings,
          onSearch: hasContent && !widget.compact ? _toggleSearch : null,
          showingSearch: _showSearch,
          onClose: widget.compact ? null : () => Navigator.pop(context),
        ),
        if (hasContent) ...[
          if (!widget.compact &&
              _view == .today &&
              query.isEmpty &&
              matching + matchingCompleted > 0)
            _TodaySummary(remaining: matching, completed: matchingCompleted),
          _ViewFilters(
            selected: _view,
            onSelected: (view) => setState(() => _view = view),
          ),
          ?status.banner(),
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
            ),
          if (_showSearch)
            _SearchField(
              controller: _search,
              focusNode: _searchFocus,
              hint: 'Search tasks',
              onChanged: () => setState(() {}),
            ),
        ],
      ],
    );

    final completedControl = completed.isEmpty
        ? null
        : _CompletedControl(
            expanded: _showCompleted,
            onToggle: () => setState(() {
              _showCompleted = !_showCompleted;
              if (!_showCompleted) _showHidden = false;
            }),
          );
    final list = !hasContent
        ? status.prompt()
        : !hasTaskRows
        ? Column(
            crossAxisAlignment: .stretch,
            children: [
              _emptyTasks(
                _view,
                query: query,
                completed: completed.isNotEmpty,
                onClearSearch: () => setState(_search.clear),
                onShowCompleted: () => setState(() => _showCompleted = true),
              ),
              ?completedControl,
            ],
          )
        : ListView.builder(
            shrinkWrap:
                widget.compact || rows.length <= _preferences.previewRows,
            primary: false,
            itemCount: rows.length,
            findChildIndexCallback: (key) =>
                key is ValueKey<_TaskKey> ? rowIndexes[key.value] : null,
            itemBuilder: (context, index) {
              final entry = rows[index];
              if (entry == _Section.completed) return completedControl;
              if (entry is _Group) return _SectionLabel(entry.label);
              final previousTask = index > 0 && rows[index - 1] is GoogleTask;
              final nextTask =
                  index + 1 < rows.length && rows[index + 1] is GoogleTask;
              return _row(
                entry as GoogleTask,
                children,
                active,
                siblings,
                listNames,
                now,
                BorderRadius.vertical(
                  top: .circular(previousTask ? 4 : 20),
                  bottom: .circular(nextTask ? 4 : 20),
                ),
                nextTask,
              );
            },
          );

    final footer = _TasksFooter(
      error: _error == null
          ? null
          : _TaskBanner(
              title: _error!,
              action: 'Dismiss',
              onPressed: () => setState(() => _error = null),
            ),
      notice: _undo != null
          ? _TaskBanner(
              title: 'Task completed',
              action: 'Undo',
              onPressed: _undoCompletion,
            )
          : _recent != null
          ? _TaskBanner(
              title: 'Task added',
              action: 'View task',
              onPressed: _viewAdded,
            )
          : null,
      onShowAll: hasContent && widget.compact ? _viewAll : null,
      onAdd: hasContent && destination != null ? _add : null,
      syncLabel: hasContent ? status.label(context) : null,
    );

    if (!widget.compact) {
      return _FullTasksLayout(
        header: header,
        list: list,
        hasTaskRows: hasTaskRows,
        footer: footer,
      );
    }
    final scaler = MediaQuery.textScalerOf(context);
    final rowHeight =
        16 + 2 * (scaler.scale(16) * 22 / 16 + scaler.scale(13) * 18 / 13) + 2;
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 12,
      children: [
        header,
        if (!hasTaskRows)
          list
        else
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: math.max(
                240,
                limit * rowHeight +
                    headerCount * (16 + scaler.scale(13) * 18 / 13) +
                    40,
              ),
            ),
            child: list,
          ),
        footer,
      ],
    );
  }

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (_showSearch) {
        _searchFocus.requestFocus();
      } else {
        _search.clear();
      }
    });
  }
}
