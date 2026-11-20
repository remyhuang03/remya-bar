part of 'tasks_block.dart';

class _TasksStatus {
  const _TasksStatus(
    this.store, {
    required this.onConnect,
    required this.onRetry,
    required this.onReview,
  });

  final TasksStore store;
  final VoidCallback? onConnect;
  final VoidCallback onRetry;
  final VoidCallback onReview;

  bool get syncing => store.state == .syncing || store.state == .loading;

  Widget prompt() => switch (store.state) {
    .disconnected => _TaskPrompt(
      icon: 'state-task',
      title: 'Connect Google Tasks',
      message:
          'Remya can view, edit and delete tasks with your Google account.',
      action: 'Connect Google Tasks',
      onPressed: onConnect,
    ),
    .authRequired => _TaskPrompt(
      icon: 'state-offline',
      title: 'Reconnect to sync',
      message: store.pendingCount > 0
          ? 'Your changes are saved on this device.'
          : 'Reconnect Google Tasks to get your lists.',
      action: 'Reconnect',
      onPressed: onConnect,
    ),
    .error || .offline => _TaskPrompt(
      icon: 'state-error',
      title: 'Couldn’t sync your tasks',
      message: store.error ?? 'Try again when you are ready.',
      action: 'Retry',
      onPressed: onRetry,
    ),
    _ => const _TaskPrompt(
      icon: 'state-sync',
      title: 'Getting your tasks',
      message: 'Loading your lists for the first time.',
      loading: true,
    ),
  };

  Widget? banner() {
    final pending = store.pendingCount;
    final waiting =
        '$pending ${pending == 1 ? 'change' : 'changes'} waiting to sync';
    return switch (store.state) {
      .offline => _TaskBanner(
        icon: 'offline',
        title: 'Offline',
        detail: waiting,
        action: 'Retry',
        onPressed: onRetry,
      ),
      .authRequired => _TaskBanner(
        icon: 'offline',
        title: 'Reconnect to sync',
        detail: pending > 0 ? waiting : null,
        action: 'Reconnect',
        onPressed: onConnect,
      ),
      .error => _TaskBanner(
        title: 'Couldn’t sync',
        detail: pending > 0
            ? 'Your changes are saved on this device.'
            : store.error,
        action: store.issues.isEmpty ? 'Retry' : 'Review',
        onPressed: store.issues.isEmpty ? onRetry : onReview,
      ),
      .conflict => _TaskBanner(
        title: 'This task changed elsewhere.',
        action: 'Resolve',
        onPressed: onReview,
      ),
      _ => null,
    };
  }

  String label(BuildContext context) {
    final last = store.lastSync;
    if (syncing) return 'Syncing…';
    if (last == null) return 'Waiting to sync';
    final local = MaterialLocalizations.of(context);
    final time = local.formatTimeOfDay(TimeOfDay.fromDateTime(last.toLocal()));
    final recent = DateTime.now().difference(last) < const Duration(minutes: 1);
    if (store.state == .ready && recent) return 'Synced just now';
    final date = DateUtils.isSameDay(last.toLocal(), DateTime.now())
        ? 'today'
        : local.formatShortDate(last.toLocal());
    return 'Last synced $date at $time';
  }
}

Widget _emptyTasks(
  _View view, {
  required String query,
  required bool completed,
  required VoidCallback onClearSearch,
  required VoidCallback onShowCompleted,
}) {
  if (query.isNotEmpty) {
    return _TaskPrompt(
      inline: true,
      icon: 'state-empty',
      title: 'No matching tasks',
      action: 'Clear search',
      onPressed: onClearSearch,
    );
  }
  if (completed) {
    return _TaskPrompt(
      inline: true,
      icon: 'state-task',
      title: 'Everything is complete',
      message: 'Your completed tasks are still available.',
      action: 'View completed',
      onPressed: onShowCompleted,
    );
  }
  return _TaskPrompt(
    inline: true,
    icon: 'state-empty',
    title: switch (view) {
      .today => 'No tasks for today',
      .upcoming => 'No upcoming tasks',
      .all => 'No tasks yet',
    },
    message: 'Add a task or switch views.',
  );
}

class _TaskPrompt extends StatelessWidget {
  const _TaskPrompt({
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.onPressed,
    this.loading = false,
    this.inline = false,
  });

  final String icon;
  final String title;
  final String? message;
  final String? action;
  final VoidCallback? onPressed;
  final bool loading;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (inline) {
      return Semantics(
        liveRegion: true,
        child: Card(
          margin: .zero,
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHigh,
          shape: const RoundedRectangleBorder(
            borderRadius: .all(.circular(20)),
          ),
          child: Padding(
            padding: const .all(16),
            child: Row(
              spacing: 12,
              children: [
                _TaskIcon(icon, 40),
                Expanded(
                  child: Column(
                    mainAxisSize: .min,
                    crossAxisAlignment: .start,
                    spacing: 4,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      if (message != null) _TaskSupporting(message!),
                      if (action != null)
                        TextButton(onPressed: onPressed, child: Text(action!)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const .symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: .start,
          spacing: 12,
          mainAxisSize: .min,
          children: [
            _TaskIcon(icon, 40),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: .w600),
            ),
            if (message != null) Text(message!),
            if (action != null)
              FilledButton(onPressed: onPressed, child: Text(action!)),
            if (loading)
              for (final height in [40.0, 32.0, 40.0])
                ExcludeSemantics(
                  child: Container(
                    width: double.infinity,
                    height: height,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: .circular(12),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _TaskBanner extends StatelessWidget {
  const _TaskBanner({
    this.icon,
    required this.title,
    this.detail,
    required this.action,
    required this.onPressed,
  });

  final String? icon;
  final String title;
  final String? detail;
  final String action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: .circular(16),
        ),
        child: Padding(
          padding: const .fromLTRB(12, 4, 6, 4),
          child: Row(
            spacing: 8,
            children: [
              if (icon != null) _TaskIcon(icon!, 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(color: colors.onSecondaryContainer),
                    ),
                    if (detail != null)
                      _TaskSupporting(
                        detail!,
                        color: colors.onSecondaryContainer,
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onPressed,
                style: TextButton.styleFrom(
                  foregroundColor: colors.onSecondaryContainer,
                ),
                child: Text(action),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
