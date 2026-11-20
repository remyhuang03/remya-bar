part of 'tasks_block.dart';

TextStyle? _dialogTitle(BuildContext context) =>
    Theme.of(context).textTheme.headlineSmall
        ?.copyWith(fontWeight: .w700, height: 30 / 24);

class _TasksDialog extends StatelessWidget {
  const _TasksDialog({
    required this.title,
    required this.child,
    this.actions = const [],
    this.fixedBody = false,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final bool fixedBody;

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const .all(8),
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(borderRadius: .all(.circular(32))),
    child: SizedBox(
      width: 420,
      child: Padding(
        padding: const .all(24),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          spacing: 12,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: _dialogTitle(context))),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const _TaskIcon('close', 20),
                ),
              ],
            ),
            Flexible(
              child: fixedBody ? child : SingleChildScrollView(child: child),
            ),
            if (actions.isNotEmpty)
              OverflowBar(
                spacing: 8,
                overflowSpacing: 8,
                alignment: .end,
                children: actions,
              ),
          ],
        ),
      ),
    ),
  );
}

class _AccountGuard extends StatefulWidget {
  const _AccountGuard({required this.store, required this.child});

  final TasksStore store;
  final Widget child;

  @override
  State<_AccountGuard> createState() => _AccountGuardState();
}

class _AccountGuardState extends State<_AccountGuard> {
  String? _accountId;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _accountId = widget.store.account?.accountId;
    widget.store.addListener(_change);
  }

  void _change() {
    if (_closing || _accountId == widget.store.account?.accountId) return;
    _closing = true;
    final route = ModalRoute.of(context);
    final navigator = route?.navigator;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && route?.isActive == true) navigator?.removeRoute(route!);
    });
  }

  @override
  void dispose() {
    widget.store.removeListener(_change);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  String? source,
  bool destructive = true,
  required TasksStore store,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _AccountGuard(
        store: store,
        child: _TaskConfirmation(
          title: title,
          message: message,
          action: action,
          source: source,
          destructive: destructive,
        ),
      ),
    ) ??
    false;

class _TaskConfirmation extends StatefulWidget {
  const _TaskConfirmation({
    required this.title,
    required this.message,
    required this.action,
    this.source,
    required this.destructive,
  });

  final String title;
  final String message;
  final String action;
  final String? source;
  final bool destructive;

  @override
  State<_TaskConfirmation> createState() => _TaskConfirmationState();
}

class _TaskConfirmationState extends State<_TaskConfirmation> {
  String? _error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _TasksDialog(
      title: widget.title,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: widget.destructive
              ? FilledButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                )
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(widget.action),
        ),
      ],
      child: Column(
        crossAxisAlignment: .start,
        mainAxisSize: .min,
        spacing: 8,
        children: [
          if (widget.destructive) const _TaskIcon('confirm-error', 32),
          Text(widget.message),
          if (widget.source != null)
            TextButton(
              onPressed: () async {
                try {
                  await openTaskLink(widget.source);
                } on Object catch (error) {
                  if (mounted) setState(() => _error = _actionError(error));
                }
              },
              child: const Text('Open source'),
            ),
          if (_error case final error?)
            _TaskSupporting(error, color: colors.error),
        ],
      ),
    );
  }
}

Future<bool> _deleteTask(
  BuildContext context,
  TasksStore store,
  GoogleTask task,
  int children,
  Future<bool> Function(Future<void> Function()) run,
) async {
  final account = store.account?.accountId;
  final source = switch (task.sourceKind) {
    'DOCUMENT' => 'Google Docs',
    'SPACE' => 'Google Chat',
    _ => 'its source',
  };
  final confirmed = await _confirm(
    context,
    title: task.assigned ? 'Delete assigned task?' : 'Delete task?',
    message: [
      '“${task.title}” will be deleted.',
      if (task.assigned)
        'This also deletes the task in $source. To remove only the assignment, open the source.',
      if (children > 0)
        '$children ${children == 1 ? 'subtask is' : 'subtasks are'} attached to this task.',
    ].join(' '),
    action: 'Delete task',
    source: task.sourceLink,
    store: store,
  );
  if (!confirmed || !context.mounted || account != store.account?.accountId) {
    return false;
  }
  return run(() => store.deleteTask(task));
}

