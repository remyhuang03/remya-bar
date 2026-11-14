import 'package:material_ui/material_ui.dart';
import 'package:remya_client/remya_client.dart';
import 'package:remya_ui/settings_ui.dart';

import '../ai_usage/ai_quota_ring.dart';
import '../ai_usage/ai_usage_data.dart';
import 'bar_pill_layout.dart';
import 'bar_preference_models.dart';
import 'bar_settings_controller.dart';

const _pageKeys = {
  'layout': ['layout', 'clock-seconds', 'folded-apps', 'keyboard-preview'],
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
      for (final key in _pageKeys[id]!)
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
    final folded = controller.values['folded-apps'] as List?;
    final preview = controller.values['keyboard-preview'] as bool?;
    final layoutBusy = controller.busy('layout');
    void setLayout(BarLayout next) => controller.write('layout', next.toJson());
    return [
      if (layout != null) ...[
        const SettingsSectionTitle('Pills'),
        SettingsSurface(
          child: BarPillLayoutEditor(
            layout: layout,
            showSeconds: seconds ?? true,
            onChanged: layoutBusy ? null : setLayout,
          ),
        ),
        _PillOptions(
          layout: layout,
          showSeconds: seconds,
          onSeconds: controller.busy('clock-seconds')
              ? null
              : (value) => controller.write('clock-seconds', value),
          onLayout: layoutBusy ? null : setLayout,
        ),
      ],
      if (folded != null)
        SettingsGroup(
          title: 'App tray',
          children: [
            _row(
              'Folded apps',
              detail:
                  'Folded apps are hidden from the bar. Fold an app from its '
                  'tray menu, and pin it here to show it again.',
            ),
            if (folded.isEmpty)
              _row('No folded apps')
            else
              for (final id in [...folded.cast<String>()]..sort())
                _row(
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
        ),
      if (preview != null)
        SettingsGroup(
          title: 'On-screen keyboard',
          children: [
            _switch(
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

  List<Widget> _osd() {
    final osd = _map('osd');
    if (osd == null) return const [];
    Widget slider(
      String field,
      String title,
      String detail,
      int min,
      int max,
    ) => _SliderTile(
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
    ) => _switch(title, detail, value[field] as bool, _edit<bool>(key, field));
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
                  'notifications still show; history keeps everything.',
            ),
            _row(
              'Popup duration',
              detail:
                  'How long popups stay when the sender does not set a '
                  'duration. Critical notifications stay until closed.',
              control: _Choice<int>(
                selected: notifications['popup-duration'] as int,
                choices: {
                  for (final seconds in const [3, 5, 8, 10, 15, 30])
                    seconds: '$seconds seconds',
                },
                onSelected: _edit<int>('notifications', 'popup-duration'),
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
              _TimeTile(
                title: 'Start time',
                detail: '24-hour time, such as 22:00.',
                value: quiet['start'] as String,
                onChanged: _edit<String>('quiet-schedule', 'start'),
              ),
              _TimeTile(
                title: 'End time',
                detail:
                    '24-hour time; earlier than the start ends on the '
                    'next day.',
                value: quiet['end'] as String,
                onChanged: _edit<String>('quiet-schedule', 'end'),
              ),
              _row(
                'Repeat',
                detail: 'Days on which the schedule starts.',
                control: _Choice<String>(
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
            _PriorityApps(
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
          title: 'Shown in Remya Bar',
          trailing: Text('${pinned.length} of 3'),
          children: [
            if (pinned.isEmpty)
              _row(
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
          _row(
            'Quota metric',
            detail: 'Show remaining or used quota',
            control: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Remaining')),
                ButtonSegment(value: true, label: Text('Used')),
              ],
              selected: {ring['show-used'] as bool},
              onSelectionChanged: busy
                  ? null
                  : (values) =>
                        controller.update('ai-ring', 'show-used', values.first),
            ),
          ),
          _row(
            'Quota rings',
            detail: 'Which window sits on the outer ring',
            control: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: '5h-outer', label: Text('Outer 5h')),
                ButtonSegment(value: '5h-inner', label: Text('Outer 1w')),
              ],
              selected: {ring['ring-order'] as String},
              onSelectionChanged: busy
                  ? null
                  : (values) => controller.update(
                      'ai-ring',
                      'ring-order',
                      values.first,
                    ),
            ),
          ),
        ],
      ),
      SettingsGroup(
        title: 'Alerts',
        children: [
          _SliderTile(
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
          'Usage comes from CodexBar. Track providers in Remya Settings.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ];
  }
}

Widget _row(String title, {String? detail, Widget? control, Widget? leading}) {
  final label = SettingLabel(title, description: detail);
  return SettingRow(
    id: title,
    label: leading == null
        ? label
        : Row(
            mainAxisSize: .min,
            spacing: 16,
            children: [
              leading,
              Flexible(child: label),
            ],
          ),
    control: control,
  );
}

Widget _switch(
  String title,
  String? detail,
  bool value,
  ValueChanged<bool>? onChanged, {
  Widget? leading,
}) => _row(
  title,
  detail: detail,
  leading: leading,
  control: Switch(value: value, onChanged: onChanged),
);

/// Options of visible pills; options of hidden pills are omitted.
class _PillOptions extends StatelessWidget {
  const _PillOptions({
    required this.layout,
    required this.showSeconds,
    required this.onSeconds,
    required this.onLayout,
  });

  final BarLayout layout;
  final bool? showSeconds;
  final ValueChanged<bool>? onSeconds;
  final ValueChanged<BarLayout>? onLayout;

  @override
  Widget build(BuildContext context) {
    final hidden = layout.hidden;
    Widget sample(String pill) => BarPillSample(
      id: pill,
      layout: layout,
      showSeconds: showSeconds ?? true,
    );
    Widget toggle(
      String pill,
      String title,
      bool value,
      ValueChanged<bool>? on,
    ) => _switch(title, barPillNames[pill], value, on, leading: sample(pill));
    final rows = [
      if (!hidden.contains('clock') && showSeconds != null)
        toggle('clock', 'Show seconds', showSeconds!, onSeconds),
      if (!hidden.contains('workspaces'))
        _row(
          'Workspaces shown',
          detail: barPillNames['workspaces'],
          leading: sample('workspaces'),
          control: _Choice<int>(
            selected: layout.workspaceCount,
            choices: {
              for (var count = 1; count <= 10; count++) count: '$count',
            },
            onSelected: onLayout == null
                ? null
                : (count) => onLayout!(layout.copyWith(workspaceCount: count)),
          ),
        ),
      if (!hidden.contains('resources'))
        SettingRow(
          id: 'Shown metrics',
          label: Column(
            crossAxisAlignment: .start,
            spacing: 12,
            children: [
              Row(
                mainAxisSize: .min,
                spacing: 16,
                children: [
                  sample('resources'),
                  Flexible(
                    child: SettingLabel(
                      'Shown metrics',
                      description: barPillNames['resources'],
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final id in barResourceIds)
                    FilterChip(
                      label: Text(barResourceNames[id]!),
                      selected: layout.resources.contains(id),
                      // At least one metric stays; hide the pill to remove it.
                      onSelected:
                          onLayout == null ||
                              layout.resources.length == 1 &&
                                  layout.resources.contains(id)
                          ? null
                          : (selected) => onLayout!(
                              layout.copyWith(
                                resources: [
                                  for (final metric in barResourceIds)
                                    if (metric == id
                                        ? selected
                                        : layout.resources.contains(metric))
                                      metric,
                                ],
                              ),
                            ),
                    ),
                ],
              ),
            ],
          ),
        ),
      if (!hidden.contains('media'))
        toggle(
          'media',
          'Enable marquee (experimental, performance degrade)',
          layout.mediaMarquee,
          onLayout == null
              ? null
              : (value) => onLayout!(layout.copyWith(mediaMarquee: value)),
        ),
      if (!hidden.contains('window'))
        toggle(
          'window',
          'Show app name',
          layout.windowAppName,
          onLayout == null
              ? null
              : (value) => onLayout!(layout.copyWith(windowAppName: value)),
        ),
    ];
    return rows.isEmpty
        ? const SizedBox.shrink()
        : SettingsGroup(title: 'Pill options', children: rows);
  }
}

class _Choice<T extends Object> extends StatelessWidget {
  const _Choice({
    required this.selected,
    required this.choices,
    required this.onSelected,
  });

  final T selected;
  final Map<T, String> choices;
  final ValueChanged<T>? onSelected;

  @override
  Widget build(BuildContext context) => DropdownMenu<T>(
    key: ValueKey(selected),
    width: 160,
    enabled: onSelected != null,
    initialSelection: selected,
    dropdownMenuEntries: [
      for (final MapEntry(:key, :value) in {
        ...choices,
        // A valid stored value outside the offered choices stays visible.
        if (!choices.containsKey(selected)) selected: '$selected',
      }.entries)
        DropdownMenuEntry(value: key, label: value),
    ],
    onSelected: (value) {
      if (value != null && value != selected) onSelected?.call(value);
    },
  );
}

/// Shows the dragged value and writes once on release.
class _SliderTile extends StatefulWidget {
  const _SliderTile({
    super.key,
    required this.title,
    required this.detail,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String title;
  final String detail;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int>? onChanged;

  @override
  State<_SliderTile> createState() => _SliderTileState();
}

class _SliderTileState extends State<_SliderTile> {
  int? _drag;

  @override
  Widget build(BuildContext context) {
    final value = _drag ?? widget.value;
    return _row(
      widget.title,
      detail: widget.detail,
      control: SizedBox(
        width: 280,
        child: Row(
          children: [
            Expanded(
              child: Slider(
                value: value.clamp(widget.min, widget.max).toDouble(),
                min: widget.min.toDouble(),
                max: widget.max.toDouble(),
                divisions: widget.max - widget.min,
                label: '$value%',
                semanticFormatterCallback: (value) => '${value.round()}%',
                onChanged: widget.onChanged == null
                    ? null
                    : (next) => setState(() => _drag = next.round()),
                onChangeEnd: widget.onChanged == null
                    ? null
                    : (next) {
                        setState(() => _drag = null);
                        if (next.round() != widget.value) {
                          widget.onChanged!(next.round());
                        }
                      },
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                '$value%',
                textAlign: .end,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.title,
    required this.detail,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String detail;
  final String value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final [hours, minutes] = value.split(':').map(int.parse).toList();
    return _row(
      title,
      detail: detail,
      control: OutlinedButton.icon(
        icon: const Icon(Icons.schedule_rounded),
        label: Text(value),
        onPressed: onChanged == null
            ? null
            : () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(hour: hours, minute: minutes),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(alwaysUse24HourFormat: true),
                    child: child!,
                  ),
                );
                if (picked == null) return;
                String two(int value) => '$value'.padLeft(2, '0');
                onChanged?.call('${two(picked.hour)}:${two(picked.minute)}');
              },
      ),
    );
  }
}

class _PriorityApps extends StatelessWidget {
  const _PriorityApps({
    required this.apps,
    required this.client,
    required this.onChanged,
  });

  final List<Map> apps;
  final SettingsClient client;
  final ValueChanged<List<Map>>? onChanged;

  @override
  Widget build(BuildContext context) => settingsRows([
    _row(
      'Priority apps',
      detail: 'Apps whose notifications show during Do Not Disturb.',
      control: FilledButton.tonalIcon(
        onPressed: onChanged == null
            ? null
            : () async {
                final app = await showDialog<Map>(
                  context: context,
                  builder: (context) => _AppPicker(
                    client: client,
                    exclude: {for (final app in apps) app['id']},
                  ),
                );
                if (app != null) onChanged?.call([...apps, app]);
              },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add app'),
      ),
    ),
    if (apps.isEmpty) _row('No priority apps'),
    for (final app in apps)
      _row(
        app['name'] as String,
        detail: app['id'] as String,
        control: IconButton(
          tooltip: 'Remove',
          onPressed: onChanged == null
              ? null
              : () => onChanged!([
                  for (final other in apps)
                    if (other['id'] != app['id']) other,
                ]),
          icon: const Icon(Icons.remove_circle_outline_rounded),
        ),
      ),
  ]);
}

/// Installed desktop applications, filtered by name.
class _AppPicker extends StatefulWidget {
  const _AppPicker({required this.client, required this.exclude});

  final SettingsClient client;
  final Set<Object?> exclude;

  @override
  State<_AppPicker> createState() => _AppPickerState();
}

class _AppPickerState extends State<_AppPicker> {
  late final Future<List<Map<String, String>>> _apps = _read();
  String _query = '';

  Future<List<Map<String, String>>> _read() async {
    final data = await widget.client.readInstalledApplications();
    final apps = <String, Map<String, String>>{};
    for (final app in data['applications'] as List? ?? const []) {
      if (app case {'id': final String id, 'name': final String name}) {
        // Notifications name their desktop entry without the suffix.
        final entry = id.endsWith('.desktop')
            ? id.substring(0, id.length - 8)
            : id;
        if (!widget.exclude.contains(entry)) {
          apps[entry] = {'id': entry, 'name': name};
        }
      }
    }
    return apps.values.toList()..sort(
      (a, b) => a['name']!.toLowerCase().compareTo(b['name']!.toLowerCase()),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add priority app'),
    content: SizedBox(
      width: 420,
      height: 420,
      child: Column(
        spacing: 12,
        children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Search apps',
            ),
            onChanged: (value) => setState(() => _query = value.toLowerCase()),
          ),
          Expanded(
            child: FutureBuilder(
              future: _apps,
              builder: (context, snapshot) {
                if (snapshot.error case final error?) {
                  return Row(
                    spacing: 8,
                    children: [
                      const Icon(Icons.error_outline_rounded),
                      Expanded(child: Text(barSettingsError(error))),
                    ],
                  );
                }
                final apps = snapshot.data;
                if (apps == null) {
                  return const Align(
                    alignment: .topCenter,
                    child: RemyaLoadingBar(),
                  );
                }
                final shown = [
                  for (final app in apps)
                    if (app['name']!.toLowerCase().contains(_query) ||
                        app['id']!.toLowerCase().contains(_query))
                      app,
                ];
                if (shown.isEmpty) {
                  return const Center(child: Text('No matching apps'));
                }
                return ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (context, index) => ListTile(
                    title: Text(shown[index]['name']!),
                    subtitle: Text(shown[index]['id']!),
                    onTap: () => Navigator.pop(context, shown[index]),
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
    ],
  );
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
