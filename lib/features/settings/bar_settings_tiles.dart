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

/// A dropdown of labelled choices for one setting value.
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

/// A percentage slider row that shows the dragged value and writes once on release.
class SettingSliderTile extends StatefulWidget {
  const SettingSliderTile({
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
  State<SettingSliderTile> createState() => _SettingSliderTileState();
}

class _SettingSliderTileState extends State<SettingSliderTile> {
  int? _drag;

  @override
  Widget build(BuildContext context) {
    final value = _drag ?? widget.value;
    return settingTile(
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
