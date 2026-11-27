import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';

/// A setting row with an optional description, control and leading widget.
Widget settingTile(
  String title, {
  String? detail,
  Widget? control,
  Widget? leading,
}) {
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

/// A setting row controlled by a switch.
Widget settingSwitch(
  String title,
  String? detail,
  bool value,
  ValueChanged<bool>? onChanged, {
  Widget? leading,
}) => settingTile(
  title,
  detail: detail,
  leading: leading,
  control: Switch(value: value, onChanged: onChanged),
);

/// A labelled choice control for one setting value.
class SettingChoice<T extends Object> extends StatelessWidget {
  const SettingChoice({
    super.key,
    required this.selected,
    required this.choices,
    required this.onSelected,
  });

  final T selected;
  final Map<T, String> choices;
  final ValueChanged<T>? onSelected;

  @override
  Widget build(BuildContext context) => SettingsChoice<T>(
    selected: selected,
    choices: choices,
    onSelected: onSelected,
  );
}

/// A setting row that picks a 24-hour `HH:mm` time.
class SettingTimeTile extends StatelessWidget {
  const SettingTimeTile({
    super.key,
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
    return settingTile(
      title,
      detail: detail,
      control: SettingsButton(
        icon: const Icon(Icons.schedule_rounded),
        label: value,
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
