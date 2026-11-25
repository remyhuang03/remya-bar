import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';

import '../settings/bar_settings_tiles.dart';
import 'tasks_integration.dart';
import 'tasks_preferences.dart';
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
        final busy = settings.busy(tasksClockPreferenceKey);
        final lists = store.lists;
        final visible = preferences.visibleListsFor(accountId);
        final lastSync = store.lastSync;
        final local = MaterialLocalizations.of(context);

        void update(String field, Object value) =>
            settings.update(tasksClockPreferenceKey, field, value);
        Widget toggle(
          String title,
          String field,
          bool value, {
          String? detail,
        }) => settingSwitch(
          title,
          detail,
          value,
          busy ? null : (next) => update(field, next),
        );
        Widget choose(
          String title,
          int selected,
          Map<int, String> choices,
          ValueChanged<int> onSelected,
        ) => settingTile(
          title,
          control: SettingChoice<int>(
            selected: selected,
            choices: choices,
            onSelected: busy ? null : onSelected,
          ),
        );
        return Column(
          crossAxisAlignment: .stretch,
          spacing: 16,
          children: [
            if (settings.error(tasksClockPreferenceKey) case final error?)
              SettingsErrorCard(
                message: error,
                actionLabel: 'Reload',
                onRetry: busy
                    ? null
                    : () => settings.reloadKey(tasksClockPreferenceKey),
              ),
            SettingsGroup(
              title: 'Google account',
              children: [
                settingTile(
                  status?.email ?? 'Google Tasks',
                  leading: Image.asset(
                    'assets/icons/google.png',
                    width: 20,
                    height: 20,
                    excludeFromSemantics: true,
                  ),
                  detail: switch (status) {
                    null => 'Checking the Google connection…',
                    _ when connecting => 'Continue in your browser',
                    _ when !status.configured =>
                      'Google sign-in is unavailable on this installation',
                    _ when connected && store.state != .authRequired =>
                      'Google Tasks can sync with this account.',
                    _ => 'Allow Remya to view tasks and update their completion status.',
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
                      if (accountId != null)
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
                                      () async {
                                        await store.disconnect();
                                      },
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
                if (lastSync != null)
                  settingTile(
                    'Last synced',
                    detail:
                        '${local.formatMediumDate(lastSync)} · '
                        '${local.formatTimeOfDay(TimeOfDay.fromDateTime(lastSync))}',
                  ),
              ],
            ),
            if (settings.values[tasksClockPreferenceKey]
                case final Map raw) ...[
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
                                tasksClockPreferenceKey,
                              );
                              final selected = await showDialog<List<String>>(
                                context: context,
                                builder: (_) => _VisibleLists(
                                  entries: {
                                    for (final row in lists) row.id: row.title,
                                  },
                                  selected: visible,
                                ),
                              );
                              if (selected == null ||
                                  store.account?.accountId != accountId) {
                                return;
                              }
                              await settings.write(tasksClockPreferenceKey, {
                                ...raw,
                                'visible-lists': selected,
                                'visible-lists-account': selected.isEmpty
                                    ? ''
                                    : accountId,
                              }, revision: revision);
                            },
                      child: Text(
                        visible.isEmpty
                            ? 'All lists'
                            : '${visible.length} selected',
                      ),
                    ),
                  ),
                  choose('Upcoming range', preferences.upcomingDays, const {
                    3: '3 days',
                    7: '7 days',
                    14: '14 days',
                  }, (value) => update('upcoming-days', value)),
                  toggle(
                    'Show assigned tasks',
                    'show-assigned',
                    preferences.showAssigned,
                    detail: 'Assigned tasks are read-only in Remya Bar',
                  ),
                ],
              ),
              SettingsGroup(
                title: 'Working on',
                children: [
                  toggle(
                    'Working on',
                    'working-on-enabled',
                    preferences.workingOnEnabled,
                    detail: 'On this device only',
                  ),
                  if (preferences.workingOnEnabled)
                    choose(
                      'Task limit',
                      preferences.workingOnLimit,
                      const {1: '1', 2: '2', 3: '3'},
                      (value) {
                        if (value < store.workingOnIds.length) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Remove tasks from Working on first.',
                              ),
                            ),
                          );
                        } else {
                          update('working-on-limit', value);
                        }
                      },
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
  final count = store.pendingCount;
  final action = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Disconnect Google account?'),
      content: Text(
        count == 0
            ? 'This removes Google access for Remya Apps on this account.'
            : 'This removes Google access for Remya Apps. You have task completions waiting to sync.',
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

class _VisibleLists extends StatefulWidget {
  const _VisibleLists({required this.entries, required this.selected});

  final Map<String, String> entries;
  final List<String> selected;

  @override
  State<_VisibleLists> createState() => _VisibleListsState();
}

class _VisibleListsState extends State<_VisibleLists> {
  late final _selected = widget.selected.isEmpty
      ? widget.entries.keys.toSet()
      : widget.selected.where(widget.entries.containsKey).toSet();
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
              : () => Navigator.pop(
                  context,
                  _selected.length == widget.entries.length
                      ? <String>[]
                      : _selected.toList(),
                ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