typedef _Choice = ({String id, String label});

Future<String?> _pick(
  BuildContext context, {
  required String title,
  required List<_Choice> choices,
  String? selected,
  required TasksStore store,
}) => showDialog<String>(
  context: context,
  builder: (_) => _AccountGuard(
    store: store,
    child: _ChoiceDialog(title: title, choices: choices, selected: selected),
  ),
);

class _ChoiceDialog extends StatefulWidget {
  const _ChoiceDialog({
    required this.title,
    required this.choices,
    required this.selected,
  });

  final String title;
  final List<_Choice> choices;
  final String? selected;

  @override
  State<_ChoiceDialog> createState() => _ChoiceDialogState();
}

class _ChoiceDialogState extends State<_ChoiceDialog> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final options = widget.choices
        .where((choice) => choice.label.toLowerCase().contains(query))
        .toList();
    return _TasksDialog(
      title: widget.title,
      fixedBody: true,
      child: Column(
        mainAxisSize: .min,
        spacing: 12,
        children: [
          if (widget.choices.length > 6)
            _SearchField(
              controller: _search,
              hint: 'Search',
              onChanged: () => setState(() {}),
            ),
          if (options.isEmpty)
            Padding(
              padding: const .all(12),
              child: Column(
                children: [
                  Text(query.isEmpty ? 'No options available' : 'No matches'),
                  if (query.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(_search.clear),
                      child: const Text('Clear search'),
                    ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final choice = options[index];
                  final selected = widget.selected == choice.id;
                  return ListTile(
                    selected: selected,
                    title: Text(choice.label, maxLines: 2, overflow: .ellipsis),
                    trailing: selected ? const Icon(Icons.check_rounded) : null,
                    onTap: () => Navigator.pop(context, choice.id),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _TaskEditor extends StatefulWidget {
  const _TaskEditor({
    required this.store,
    required this.task,
    this.addSubtask = false,
  });

  final TasksStore store;
  final GoogleTask task;
  final bool addSubtask;

  @override
  State<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<_TaskEditor> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  final _subtask = TextEditingController();
  final _subtaskFocus = FocusNode();
  late final GoogleTask _original;
  late final String? _accountId;
  Timer? _draftTimer;
  DateTime? _scheduled;
  String? _error;
  bool _busy = false;
  bool _submitted = false;

  TasksStore get _store => widget.store;

  GoogleTask? get _current =>
      _store.findTask(widget.task.listId, widget.task.id);

  @override
  void initState() {
    super.initState();
    _accountId = _store.account?.accountId;
    _original = _store.draftBaseFor(widget.task) ?? widget.task;
    final draft = _store.draftFor(widget.task);
    _title = TextEditingController(
      text: draft?['title'] as String? ?? _original.title,
    );
    _notes = TextEditingController(
      text: draft?['notes'] as String? ?? _original.notes,
    );
    _scheduled = draft?.containsKey('scheduled') == true
        ? draft!['scheduled'] as DateTime?
        : _original.scheduled;
    if (widget.addSubtask) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _subtaskFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    if (!_submitted && _current != null) {
      final changes = _changes;
      final base = _baseline;
      final store = _store;
      final account = _accountId;
      if (changes.isNotEmpty || store.draftFor(base) != null) {
        scheduleMicrotask(() {
          if (store.account?.accountId != account) return;
          try {
            store.saveDraft(base, changes);
          } on Object {
            // The previously saved draft remains if this save fails.
          }
        });
      }
    }
    _title.dispose();
    _notes.dispose();
    _subtask.dispose();
    _subtaskFocus.dispose();
    super.dispose();
  }

  Map<String, Object?> get _changes => {
    if (_title.text != _original.title) 'title': _title.text,
    if (_notes.text != _original.notes && _current?.sourceKind != 'DOCUMENT')
      'notes': _notes.text,
    if (!DateUtils.isSameDay(_scheduled, _original.scheduled))
      'scheduled': _scheduled,
  };

  GoogleTask get _baseline {
    final current = _current ?? _original;
    if (_original.id == current.id && _original.listId == current.listId) {
      return _original;
    }
    return GoogleTask(
      id: current.id,
      listId: current.listId,
      title: _original.title,
      notes: _original.notes,
      scheduled: _original.scheduled,
      etag: _original.etag,
      position: current.position,
      parent: current.parent,
      sourceKind: current.sourceKind,
      completed: current.completed,
    );
  }

  void _persistDraft() {
    final changes = _changes;
    if (changes.isEmpty && _store.draftFor(_baseline) == null) return;
    _store.saveDraft(_baseline, changes);
  }

  void _changed() {
    setState(() => _error = null);
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || _accountId != _store.account?.accountId || _submitted) {
        return;
      }
      try {
        _persistDraft();
      } on Object catch (error) {
        setState(() => _error = _actionError(error));
      }
    });
  }

  Future<bool> _run(Future<void> Function() action) async {
    if (_busy || _accountId != _store.account?.accountId) return false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      return mounted && _accountId == _store.account?.accountId;
    } on Object catch (error) {
      if (mounted) setState(() => _error = _actionError(error));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_current == null || _title.text.trim().isEmpty || _busy) return;
    _draftTimer?.cancel();
    if (await _run(
          () => _store.editTask(_baseline, _changes, clearDraft: true),
        ) &&
        mounted) {
      _submitted = true;
      Navigator.pop(context);
    }
  }

  Future<void> _cancel() async {
    if (_busy) return;
    if (_changes.isNotEmpty) {
      final discard = await _confirm(
        context,
        title: 'Discard this draft?',
        message: 'Your unsaved task edits will be deleted.',
        action: 'Discard draft',
        store: _store,
      );
      if (!discard || !mounted) return;
    }
    _draftTimer?.cancel();
    if (await _run(() async => _store.discardDraft(_baseline)) && mounted) {
      _submitted = true;
      Navigator.pop(context);
    }
  }

  Future<void> _addSubtask(GoogleTask current) async {
    final title = _subtask.text.trim();
    if (title.isEmpty) return;
    if (await _run(() async {
          await _store.addTask(current.listId, title, parent: current.id);
        }) &&
        mounted) {
      _subtask.clear();
      _subtaskFocus.requestFocus();
    }
  }

  Future<void> _pickDate() async {
    final choice = await showDialog<({DateTime? date})>(
      context: context,
      builder: (_) => _SchedulePicker(initial: _scheduled),
    );
    if (choice == null || !mounted) return;
    setState(() => _scheduled = choice.date);
    _changed();
  }

  Future<void> _move(GoogleTask current) async {
    if (!await _run(() async => _persistDraft()) || !mounted) return;
    final moved = await showDialog<bool>(
      context: context,
      builder: (_) => _MoveTask(store: _store, task: current),
    );
    if (moved == true && mounted) {
      _submitted = true;
      Navigator.pop(context);
    }
  }

  Future<void> _delete(GoogleTask current, int children) async {
    if (await _deleteTask(context, _store, current, children, _run) &&
        mounted) {
      _submitted = true;
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => _AccountGuard(
    store: _store,
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
      },
      child: ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          final current = _current;
          if (current == null) {
            return const _TasksDialog(
              title: 'Edit task',
              child: Text('This task is no longer available.'),
            );
          }
          final children = _store.tasks
              .where(
                (task) =>
                    task.listId == current.listId &&
                    task.parent == current.id &&
                    !task.deleted &&
                    !task.hidden,
              )
              .toList();
          final list = _store.lists
              .where((list) => list.id == current.listId)
              .firstOrNull;
          final canAdd =
              !current.assigned && !current.hidden && current.parent == null;
          final readonlyNotes = current.sourceKind == 'DOCUMENT';
          return _TasksDialog(
            title: 'Edit task',
            actions: [
              TextButton(
                onPressed: _busy || current.pending
                    ? null
                    : () => _delete(current, children.length),
                child: const Text('Delete'),
              ),
              FilledButton.tonal(
                onPressed: _busy ? null : _cancel,
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _busy || _title.text.trim().isEmpty ? null : _save,
                child: const Text('Save'),
              ),
            ],
            child: Column(
              crossAxisAlignment: .stretch,
              spacing: 12,
              children: [
                TextField(
                  controller: _title,
                  autofocus: !widget.addSubtask,
                  readOnly: _busy,
                  maxLines: 2,
                  minLines: 1,
                  maxLength: 1024,
                  buildCounter: _lengthCounter,
                  decoration: _taskInput(context, label: 'Title'),
                  onChanged: (_) => _changed(),
                ),
                TextField(
                  controller: _notes,
                  readOnly: readonlyNotes || _busy,
                  maxLines: 8,
                  minLines: 2,
                  maxLength: 8192,
                  buildCounter: _lengthCounter,
                  decoration: _taskInput(context, label: 'Notes'),
                  onChanged: (_) => _changed(),
                ),
                if (readonlyNotes)
                  const _TaskSupporting(
                    'Edit notes in the assigned Google Doc.',
                  ),
                Column(
                  crossAxisAlignment: .stretch,
                  spacing: 4,
                  children: [
                    const _TaskSupporting('List'),
                    _ListChoiceButton(
                      label: list?.title ?? 'Current list',
                      onPressed: _busy || current.pending
                          ? null
                          : () => _move(current),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: .stretch,
                  spacing: 4,
                  children: [
                    const _TaskSupporting('Scheduled date'),
                    Row(
                      children: [
                        Expanded(
                          child: _ListChoiceButton(
                            icon: 'date',
                            label: _scheduled == null
                                ? 'Choose date'
                                : _friendlyDate(
                                    context,
                                    _scheduled!,
                                    DateTime.now(),
                                  ),
                            onPressed: _busy ? null : _pickDate,
                          ),
                        ),
                        if (_scheduled != null)
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    setState(() => _scheduled = null);
                                    _changed();
                                  },
                            child: const Text('Clear'),
                          ),
                      ],
                    ),
                  ],
                ),
                if (canAdd || children.isNotEmpty)
                  _TaskSupporting(
                    'Subtasks · ${children.where((t) => t.completed).length} of ${children.length} completed',
                  ),
                if (children.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 192),
                    child: ListView.builder(
                      primary: false,
                      shrinkWrap: true,
                      itemCount: children.length,
                      itemBuilder: (context, index) {
                        final child = children[index];
                        return _TaskRow(
                          key: ValueKey(_key(child)),
                          task: child,
                          childRow: true,
                          dateLabel: null,
                          listLabel: null,
                          children: const [],
                          expanded: false,
                          onExpand: () {},
                          onOpen: () => showDialog<void>(
                            context: context,
                            builder: (_) =>
                                _TaskEditor(store: _store, task: child),
                          ),
                          onComplete: _busy
                              ? null
                              : (completed) => _run(
                                  () => _store.editTask(child, {
                                    'completed': completed,
                                  }),
                                ),
                          onAction: (action) async {
                            switch (action) {
                              case .edit:
                                await showDialog<void>(
                                  context: context,
                                  builder: (_) =>
                                      _TaskEditor(store: _store, task: child),
                                );
                              case .move:
                                await showDialog<bool>(
                                  context: context,
                                  builder: (_) =>
                                      _MoveTask(store: _store, task: child),
                                );
                              case .moveOut:
                                await _run(() => _store.moveTask(child));
                              case .delete:
                                if (context.mounted) {
                                  await _deleteTask(
                                    context,
                                    _store,
                                    child,
                                    0,
                                    _run,
                                  );
                                }
                              case .external:
                                await _run(
                                  () => openGoogleTasks(child.webViewLink),
                                );
                              case .source:
                                await _run(
                                  () => openTaskLink(child.sourceLink),
                                );
                              case .issues:
                                await showDialog<void>(
                                  context: context,
                                  builder: (_) => _SyncIssues(store: _store),
                                );
                              case .addChild || .up || .down:
                                break;
                            }
                          },
                          moveEarlier: false,
                          moveLater: false,
                          canDrag: false,
                          acceptsDrag: (_) => false,
                          onDrop: (_) {},
                        );
                      },
                    ),
                  ),
                if (canAdd)
                  _QuickAdd(
                    controller: _subtask,
                    focusNode: _subtaskFocus,
                    label: 'Add a subtask',
                    saving: _busy,
                    onSubmitted: () => _addSubtask(current),
                  ),
                if (taskHttpsUrl(current.sourceLink) != null)
                  Align(
                    alignment: .centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          _run(() => openTaskLink(current.sourceLink)),
                      icon: const _TaskIcon('external', 18),
                      label: const Text('Open source'),
                    ),
                  ),
                const _TaskSupporting(
                  'Manage times, deadlines, repeats and stars in Google Tasks.',
                ),
                Align(
                  alignment: .centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        _run(() => openGoogleTasks(current.webViewLink)),
                    icon: const _TaskIcon('external', 18),
                    label: const Text('Open in Google Tasks'),
                  ),
                ),
                if (_error case final error?)
                  _TaskSupporting(
                    error,
                    color: Theme.of(context).colorScheme.error,
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _SchedulePicker extends StatefulWidget {
  const _SchedulePicker({required this.initial});

  final DateTime? initial;

  @override
  State<_SchedulePicker> createState() => _SchedulePickerState();
}

class _SchedulePickerState extends State<_SchedulePicker> {
  late final DateTime _today = DateUtils.dateOnly(DateTime.now());
  late DateTime _selected = widget.initial ?? _today;
  int _revision = 0;

  void _quickDate(DateTime value) {
    setState(() {
      _selected = value;
      _revision++;
    });
  }

  @override
  Widget build(BuildContext context) => _TasksDialog(
    title: 'Scheduled date',
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, (date: null as DateTime?)),
        child: const Text('Clear date'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, (date: _selected)),
        child: const Text('Done'),
      ),
    ],
    child: Column(
      crossAxisAlignment: .stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonal(
              onPressed: () => _quickDate(_today),
              child: const Text('Today'),
            ),
            FilledButton.tonal(
              onPressed: () => _quickDate(DateUtils.addDaysToDate(_today, 1)),
              child: const Text('Tomorrow'),
            ),
          ],
        ),
        CalendarDatePicker(
          key: ValueKey(_revision),
          initialDate: _selected,
          firstDate: DateTime(math.min(1900, _selected.year)),
          lastDate: DateTime(math.max(2100, _selected.year), 12, 31),
          onDateChanged: (date) => setState(() => _selected = date),
        ),
      ],
    ),
  );
}

class _MoveTask extends StatefulWidget {
  const _MoveTask({required this.store, required this.task});

  final TasksStore store;
  final GoogleTask task;

  @override
  State<_MoveTask> createState() => _MoveTaskState();
}

class _MoveTaskState extends State<_MoveTask> {
  late String _listId = widget.task.listId;
  late String? _parent = widget.task.parent;
  String? _accountId;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _accountId = widget.store.account?.accountId;
  }

  Future<void> _chooseList() async {
    final result = await _pick(
      context,
      title: 'Destination list',
      store: widget.store,
      selected: _listId,
      choices: [
        for (final list in widget.store.lists) (id: list.id, label: list.title),
      ],
    );
    if (!mounted || result == null || result == _listId) return;
    setState(() {
      _listId = result;
      _parent = null;
    });
  }

  Future<void> _chooseParent() async {
    // Top-level choices prevent a cycle and keep the task/subtask hierarchy.
    final choices = widget.store.tasks.where(
      (task) =>
          task.listId == _listId &&
          task.id != widget.task.id &&
          task.parent == null &&
          !task.hidden &&
          !task.deleted &&
          !task.assigned,
    );
    final result = await _pick(
      context,
      title: 'Parent task',
      store: widget.store,
      selected: _parent ?? '',
      choices: [
        (id: '', label: 'No parent'),
        for (final task in choices) (id: task.id, label: task.title),
      ],
    );
    if (mounted && result != null) {
      setState(() => _parent = result.isEmpty ? null : result);
    }
  }

  Future<void> _save() async {
    if (_saving || _accountId != widget.store.account?.accountId) return;
    setState(() => _saving = true);
    try {
      await widget.store.moveTask(
        widget.task,
        destinationListId: _listId,
        parent: _parent,
      );
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _actionError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final changed =
        _listId != widget.task.listId || _parent != widget.task.parent;
    final canNest = !widget.task.assigned && !widget.task.hidden;
    final listName = widget.store.lists
        .where((list) => list.id == _listId)
        .firstOrNull
        ?.title;
    final parentName = widget.store.tasks
        .where((task) => task.listId == _listId && task.id == _parent)
        .firstOrNull
        ?.title;
    return _AccountGuard(
      store: widget.store,
      child: _TasksDialog(
        title: 'Move task',
        actions: [
          FilledButton.tonal(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving || !changed || listName == null ? null : _save,
            child: const Text('Move'),
          ),
        ],
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 10,
          children: [
            Text(widget.task.title),
            const _TaskSupporting('Destination list'),
            _ListChoiceButton(
              label: listName ?? 'Choose a list',
              onPressed: _saving ? null : _chooseList,
            ),
            if (canNest) ...[
              const _TaskSupporting('Parent task'),
              _ListChoiceButton(
                label: parentName ?? 'No parent',
                onPressed: _saving ? null : _chooseParent,
              ),
              const _TaskSupporting(
                'Keep it as a main task or choose a task in the destination list.',
              ),
            ],
            if (_error case final error?)
              _TaskSupporting(
                error,
                color: Theme.of(context).colorScheme.error,
              ),
          ],
        ),
      ),
    );
  }
}

class _ManageLists extends StatefulWidget {
  const _ManageLists({
    required this.store,
    required this.defaultList,
    required this.onSetDefaultList,
  });

  final TasksStore store;
  final String? Function() defaultList;
  final Future<void> Function(String) onSetDefaultList;

  @override
  State<_ManageLists> createState() => _ManageListsState();
}

class _ManageListsState extends State<_ManageLists> {
  final _search = TextEditingController();
  late final String? _accountId;
  String? _error;

  TasksStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _accountId = _store.account?.accountId;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_store.account?.accountId != _accountId) return;
    try {
      await action();
      if (mounted && _error != null) setState(() => _error = null);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _actionError(error));
    }
  }

  Future<void> _nameList([TaskList? list]) => showDialog<void>(
    context: context,
    builder: (_) => _AccountGuard(
      store: _store,
      child: _ListNameDialog(
        list: list,
        onSave: (title) async {
          if (_accountId != _store.account?.accountId) {
            throw const TasksEditException('The Google Tasks account changed.');
          }
          if (list == null) {
            await _store.createList(title);
          } else {
            await _store.renameList(list, title);
          }
        },
      ),
    ),
  );

  Future<void> _deleteList(TaskList list, int total) async {
    final confirmed = await _confirm(
      context,
      title: 'Delete list?',
      message:
          '“${list.title}” and its $total ${total == 1 ? 'task' : 'tasks'} will be deleted.',
      action: 'Delete list',
      store: _store,
    );
    if (!mounted || !confirmed) return;
    await _run(() async {
      if (widget.defaultList() == list.id) await widget.onSetDefaultList('');
      if (_store.account?.accountId == _accountId) {
        await _store.deleteList(list);
      }
    });
  }

  @override
  Widget build(BuildContext context) => _AccountGuard(
    store: _store,
    child: ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final query = _search.text.trim().toLowerCase();
        final lists = _store.lists
            .where((list) => list.title.toLowerCase().contains(query))
            .toList();
        final activeCounts = <String, int>{};
        final taskCounts = <String, int>{};
        for (final task in _store.tasks) {
          if (task.deleted) continue;
          taskCounts.update(
            task.listId,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
          if (!task.completed && task.parent == null && !task.hidden) {
            activeCounts.update(
              task.listId,
              (count) => count + 1,
              ifAbsent: () => 1,
            );
          }
        }
        return _TasksDialog(
          title: 'Manage lists',
          fixedBody: true,
          actions: [
            FilledButton(
              onPressed: _nameList,
              child: const Text('Create new list'),
            ),
          ],
          child: Column(
            crossAxisAlignment: .stretch,
            mainAxisSize: .min,
            spacing: 12,
            children: [
              _TaskSupporting(_store.account?.email ?? 'Connected account'),
              _SearchField(
                controller: _search,
                hint: 'Search lists',
                onChanged: () => setState(() {}),
              ),
              if (_error case final error?)
                _TaskSupporting(
                  error,
                  color: Theme.of(context).colorScheme.error,
                ),
              if (lists.isEmpty)
                if (query.isEmpty)
                  const Text('No task lists')
                else
                  Column(
                    crossAxisAlignment: .start,
                    children: [
                      const Text('No matching lists'),
                      TextButton(
                        onPressed: () => setState(_search.clear),
                        child: const Text('Clear search'),
                      ),
                    ],
                  )
              else
                Flexible(
                  child: ListView.separated(
                    primary: false,
                    shrinkWrap: true,
                    itemCount: lists.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final list = lists[index];
                      final colors = Theme.of(context).colorScheme;
                      return Material(
                        borderRadius: .circular(12),
                        color: colors.surfaceContainerHighest,
                        clipBehavior: .antiAlias,
                        child: Padding(
                          padding: const .only(left: 12),
                          child: Row(
                            spacing: 8,
                            children: [
                              const _TaskIcon('list', 20),
                              Expanded(
                                child: Text(
                                  list.title,
                                  maxLines: 2,
                                  overflow: .ellipsis,
                                ),
                              ),
                              _TaskSupporting('${activeCounts[list.id] ?? 0}'),
                              _TasksMenu(
                                tooltip: 'List menu for ${list.title}',
                                items: [
                                  (
                                    label: 'Rename',
                                    action: () => _nameList(list),
                                  ),
                                  (
                                    label: 'Set as default',
                                    action: list.pending
                                        ? null
                                        : () => _run(
                                            () => widget.onSetDefaultList(
                                              list.id,
                                            ),
                                          ),
                                  ),
                                  (
                                    label: 'Hide completed tasks',
                                    action: () => _run(
                                      () => _store.hideCompleted(list.id),
                                    ),
                                  ),
                                  (
                                    label: 'Delete list…',
                                    action: () => _deleteList(
                                      list,
                                      taskCounts[list.id] ?? 0,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const _TaskSupporting('Deleting a list also deletes its tasks.'),
            ],
          ),
        );
      },
    ),
  );
}

class _ListNameDialog extends StatefulWidget {
  const _ListNameDialog({required this.list, required this.onSave});

  final TaskList? list;
  final Future<void> Function(String) onSave;

  @override
  State<_ListNameDialog> createState() => _ListNameDialogState();
}

class _ListNameDialogState extends State<_ListNameDialog> {
  late final _name = TextEditingController(text: widget.list?.title);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _name.text.trim();
    if (_saving || text.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(text);
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _actionError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => _TasksDialog(
    title: widget.list == null ? 'Create list' : 'Rename list',
    actions: [
      FilledButton.tonal(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving || _name.text.trim().isEmpty ? null : _save,
        child: Text(widget.list == null ? 'Create' : 'Rename'),
      ),
    ],
    child: TextField(
      controller: _name,
      autofocus: true,
      readOnly: _saving,
      decoration: _taskInput(context, label: 'List name', error: _error),
      maxLength: 1024,
      buildCounter: _lengthCounter,
      onSubmitted: (_) => _save(),
      onChanged: (_) => setState(() => _error = null),
    ),
  );
}

class _SyncIssues extends StatefulWidget {
  const _SyncIssues({required this.store});

  final TasksStore store;

  @override
  State<_SyncIssues> createState() => _SyncIssuesState();
}

class _SyncIssuesState extends State<_SyncIssues> {
  late final String? _accountId;
  String? _error;
  bool _busy = false;
  TasksStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _accountId = _store.account?.accountId;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || _accountId != _store.account?.accountId) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (error) {
      if (mounted) setState(() => _error = _actionError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discard(TasksIssue issue) async {
    final discarded = await _confirm(
      context,
      title: 'Discard this change?',
      message: 'This removes the saved local change for “${issue.title}”.',
      action: 'Discard change',
      store: _store,
    );
    if (discarded && mounted) await _run(() => _store.discardIssue(issue));
  }

  String _fieldLabel(String field) => switch (field) {
    'title' => 'Title',
    'notes' => 'Notes',
    'due' => 'Scheduled date',
    'status' => 'Completion',
    'position' => 'Position',
    'parent' => 'Parent task',
    _ => field,
  };

  String _fieldValue(BuildContext context, String name, Object? value) {
    if (value == null || value == '') return 'None';
    if (name == 'due') {
      final date = googleScheduledDate(value);
      if (date != null) {
        return MaterialLocalizations.of(context).formatMediumDate(date);
      }
    }
    if (name == 'status') {
      return value == 'completed' || value == true ? 'Completed' : 'Incomplete';
    }
    return value.toString();
  }

  Widget _version(
    BuildContext context,
    TasksConflict conflict, {
    required bool mine,
  }) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: .circular(16),
      ),
      child: Padding(
        padding: const .all(16),
        child: Column(
          crossAxisAlignment: .start,
          spacing: 6,
          children: [
            _TaskSupporting(mine ? 'MY CHANGE' : 'GOOGLE TASKS'),
            for (final field in conflict.fields) ...[
              if (conflict.fields.length > 1)
                _TaskSupporting(_fieldLabel(field.name)),
              Text(
                _fieldValue(
                  context,
                  field.name,
                  mine ? field.mine : field.google,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _AccountGuard(
    store: _store,
    child: ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final conflicts = _store.conflicts;
        final issues = _store.issues;
        return _TasksDialog(
          title: conflicts.isEmpty ? 'Sync issues' : 'Resolve a change',
          fixedBody: true,
          child: ListView.builder(
            shrinkWrap: true,
            primary: false,
            itemCount:
                math.max(1, conflicts.length + issues.length) +
                (_error == null ? 0 : 1),
            itemBuilder: (context, index) {
              if (_error != null) {
                if (index == 0) {
                  return _TaskSupporting(
                    _error!,
                    color: Theme.of(context).colorScheme.error,
                  );
                }
                index--;
              }
              if (conflicts.isEmpty && issues.isEmpty) {
                return const Text('No changes need attention.');
              }
              if (index < conflicts.length) {
                final conflict = conflicts[index];
                return Column(
                  crossAxisAlignment: .stretch,
                  spacing: 12,
                  children: [
                    Text(
                      conflict.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(conflict.message),
                    if (conflict.fields.isNotEmpty) ...[
                      _version(context, conflict, mine: true),
                      _version(context, conflict, mine: false),
                      if (conflict.canKeepMine)
                        const _TaskSupporting('Your other edits will be kept.'),
                    ],
                    OverflowBar(
                      spacing: 8,
                      children: [
                        FilledButton.tonal(
                          onPressed: _busy
                              ? null
                              : () => _run(
                                  () => _store.resolveConflict(
                                    conflict,
                                    keepMine: false,
                                  ),
                                ),
                          child: const Text('Use Google version'),
                        ),
                        if (conflict.canKeepMine)
                          FilledButton(
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    () => _store.resolveConflict(
                                      conflict,
                                      keepMine: true,
                                    ),
                                  ),
                            child: const Text('Keep mine'),
                          ),
                      ],
                    ),
                    const Divider(),
                  ],
                );
              }
              final issue = issues[index - conflicts.length];
              return Column(
                crossAxisAlignment: .stretch,
                spacing: 10,
                children: [
                  Text(
                    issue.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(issue.message),
                  OverflowBar(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: _busy ? null : () => _discard(issue),
                        child: const Text('Discard change'),
                      ),
                      if (issue.ambiguous)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _run(
                                  () =>
                                      openGoogleTasks(issue.task?.webViewLink),
                                ),
                          child: const Text('Open in Google Tasks'),
                        ),
                      FilledButton.tonal(
                        onPressed: _busy
                            ? null
                            : () => _run(() => _store.retryIssue(issue)),
                        child: Text(issue.ambiguous ? 'Try again' : 'Retry'),
                      ),
                    ],
                  ),
                  const Divider(),
                ],
              );
            },
          ),
        );
      },
    ),
  );
}
