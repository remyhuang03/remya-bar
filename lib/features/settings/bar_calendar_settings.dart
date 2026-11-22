import 'package:material_ui/material_ui.dart';
import 'package:remya_client/remya_client.dart';
import 'package:remya_ui/settings_ui.dart';

import '../clock/calendar_integration.dart';
import '../tasks/tasks_settings.dart';
import '../tasks/tasks_store.dart';
import 'bar_preferences.dart';
import 'bar_settings_controller.dart';
import 'bar_settings_tiles.dart';

class BarCalendarSettings extends StatelessWidget {
  const BarCalendarSettings({super.key, required this.controller});

  final BarSettingsController controller;

  @override
  Widget build(BuildContext context) {
    final integration = CalendarIntegration.shared;
    return ListenableBuilder(
      listenable: integration,
      builder: (context, _) => _content(integration),
    );
  }

  Widget _content(CalendarIntegration integration) {
    final preferences = controller.values['calendar'] as Map?;
    final busy = controller.busy('calendar');
    final accountId = integration.account?.accountId;

    Widget choose<T extends Object>(
      String label,
      String field,
      Map<T, String> choices,
    ) => settingTile(
      label,
      control: SettingChoice<T>(
        selected: preferences![field] as T,
        choices: choices,
        onSelected: busy
            ? null
            : (value) => controller.update('calendar', field, value),
      ),
    );

    Widget toggle(String label, String field) => settingSwitch(
      label,
      null,
      preferences![field] as bool,
      busy ? null : (value) => controller.update('calendar', field, value),
    );

    return Column(
      crossAxisAlignment: .stretch,
      spacing: 16,
      children: [
        _CalendarConnection(
          client: controller.client,
          integration: integration,
        ),
        if (preferences != null) ...[
          if (accountId != null && integration.calendars.isNotEmpty)
            SettingsGroup(
              title: 'Calendars',
              children: [
                for (final calendar in integration.calendars)
                  settingSwitch(
                    calendar.name,
                    null,
                    barCalendarVisible(
                      preferences,
                      accountId,
                      calendar.id,
                      calendar.selected,
                    ),
                    busy
                        ? null
                        : (visible) {
                            if (accountId == integration.account?.accountId) {
                              _setVisible(accountId, calendar.id, visible);
                            }
                          },
                    leading: _CalendarDot(color: calendar.color),
                  ),
              ],
            ),
          SettingsGroup(
            title: 'View',
            children: [
              choose('Default view', 'default-view', const {
                'month': 'Month',
                'week': 'Week',
                'remember': 'Remember last',
              }),
              choose('Week starts on', 'week-start', const {
                'system': 'System',
                'monday': 'Monday',
                'sunday': 'Sunday',
              }),
              toggle('Show week numbers', 'show-week-numbers'),
              toggle('Show seconds', 'show-seconds'),
            ],
          ),
          SettingsGroup(
            title: 'Agenda',
            children: [
              choose('Agenda range', 'agenda-range', const {
                7: '7 days',
                14: '14 days',
                30: '30 days',
              }),
              toggle('Show declined events', 'show-declined'),
              toggle('Fold finished events', 'fold-finished'),
            ],
          ),
        ],
      ],
    );
  }

  void _setVisible(String accountId, String id, bool visible) {
    final preferences = controller.values['calendar'] as Map;
    Set<String> overrides(String key) =>
        preferences['calendar-account'] == accountId
        ? Set<String>.from(preferences[key] as List)
        : {};
    final shown = overrides('shown-calendars');
    final hidden = overrides('hidden-calendars');
    if (visible) {
      shown.add(id);
      hidden.remove(id);
    } else {
      hidden.add(id);
      shown.remove(id);
    }
    controller.write('calendar', {
      ...preferences,
      'calendar-account': accountId,
      'shown-calendars': shown.toList(),
      'hidden-calendars': hidden.toList(),
    });
  }
}

class _CalendarConnection extends StatefulWidget {
  const _CalendarConnection({required this.client, required this.integration});

  final SettingsClient client;
  final CalendarIntegration integration;

  @override
  State<_CalendarConnection> createState() => _CalendarConnectionState();
}

class _CalendarConnectionState extends State<_CalendarConnection> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<GoogleAccountStatus> Function() request) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await request();
    } on Object catch (error) {
      _error = barSettingsError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect(String accountId) async {
    if (await confirmGoogleDisconnect(context, TasksStore.shared) &&
        mounted &&
        accountId == widget.integration.account?.accountId) {
      await _run(widget.client.disconnectGoogleAccount);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.integration.account;
    final accountId = status?.accountId;
    final pending = status?.pending == true;
    final authorized = status?.calendar == true;
    final expired = widget.integration.authRequired;
    return SettingsGroup(
      title: 'Google account',
      children: [
        settingTile(
          status?.email ?? 'Google Calendar',
          leading: Image.asset(
            'assets/icons/google.png',
            width: 20,
            height: 20,
            excludeFromSemantics: true,
          ),
          detail: switch (status) {
            null =>
              widget.integration.accountRead
                  ? 'Status unavailable'
                  : 'Checking the Google connection…',
            _ when pending => 'Continue in your browser',
            _ when !status.configured =>
              'Google sign-in is unavailable on this installation',
            _ when expired => 'Google sign-in expired',
            _ when authorized => 'Google Calendar is connected',
            _ => 'Allow Remya to view your Google Calendar events',
          },
          control: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (status?.configured == true &&
                  !pending &&
                  (!authorized || expired))
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(widget.client.connectGoogleCalendar),
                  child: Text(
                    expired ? 'Reconnect' : 'Connect Google Calendar',
                  ),
                ),
              if (pending)
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(widget.client.cancelGoogleAuthorization),
                  child: const Text('Cancel sign-in'),
                ),
              if (accountId != null && !pending)
                OutlinedButton(
                  onPressed: _busy ? null : () => _disconnect(accountId),
                  child: const Text('Disconnect'),
                ),
            ],
          ),
        ),
        if ((_error ?? widget.integration.accountError) case final error?)
          settingTile(error),
      ],
    );
  }
}

class _CalendarDot extends StatelessWidget {
  const _CalendarDot({required this.color});

  final String color;

  @override
  Widget build(BuildContext context) {
    final rgb = color.startsWith('#') && color.length == 7
        ? int.tryParse(color.substring(1), radix: 16)
        : null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: rgb == null
            ? Theme.of(context).colorScheme.primary
            : Color(0xff000000 | rgb),
        shape: .circle,
      ),
      child: const SizedBox.square(dimension: 12),
    );
  }
}
