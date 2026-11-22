import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';

import '../ai_usage/ai_quota_ring.dart';
import '../ai_usage/ai_usage_data.dart';
import '../weather/weather_settings.dart';
import 'bar_pill_layout.dart';
import 'bar_preference_models.dart';
import 'bar_priority_apps.dart';
import 'bar_settings_controller.dart';
import 'bar_settings_tiles.dart';

const _pageKeys = {
  'layout': [
    'position',
    'layout',
    'clock-seconds',
    'resources',
    'folded-apps',
    'keyboard-preview',
  ],
  'osd': ['osd'],
  'notifications': [
    'notifications',
    'quiet-schedule',
    'priority-notifications',
  ],
  'ai-ring': ['ai-ring'],
};

/// Whether a value of page [id] is still loading without an error.
bool barSettingsPageLoading(BarSettingsController controller, String id) =>
    (_pageKeys[id] ?? const []).any(
      (key) =>
          !controller.values.containsKey(key) && controller.error(key) == null,
    );

/// The content of one registered page of the Bar settings window.
class BarSettingsPage extends StatelessWidget {
  const BarSettingsPage({
    super.key,
    required this.id,
    required this.controller,
  });

  final String id;
  final BarSettingsController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: [
      for (final key in _pageKeys[id] ?? const <String>[])
        if (controller.error(key) case final message?)
          SettingsErrorCard(
            message: message,
            actionLabel: 'Reload',
            onRetry: controller.busy(key)
                ? null
                : () => controller.reloadKey(key),
          ),
      ...switch (id) {
        'layout' => _layout(context),
        'osd' => _osd(),
        'weather' => const [WeatherSettings()],
        'notifications' => _notifications(context),
        _ => _aiRing(context),
      },
    ],
  );

  Map? _map(String key) => controller.values[key] as Map?;

  /// Null while [key] is being saved; edits wait for the readback.
  ValueChanged<T>? _edit<T>(String key, String field) => controller.busy(key)
      ? null
      : (value) => controller.update(key, field, value as Object);

  List<Widget> _layout(BuildContext context) {
    final json = controller.values['layout'];
    final layout = json == null ? null : BarLayout.fromJson(json);
    final seconds = controller.values['clock-seconds'] as bool?;
    final resources = controller.values['resources'] == null
        ? null
        : BarResourcePreferences.fromJson(controller.values['resources']);
    final folded = controller.values['folded-apps'] as List?;
    final preview = controller.values['keyboard-preview'] as bool?;
    final position = controller.values['position'] as String?;
    final layoutBusy = controller.busy('layout');
    void setLayout(BarLayout next) => controller.write('layout', next.toJson());
    return [
      if (layout != null)
        BarPillLayoutEditor(
          layout: layout,
          bottom: position == 'bottom',
          onChanged: layoutBusy ? null : setLayout,
          onBottom: position == null || controller.busy('position')
              ? null
              : (bottom) =>
                    controller.write('position', bottom ? 'bottom' : 'top'),
          options: (id) => _pillOptions(
            id,
            layout: layout,
            seconds: seconds,
            resources: resources,
            onLayout: layoutBusy ? null : setLayout,
            folded: folded,
          ),
        ),
      if (preview != null)
        SettingsGroup(
          title: 'On-screen keyboard',
          children: [
            settingSwitch(
              'Show touch key previews',
              'Show a character preview when pressing a key on a '
                  'touchscreen.',
              preview,
              controller.busy('keyboard-preview')
                  ? null
                  : (value) => controller.write('keyboard-preview', value),
            ),
          ],
        ),
    ];
  }

  /// Rows of pill [id]'s own options in its layout panel.
  List<Widget> _pillOptions(
    String id, {
    required BarLayout layout,
    required bool? seconds,
    required BarResourcePreferences? resources,
    required ValueChanged<BarLayout>? onLayout,
    required List? folded,
  }) => switch (id) {
    'clock' when seconds != null => [
      settingSwitch(
        'Show seconds',
        null,
        seconds,
        controller.busy('clock-seconds')
            ? null
            : (value) => controller.write('clock-seconds', value),
      ),
    ],
    'workspaces' => [
      settingTile(
        'Workspaces shown',
        control: SettingNumberField(
          value: layout.workspaceCount,
          min: 1,
          max: 10,
          onChanged: onLayout == null
              ? null
              : (count) => onLayout(layout.copyWith(workspaceCount: count)),
        ),
      ),
    ],
    'resources' => [
      SettingRow(
        id: 'Shown metrics',
        label: Column(
          crossAxisAlignment: .start,
          spacing: 12,
          children: [
            const SettingLabel('Shown metrics'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final metric in barResourceIds)
                  FilterChip(
                    label: Text(barResourceNames[metric]!),
                    selected: layout.resources.contains(metric),
                    // At least one metric stays; hide the pill to remove it.
                    onSelected:
                        onLayout == null ||
                            layout.resources.length == 1 &&
                                layout.resources.contains(metric)
                        ? null
                        : (selected) => onLayout(
                            layout.copyWith(
                              resources: [
                                for (final other in barResourceIds)
                                  if (other == metric
                                      ? selected
                                      : layout.resources.contains(other))
                                    other,
                              ],
                            ),
                          ),
                  ),
              ],
            ),
          ],
        ),
      ),
      if (resources != null) ...[
        settingTile(
          'Refresh rate',
          detail: 'How often usage updates',
          control: SettingChoice<int>(
            selected: resources.refreshIntervalMs,
            choices: const {
              500: '0.5 s',
              1000: '1 s',
              2000: '2 s',
              5000: '5 s',
              10000: '10 s',
            },
            onSelected: controller.busy('resources')
                ? null
                : (value) => controller.write(
                    'resources',
                    resources.copyWith(refreshIntervalMs: value).toJson(),
                  ),
          ),
        ),
        settingTile(
          'Graph history',
          detail: 'Time range of the System card graphs',
          control: SettingChoice<int>(
            selected: resources.timeRangeSeconds,
            choices: const {
              30: '30 s',
              60: '1 min',
              120: '2 min',
              300: '5 min',
              600: '10 min',
            },
            onSelected: controller.busy('resources')
                ? null
                : (value) => controller.write(
                    'resources',
                    resources.copyWith(timeRangeSeconds: value).toJson(),
                  ),
          ),
        ),
      ],
    ],
    'media' => [
      settingSwitch(
        'Scroll long titles',
        'Experimental; uses more power',
        layout.mediaMarquee,
        onLayout == null
            ? null
            : (value) => onLayout(layout.copyWith(mediaMarquee: value)),
      ),
    ],
    'window' => [
      settingSwitch(
        'Show app name',
        null,
        layout.windowAppName,
        onLayout == null
            ? null
            : (value) => onLayout(layout.copyWith(windowAppName: value)),
      ),
    ],
    'tray' when folded != null => [
      settingTile(
        'Folded apps',
        detail:
            'Folded apps are hidden from the bar. Fold an app from its '
            'tray menu, and pin it here to show it again.',
      ),
      if (folded.isEmpty)
        settingTile('No folded apps')
      else
        for (final id in [...folded.cast<String>()]..sort())
          settingTile(
            id,
            control: FilledButton.tonalIcon(
              onPressed: controller.busy('folded-apps')
                  ? null
                  : () => controller.write('folded-apps', [
                      for (final other in folded)
                        if (other != id) other,
                    ]),
              icon: const Icon(Icons.push_pin_outlined),
              label: const Text('Pin to tray'),
            ),
          ),
    ],
    _ => const [],
  };

  List<Widget> _osd() {
    final osd = _map('osd');
    if (osd == null) return const [];
    Widget slider(
      String field,
      String title,
      String detail,
      int min,
      int max,
    ) => SettingSliderTile(
      key: ValueKey(field),
      title: title,
      detail: detail,
      value: osd[field] as int,
      min: min,
      max: max,
      onChanged: _edit<int>('osd', field),
    );
    return [
      SettingsGroup(
        title: 'Shortcuts',
        children: [
          slider(
            'volume-step',
            'Volume step size',
            'Percentage changed by each volume shortcut step.',
            1,
            25,
          ),
          slider(
            'volume-max',
            'Maximum volume',
            'Highest output volume reachable from the bar. Above 100% boosts '
                'and may distort.',
            100,
            150,
          ),
          slider(
            'brightness-step',
            'Brightness step size',
            'Percentage changed by each brightness or gamma shortcut step.',
            1,
            25,
          ),
          slider(
            'gamma-min',
            'Minimum gamma',
            'Lowest software gamma level reached after hardware brightness '
                'hits its minimum.',
            10,
            90,
          ),
        ],
      ),
    ];
  }

  List<Widget> _notifications(BuildContext context) {
    final notifications = _map('notifications');
    final quiet = _map('quiet-schedule');
    final priority = _map('priority-notifications');
    Widget toggle(
      Map value,
      String key,
      String field,
      String title,
      String detail,
    ) => settingSwitch(
      title,
      detail,
      value[field] as bool,
      _edit<bool>(key, field),
    );
    return [
      if (notifications != null)
        SettingsGroup(
          title: 'Notifications',
          children: [
            toggle(
              notifications,
              'notifications',
              'do-not-disturb',
              'Do not disturb',
              'Hide notification popups and sounds. Critical and priority '
                  'notifications still show.',
            ),
            settingTile(
              'Popup duration',
              detail:
                  'How long popups stay when the sender does not set a '
                  'duration. Critical notifications stay until closed.',
              control: SettingNumberField(
                value: notifications['popup-duration'] as int,
                min: 1,
                max: 600,
                suffix: 's',
                onChanged: _edit<int>('notifications', 'popup-duration'),
              ),
            ),
            settingTile(
              'Popup position',
              detail: 'Which side of the screen shows notification popups.',
              control: SettingChoice<String>(
                selected: notifications['toast-side'] as String? ?? 'left',
                choices: const {'left': 'Left', 'right': 'Right'},
                onSelected: _edit<String>('notifications', 'toast-side'),
              ),
            ),
            toggle(
              notifications,
              'notifications',
              'sounds',
              'Play sounds',
              'Play the sound a notification requests, or the theme\'s '
                  'message sound. Senders can ask for silence.',
            ),
            settingSwitch(
              'Clear all also removes critical notifications',
              'Resident notifications must be dismissed individually.',
              notifications['clear-critical'] as bool? ?? false,
              _edit<bool>('notifications', 'clear-critical'),
            ),
          ],
        ),
      if (quiet != null)
        SettingsGroup(
          title: 'Automatic Do Not Disturb',
          children: [
            toggle(
              quiet,
              'quiet-schedule',
              'enabled',
              'During these times',
              'Turn on Do Not Disturb between the start and end times.',
            ),
            // Schedule details are hidden while the schedule is off.
            if (quiet['enabled'] == true) ...[
              SettingTimeTile(
                title: 'Start time',
                detail: '24-hour time, such as 22:00.',
                value: quiet['start'] as String,
                onChanged: _edit<String>('quiet-schedule', 'start'),
              ),
              SettingTimeTile(
                title: 'End time',
                detail:
                    '24-hour time; earlier than the start ends on the '
                    'next day.',
                value: quiet['end'] as String,
                onChanged: _edit<String>('quiet-schedule', 'end'),
              ),
              settingTile(
                'Repeat',
                detail: 'Days on which the schedule starts.',
                control: SettingChoice<String>(
                  selected: quiet['repeat'] as String,
                  choices: const {
                    'every-day': 'Every day',
                    'weekdays': 'Weekdays',
                    'weekends': 'Weekends',
                  },
                  onSelected: _edit<String>('quiet-schedule', 'repeat'),
                ),
              ),
            ],
            toggle(
              quiet,
              'quiet-schedule',
              'fullscreen',
              'When an app is full screen',
              'Turn on Do Not Disturb while any display shows a full screen '
                  'window.',
            ),
          ],
        ),
      if (priority != null)
        SettingsGroup(
          title: 'Priority notifications',
          children: [
            toggle(
              priority,
              'priority-notifications',
              'calls',
              'Incoming calls',
              'Show call notifications during Do Not Disturb.',
            ),
            BarPriorityApps(
              apps: [for (final Map app in priority['apps'] as List) app],
              client: controller.client,
              onChanged: _edit<List<Map>>('priority-notifications', 'apps'),
            ),
          ],
        ),
    ];
  }

  List<Widget> _aiRing(BuildContext context) {
    final ring = _map('ai-ring');
    if (ring == null) return const [];
    final busy = controller.busy('ai-ring');
    final providers = controller.aiProviders;
    final tracked = {
      for (final row in providers ?? const <Map<String, dynamic>>[])
        if (row['kind'] == 'codexbar' &&
            row['enabled'] == true &&
            row['id'] is String)
          row['id'] as String: (row['name'] as String?) ?? row['id'] as String,
    };
    // Pins of untracked providers stay stored but are not shown.
    final pinned = [
      for (final id in ring['pinned'] as List)
        if (tracked.containsKey(id)) id as String,
    ];
    final others = [
      for (final id in tracked.keys)
        if (!pinned.contains(id)) id,
    ];
    void pin(List<String> next) => controller.update('ai-ring', 'pinned', next);
    return [
      if (controller.aiError case final message?)
        SettingsErrorCard(
          message: message,
          actionLabel: 'Reload',
          onRetry: controller.loadAi,
        ),
      if (providers != null) ...[
        SettingsGroup(
          title: "Shown in Remy'a Bar",
          trailing: Text('${pinned.length} of 3'),
          children: [
            if (pinned.isEmpty)
              settingTile(
                'No providers pinned. The bar shows the first three '
                'tracked providers that report usage.',
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: pinned.length,
                onReorderItem: (from, to) {
                  if (busy) return;
                  final next = [...pinned];
                  next.insert(to, next.removeAt(from));
                  pin(next);
                },
                itemBuilder: (context, i) => _ProviderTile(
                  key: ValueKey('ai-pinned-${pinned[i]}'),
                  id: pinned[i],
                  name: tracked[pinned[i]]!,
                  leading: ReorderableDragStartListener(
                    index: i,
                    enabled: !busy,
                    child: const Icon(Icons.drag_indicator_rounded),
                  ),
                  actions: [
                    if (i > 0)
                      IconButton(
                        tooltip: 'Move up',
                        onPressed: busy
                            ? null
                            : () => pin(
                                [...pinned]
                                  ..insert(i - 1, pinned[i])
                                  ..removeAt(i + 1),
                              ),
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                    IconButton(
                      tooltip: 'Hide from bar',
                      onPressed: busy
                          ? null
                          : () => pin([...pinned]..removeAt(i)),
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (others.isNotEmpty)
          SettingsGroup(
            title: 'Other tracked providers',
            children: [
              for (final id in others)
                _ProviderTile(
                  key: ValueKey('ai-other-$id'),
                  id: id,
                  name: tracked[id]!,
                  subtitle: pinned.length >= 3
                      ? 'Hide a pinned provider to show this one'
                      : null,
                  actions: [
                    if (pinned.length < 3)
                      TextButton.icon(
                        onPressed: busy ? null : () => pin([...pinned, id]),
                        icon: const Icon(Icons.push_pin_outlined),
                        label: const Text('Show in bar'),
                      ),
                  ],
                ),
            ],
          ),
      ],
      SettingsGroup(
        title: 'Bar display',
        children: [
          settingTile(
            'Quota metric',
            detail: 'Show remaining or used quota',
            control: SettingChoice<bool>(
              selected: ring['show-used'] as bool,
              choices: const {false: 'Remaining', true: 'Used'},
              onSelected: busy
                  ? null
                  : (value) => controller.update('ai-ring', 'show-used', value),
            ),
          ),
          settingTile(
            'Quota rings',
            detail: 'Which window sits on the outer ring',
            control: SettingChoice<String>(
              selected: ring['ring-order'] as String,
              choices: const {'5h-outer': 'Outer 5h', '5h-inner': 'Outer 1w'},
              onSelected: busy
                  ? null
                  : (value) =>
                        controller.update('ai-ring', 'ring-order', value),
            ),
          ),
        ],
      ),
      SettingsGroup(
        title: 'Alerts',
        children: [
          SettingSliderTile(
            title: 'Low quota warning',
            detail: 'Warn when a window has this much quota or less left.',
            value: ring['low-percent'] as int,
            min: 1,
            max: 100,
            onChanged: _edit<int>('ai-ring', 'low-percent'),
          ),
        ],
      ),
      Padding(
        padding: const .only(top: 16),
        child: Text(
          "Usage comes from CodexBar. Track providers in Remy'a Settings.",
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ];
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    super.key,
    required this.id,
    required this.name,
    required this.actions,
    this.leading,
    this.subtitle,
  });

  final String id;
  final String name;
  final List<Widget> actions;
  final Widget? leading;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const .symmetric(horizontal: 20, vertical: 4),
    leading: Row(
      mainAxisSize: .min,
      spacing: 12,
      children: [
        ?leading,
        AiProviderLogo(
          AiQuotaProvider({'id': id, 'name': name}, DateTime.now(), 0),
          size: 32,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ],
    ),
    title: Text(name),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: Row(mainAxisSize: .min, children: actions),
  );
}
