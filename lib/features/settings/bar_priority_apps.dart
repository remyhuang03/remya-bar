import 'package:material_ui/material_ui.dart';
import 'package:remya_client/remya_client.dart';
import 'package:remya_ui/settings_ui.dart';

import 'bar_settings_controller.dart';
import 'bar_settings_tiles.dart';

/// Priority app list with an installed-app picker for adding entries.
class BarPriorityApps extends StatelessWidget {
  const BarPriorityApps({
    super.key,
    required this.apps,
    required this.client,
    required this.onChanged,
  });

  final List<Map> apps;
  final SettingsClient client;
  final ValueChanged<List<Map>>? onChanged;

  @override
  Widget build(BuildContext context) => settingsRows([
    settingTile(
      'Priority apps',
      detail: 'Apps whose notifications show during Do Not Disturb.',
      control: SettingsButton(
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
        label: 'Add app',
      ),
    ),
    if (apps.isEmpty) settingTile('No priority apps'),
    for (final app in apps)
      settingTile(
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
