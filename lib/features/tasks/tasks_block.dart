import 'dart:async';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../clock/calendar_dates.dart';
import '../clock/clock_card_controls.dart';
import '../google/google_links.dart';
import 'tasks_links.dart';
import 'tasks_preferences.dart';
import 'tasks_store.dart';

part 'tasks_rows.dart';

class TasksBlock extends StatefulWidget {
  const TasksBlock({
    super.key,
    required this.store,
    required this.preferences,
    required this.onSettings,
    required this.now,
    this.scrollable = true,
  });

  final TasksStore store;
  final TasksPreferences preferences;
  final VoidCallback onSettings;
  final DateTime now;
  final bool scrollable;

  @override
  State<TasksBlock> createState() => _TasksBlockState();
}

class _TasksBlockState extends State<TasksBlock> {
  final _rowsFocus = FocusScopeNode(traversalEdgeBehavior: .parentScope);
  final _scroll = ScrollController();
  Timer? _noticeTimer;
  String? _notice;
  String? _noticeAccount;
  bool _fade = false;
  bool _watching = false;

  TasksStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _watch();
  }

  @override
  void didUpdateWidget(TasksBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != _store) {
      if (_watching) oldWidget.store.setCardOpen(this, false);
      _watching = false;
      _watch();
    }
    if (oldWidget.scrollable != widget.scrollable) _fade = false;
  }

  void _watch() {
    final store = _store;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _store != store) return;
      _watching = true;
      store.setCardOpen(this, true);
    });
  }

  @override
  void dispose() {
    if (_watching) _store.setCardOpen(this, false);
    _scroll.dispose();
    _rowsFocus.dispose();
    _noticeTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.hasClients) _updateFade(_scroll.position);
  }

  void _updateFade(ScrollMetrics metrics) {
    final fade = metrics.extentAfter > 1;
    if (_fade != fade) setState(() => _fade = fade);
  }

  Future<void> _act(Future<void> Function() action, String fallback) async {
    final store = _store;
    final account = store.account?.accountId;
    try {
      await action();
    } on Object catch (error) {
      if (!mounted || _store != store || store.account?.accountId != account) {
        return;
      }
      _noticeTimer?.cancel();
      setState(() {
        _noticeAccount = account;
        _notice = error is TasksEditException ? error.message : fallback;
      });
      _noticeTimer = Timer(const Duration(seconds: 5), () {
        setState(() => _notice = null);
      });
    }
  }

  void _home() => unawaited(
    _act(
      () => openGoogleTasks(email: _store.account?.email),
      'Couldn’t open Google Tasks.',
    ),
  );

  void _refresh() => unawaited(_act(_store.retry, 'Couldn’t sync your tasks.'));

  void _connect() =>
      unawaited(_act(_store.connect, 'Couldn’t open Google sign-in.'));

  Widget? _banner() {
    final pending = _store.pendingCount;
    final signInPending = _store.account?.pending == true;
    return switch (_store.state) {
      .offline => ClockCardStatusBanner(
        message: pending == 0
            ? 'Offline'
            : 'Offline · $pending ${pending == 1 ? 'change' : 'changes'} waiting to sync',
        icon: Icons.cloud_off_outlined,
        action: 'Retry',
        onAction: _refresh,
      ),
      .authRequired => ClockCardStatusBanner(
        message: 'Reconnect to sync your changes',
        icon: Icons.lock_outline,
        action: 'Retry',
        onAction: signInPending ? null : _connect,
      ),
      .error => ClockCardStatusBanner(
        message: pending == 0
            ? 'Couldn’t sync'
            : 'Couldn’t sync. Your changes are saved on this device.',
        icon: Icons.error_outline,
        action: 'Retry',
        onAction: _refresh,
      ),
      _ => null,
    };
  }

  List<Widget> _items() {
    final store = _store;
    if (store.state == .loading && store.lastSync == null) {
      return [const _TaskSkeleton()];
    }
    if (store.state == .disconnected) {
      return [
        const Text('Connect Google Tasks to see your tasks.'),
        Align(
          alignment: .centerLeft,
          child: FilledButton.tonal(
            onPressed: store.account?.configured == true ? _connect : null,
            child: const Text('Connect Google Tasks'),
          ),
        ),
      ];
    }

    final preferences = widget.preferences;
    final today = calendarDay(widget.now);
    final visibleLists = preferences.visibleListsFor(store.account?.accountId);
    final groups = <_TaskGroup, List<GoogleTask>>{
      for (final group in _TaskGroup.values) group: [],
    };
    final workingOn = store.workingOnIds;
    for (final task in store.tasks) {
      if (task.deleted ||
          task.hidden ||
          (task.completed && !task.completionUndoable) ||
          (task.assigned && !preferences.showAssigned) ||
          (visibleLists.isNotEmpty && !visibleLists.contains(task.listId))) {
        continue;
      }
      final date = task.scheduled;
      final days = date == null
          ? null
          : calendarDay(date).difference(today).inDays;
      if (preferences.workingOnEnabled && workingOn.contains(task.id)) {
        groups[_TaskGroup.workingOn]!.add(task);
      } else if (days == 0) {
        groups[_TaskGroup.today]!.add(task);
      } else if (days == null ||
          (days > 0 && days <= preferences.upcomingDays)) {
        groups[_TaskGroup.upcoming]!.add(task);
      }
    }

    final upcoming = groups[_TaskGroup.upcoming]!;
    final order = {
      for (final (index, task) in upcoming.indexed) task.key: index,
    };
    upcoming.sort((a, b) {
      final due = switch ((a.scheduled, b.scheduled)) {
        (final a?, final b?) => a.compareTo(b),
        (null, null) => 0,
        (null, _) => 1,
        (_, null) => -1,
      };
      return due != 0 ? due : order[a.key]!.compareTo(order[b.key]!);
    });

    final nonEmpty = groups.entries.where((group) => group.value.isNotEmpty);
    final local = MaterialLocalizations.of(context);
    final email = store.account?.email;
    final theme = Theme.of(context);
    return [
      for (final (index, MapEntry(key: group, value: rows))
          in nonEmpty.indexed) ...[
        if (index > 0) const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(
            group.label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: .w500,
              height: 18 / 13,
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final (index, task) in rows.indexed)
          _TaskRow(
            key: ValueKey(task.key),
            task: task,
            dueLabel: task.scheduled == null
                ? null
                : local.formatFullDate(task.scheduled!),
            dateLabel: group == _TaskGroup.upcoming && task.scheduled != null
                ? _upcomingLabel(task.scheduled!, today)
                : null,
            first: index == 0,
            last: index == rows.length - 1,
            workingOn: group == _TaskGroup.workingOn,
            showBookmark: preferences.workingOnEnabled,
            onBookmark: preferences.workingOnEnabled && !task.completed
                ? () => unawaited(
                    _act(
                      () => store.toggleWorkingOn(task),
                      'Couldn’t update Working on.',
                    ),
                  )
                : null,
            onComplete:
                !task.assigned && (!task.completed || task.completionUndoable)
                ? () => unawaited(
                    _act(
                      () => store.setCompleted(task, !task.completed),
                      'Couldn’t update this task.',
                    ),
                  )
                : null,
            onOpen: googleBrowserLink(task.webViewLink) == null
                ? null
                : () => unawaited(
                    _act(
                      () => openGoogleTask(task, email: email),
                      'Couldn’t open this task.',
                    ),
                  ),
            onSource:
                !task.assigned || googleBrowserLink(task.sourceLink) == null
                ? null
                : () => unawaited(
                    _act(
                      () => openTaskSource(task, email: email),
                      'Couldn’t open the source.',
                    ),
                  ),
          ),
      ],
    ];
  }

  Widget _list(List<Widget> items) {
    if (items.isEmpty) {
      if (_store.lastSync == null &&
          switch (_store.state) {
            .offline || .authRequired || .error => true,
            _ => false,
          }) {
        return const SizedBox.shrink();
      }
      return Center(
        child: Padding(
          padding: const .symmetric(vertical: 24),
          child: Text(
            'No tasks',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    if (!widget.scrollable) {
      return Column(crossAxisAlignment: .stretch, children: items);
    }
    final keys = {for (final (index, item) in items.indexed) ?item.key: index};
    return ClockCardScrollFade(
      bottom: _fade,
      child: ClipRect(
        clipper: const _TaskListClip(),
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) {
            if (notification.depth == 0) _updateFade(notification.metrics);
            return false;
          },
          child: ListView.builder(
            controller: _scroll,
            padding: const .only(bottom: 4),
            clipBehavior: .none,
            itemCount: items.length,
            findChildIndexCallback: (key) => keys[key],
            itemBuilder: (_, index) => items[index],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _store,
    builder: (context, _) {
      final banner = _banner();
      final colors = Theme.of(context).colorScheme;
      final notice = _noticeAccount == _store.account?.accountId
          ? _notice
          : null;
      final items = FocusScope(node: _rowsFocus, child: _list(_items()));
      final content = Column(
        mainAxisSize: widget.scrollable ? .max : .min,
        crossAxisAlignment: .stretch,
        spacing: 16,
        children: [
          ClockCardHeader(
            title: 'Tasks',
            newTooltip: 'New task',
            googleLabel: 'Open in Google Tasks',
            onNew: _home,
            onGoogle: _home,
            onRefresh: _refresh,
            onSettings: widget.onSettings,
          ),
          ?banner,
          if (notice != null)
            Semantics(
              liveRegion: true,
              child: Text(notice, style: TextStyle(color: colors.error)),
            ),
          if (widget.scrollable) Expanded(child: items) else items,
          if (_store.undoTask != null)
            Semantics(
              liveRegion: true,
              child: Material(
                color: colors.inverseSurface,
                borderRadius: .circular(16),
                child: Padding(
                  padding: const .symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Task completed',
                          style: TextStyle(color: colors.onInverseSurface),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: colors.inversePrimary,
                        ),
                        onPressed: () => unawaited(
                          _act(
                            _store.undoCompletion,
                            'Couldn’t undo completion.',
                          ),
                        ),
                        child: const Text('Undo'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyN): _home,
          const SingleActivator(LogicalKeyboardKey.keyG): _home,
          const SingleActivator(LogicalKeyboardKey.keyR): _refresh,
        },
        child: Focus(autofocus: true, skipTraversal: true, child: content),
      );
    },
  );
}

class _TaskListClip extends CustomClipper<Rect> {
  const _TaskListClip();

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-4, 0, size.width + 4, size.height);

  @override
  bool shouldReclip(_TaskListClip oldClipper) => false;
}

enum _TaskGroup {
  workingOn('Working on'),
  today('Today'),
  upcoming('Upcoming');

  const _TaskGroup(this.label);

  final String label;
}

String _upcomingLabel(DateTime due, DateTime today) {
  final offset = calendarDay(due).difference(today).inDays;
  return DateFormat(offset <= 3 ? 'EEE' : 'EEE d', 'en_US').format(due);
}

class _TaskSkeleton extends StatelessWidget {
  const _TaskSkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHigh;
    return Semantics(
      label: 'Loading tasks',
      child: Column(
        spacing: 2,
        children: [
          for (var i = 0; i < 3; i++)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: connectedClockRowRadius(
                    first: i == 0,
                    last: i == 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
