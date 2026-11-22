import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';

import '../settings/bar_settings_tiles.dart';
import 'tasks_integration.dart';
import 'tasks_links.dart';
import 'tasks_store.dart';

class TasksSettings extends StatelessWidget {
  const TasksSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final integration = TasksIntegration.shared;
    final settings = integration.settings;
    final store = integration.store;
    return ListenableBuilder(
      listenable: Listenable.merge([settings, store]),
      builder: (context, _) {
        final preferences = integration.preferences;
        final status = store.account;
        final accountId = status?.accountId;
        final connecting = status?.pending == true;
        final connected = status?.tasks == true;
        final busy = settings.busy('tasks');
        final lists = store.lists.where((list) => !list.pending).toList();
        final targetLabel = preferences.defaultList == '@default'
            ? 'Google default'
            : lists
                      .where((list) => list.id == preferences.defaultList)
                      .firstOrNull
                      ?.title ??
                  'Choose a list';
        void update(String field, Object value) =>
            settings.update('tasks', field, value);
        Widget toggle(String title, String field, bool value) => settingSwitch(
          title,
          null,
          value,
          busy ? null : (next) => update(field, next),
        );
        Widget choose<T extends Object>(
          String title,
          String field,
          T selected,
          Map<T, String> choices,
        ) => settingTile(
          title,
          control: SettingChoice<T>(
            selected: selected,
            choices: choices,
            onSelected: busy ? null : (next) => update(field, next),
          ),
        );
        return Column(
          crossAxisAlignment: .stretch,
          spacing: 16,
          children: [
            if (settings.error('tasks') case final error?)
              SettingsErrorCard(
                message: error,
                actionLabel: 'Reload',
                onRetry: busy ? null : () => settings.reloadKey('tasks'),
              ),
            SettingsGroup(
              title: 'Connection',
              trailing: TextButton.icon(
                onPressed: () => _runTaskAction(
                  context,
                  'Couldn’t open Google Tasks',
                  openGoogleTasks,
                ),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open in Google Tasks'),
              ),
              children: [
                settingTile(
                  status?.email ?? 'Google Tasks',
                  detail: switch (status) {
                    null => 'Checking the Google connection…',
                    _ when connecting => 'Continue in your browser',
                    _ when !status.configured =>
                      'Google sign-in is unavailable on this installation',
                    _ when connected && store.state != .authRequired =>
                      'Google Tasks can sync with this account.',
                    _ => 'Allow Remya to view, edit and delete Google Tasks.',
                  },
                  control: Wrap(
                    spacing: 8,
                    children: [
                      if (status?.configured == true &&
                          !connecting &&
                          (!connected || store.state == .authRequired))
                        FilledButton(
                          onPressed: () => _runTaskAction(
                            context,
                            'Couldn’t update the Google connection',
                            store.connect,
                          ),
                          child: Text(
                            connected || store.state == .authRequired
                                ? 'Reconnect'
                                : 'Connect Google Tasks',
                          ),
                        ),
                      if (connecting)
                        OutlinedButton(
                          onPressed: () => _runTaskAction(
                            context,
                            'Couldn’t cancel Google sign-in',
                            store.cancelAuthorization,
                          ),
                          child: const Text('Cancel sign-in'),
                        ),
                      if (accountId != null &&
                          (connected || store.pendingCount > 0))
                        OutlinedButton(
                          onPressed: connecting
                              ? null
                              : () async {
                                  if (!await confirmGoogleDisconnect(
                                    context,
                                    store,
                                  )) {
                                    return;
                                  }
                                  if (context.mounted) {
                                    await _runTaskAction(
                                      context,
                                      'Couldn’t update the Google connection',
                                      store.disconnect,
                                    );
                                  }
                                },
                          child: const Text('Disconnect'),
                        ),
                    ],
                  ),
                ),
                if ((status?.error ?? store.error) case final error?)
                  settingTile(error),
              ],
            ),
            if (settings.values['tasks'] case final Map raw) ...[
              SettingsGroup(
                title: 'Lists and view',
                children: [
                  settingTile(
                    'Visible lists',
                    control: OutlinedButton(
                      onPressed: busy || accountId == null || lists.isEmpty
                          ? null
                          : () async {
                              final revision = settings.preferences.revision(
                                'tasks',
                              );
                              final selected = await showDialog<List<String>>(
                                context: context,
                                builder: (_) => _VisibleLists(
                                  entries: {
                                    for (final row in lists) row.id: row.title,
                                  },
                                  selected: preferences.visibleLists,
                                ),
                              );
                              if (selected == null ||
                                  store.account?.accountId != accountId) {
                                return;
                              }
                              await settings.write('tasks', {
                                ...raw,
                                'visible-lists': selected,
                                'visible-lists-account': selected.isEmpty
                                    ? ''
                                    : accountId,
                              }, revision: revision);
                            },
                      child: Text(
                        preferences.visibleLists.isEmpty
                            ? 'All lists'
                            : '${preferences.visibleLists.length} selected',
                      ),
                    ),
                  ),
                  settingTile(
                    'Default list for new tasks',
                    control: OutlinedButton(
                      onPressed: busy || accountId == null || lists.isEmpty
                          ? null
                          : () async {
                              final revision = settings.preferences.revision(
                                'tasks',
                              );
                              final picked = await showDialog<String>(
                                context: context,
                                builder: (_) => _DefaultList(
                                  entries: {
                                    '@default': 'Google default',
                                    for (final row in lists) row.id: row.title,
                                  },
                                ),
                              );
                              if (picked != null && context.mounted) {
                                await _runTaskAction(
                                  context,
                                  'Couldn’t save the default list',
                                  () => integration.setDefaultList(
                                    picked,
                                    accountId,
                                    revision: revision,
                                  ),
                                );
                              }
                            },
                      child: Text(targetLabel),
                    ),
                  ),
                  choose(
                    'Initial view',
                    'initial-view',
                    preferences.initialView,
                    const {
                      'today': 'Today',
                      'upcoming': 'Upcoming',
                      'all': 'All',
                    },
                  ),
                  choose('Single-list sort', 'sort', preferences.sort, const {
                    'manual': 'My order',
                    'date': 'Scheduled date',
                  }),
                  toggle(
                    'Expand completed tasks',
                    'completed-expanded',
                    preferences.completedExpanded,
                  ),
                  toggle(
                    'Show assigned tasks',
                    'show-assigned',
                    preferences.showAssigned,
                  ),
                  toggle(
                    'Include unscheduled tasks in Today',
                    'today-includes-unscheduled',
                    preferences.todayIncludesUnscheduled,
                  ),
                ],
              ),
              SettingsGroup(
                title: 'Placement',
                children: [
                  toggle('Show in sidebar', 'sidebar', preferences.sidebar),
                  toggle(
                    'Show in notifications',
                    'notifications',
                    preferences.notifications,
                  ),
                  choose(
                    'Preview rows',
                    'preview-rows',
                    preferences.previewRows,
                    const {3: '3', 5: '5', 8: '8'},
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

Future<void> _runTaskAction(
  BuildContext context,
  String title,
  Future<void> Function() action,
) async {
  try {
    await action();
  } on Object {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// Save or explicitly discard pending operations before revoking Google access.
Future<bool> confirmGoogleDisconnect(
  BuildContext context,
  TasksStore store,
) async {
  final accountId = store.account?.accountId;
  final count = store.pendingCount + store.draftCount;
  final action = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Disconnect Google account?'),
      content: Text(
        count == 0
            ? 'This removes Google access for Remya Apps on this account.'
            : 'This removes Google access for Remya Apps. You have tasks with local changes that have not synced.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(count == 0 ? 'Cancel' : 'Keep syncing'),
        ),
        if (count > 0)
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Discard and disconnect'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context, 'keep'),
          child: Text(
            count == 0 ? 'Disconnect' : 'Keep local changes and disconnect',
          ),
        ),
      ],
    ),
  );
  if (!context.mounted ||
      action == null ||
      accountId != store.account?.accountId) {
    return false;
  }
  if (action == 'discard') {
    try {
      await store.discardPendingChanges();
    } on Object {
      if (!context.mounted) return false;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Couldn’t discard local changes'),
          content: const Text(
            'Wait for the current sync to finish, then try again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return false;
    }
  }
  return true;
}

class _DefaultList extends StatelessWidget {
  const _DefaultList({required this.entries});

  final Map<String, String> entries;

  @override
  Widget build(BuildContext context) {
    final rows = entries.entries.toList();
    return AlertDialog(
      title: const Text('Default list for new tasks'),
      content: SizedBox(
        width: 360,
        height: 320,
        child: ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) => ListTile(
            title: Text(rows[index].value),
            onTap: () => Navigator.pop(context, rows[index].key),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _VisibleLists extends StatefulWidget {
  const _VisibleLists({required this.entries, required this.selected});

  final Map<String, String> entries;
  final List<String> selected;

  @override
  State<_VisibleLists> createState() => _VisibleListsState();
}

class _VisibleListsState extends State<_VisibleLists> {
  late final _selected = widget.selected
      .where(widget.entries.containsKey)
      .toSet();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final rows = widget.entries.entries
        .where((row) => row.value.toLowerCase().contains(_query))
        .toList();
    return AlertDialog(
      title: const Text('Visible lists'),
      content: SizedBox(
        width: 360,
        height: 350,
        child: Column(
          spacing: 8,
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'Search lists'),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('No matching lists'))
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        return CheckboxListTile(
                          title: Text(row.value),
                          value: _selected.contains(row.key),
                          onChanged: (selected) => setState(
                            () => selected == true
                                ? _selected.add(row.key)
                                : _selected.remove(row.key),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, <String>[]),
          child: const Text('Show all'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, _selected.toList()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
