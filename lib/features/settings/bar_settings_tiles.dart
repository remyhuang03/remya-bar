import 'dart:async';

import 'package:flutter/services.dart';
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

/// A compact number entry with step buttons. Typed values commit on Enter or
/// when focus leaves; out-of-range values clamp, and invalid text reverts.
/// Button presses commit after a short pause so repeated steps write once.
class SettingNumberField extends StatefulWidget {
  const SettingNumberField({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.suffix,
    this.onPreview,
  });

  final int value;
  final int min;
  final int max;
  final String? suffix;
  final ValueChanged<int>? onChanged;

  /// Reports the uncommitted value while stepping.
  final ValueChanged<int?>? onPreview;

  @override
  State<SettingNumberField> createState() => _SettingNumberFieldState();
}

class _SettingNumberFieldState extends State<SettingNumberField> {
  late final _text = TextEditingController(text: '${widget.value}');
  final _focus = FocusNode();
  Timer? _commit;
  int? _pending;
  // The last written value, shown until the saved value reads back.
  int? _sent;

  int get _shown => _pending ?? _sent ?? widget.value;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _submit(_text.text);
    });
  }

  @override
  void didUpdateWidget(SettingNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) _sent = null;
    if (!_focus.hasFocus) _text.text = '$_shown';
  }

  @override
  void dispose() {
    _commit?.cancel();
    if (_pending case final value?) widget.onChanged?.call(value);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _write(int value) {
    _commit?.cancel();
    final changed = value != (_sent ?? widget.value);
    setState(() {
      _pending = null;
      if (changed) _sent = value;
    });
    widget.onPreview?.call(null);
    _text.text = '$value';
    if (changed) widget.onChanged?.call(value);
  }

  void _submit(String text) {
    final parsed = int.tryParse(text.trim());
    if (parsed == null) {
      _text.text = '$_shown';
      return;
    }
    _write(parsed.clamp(widget.min, widget.max));
  }

  void _step(int delta) {
    final next = (_shown + delta).clamp(widget.min, widget.max);
    setState(() => _pending = next);
    widget.onPreview?.call(next);
    _text.text = '$next';
    _commit?.cancel();
    _commit = Timer(const Duration(milliseconds: 600), () => _write(next));
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      shape: const StadiumBorder(),
      child: Row(
        mainAxisSize: .min,
        children: [
          IconButton(
            tooltip: 'Decrease',
            onPressed: enabled && _shown > widget.min ? () => _step(-1) : null,
            icon: const Icon(Icons.remove_rounded),
          ),
          SizedBox(
            width: widget.suffix == null ? 44 : 60,
            child: TextField(
              controller: _text,
              focusNode: _focus,
              enabled: enabled,
              textAlign: .center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              // A one- or two-digit field has nothing worth a context menu.
              contextMenuBuilder: null,
              style: Theme.of(context).textTheme.titleMedium,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                suffixText: widget.suffix,
              ),
              onSubmitted: _submit,
            ),
          ),
          IconButton(
            tooltip: 'Increase',
            onPressed: enabled && _shown < widget.max ? () => _step(1) : null,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}

/// A numeric setting: a stepper for exact values beside the label, and a
/// full-width slider below for quick, coarse changes. Writes once per gesture.
class SettingSliderTile extends StatefulWidget {
  const SettingSliderTile({
    super.key,
    required this.title,
    required this.detail,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.suffix = '%',
  });

  final String title;
  final String detail;
  final int value;
  final int min;
  final int max;
  final String suffix;
  final ValueChanged<int>? onChanged;

  @override
  State<SettingSliderTile> createState() => _SettingSliderTileState();
}

class _SettingSliderTileState extends State<SettingSliderTile> {
  int? _drag;

  @override
  Widget build(BuildContext context) {
    final value = (_drag ?? widget.value).clamp(widget.min, widget.max);
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final onChanged = widget.onChanged;
    String label(int v) => '$v${widget.suffix}';
    return Padding(
      key: ValueKey(widget.title),
      padding: const .fromLTRB(20, 18, 20, 10),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 8,
        children: [
          Row(
            spacing: 16,
            children: [
              Expanded(
                child: SettingLabel(widget.title, description: widget.detail),
              ),
              SettingNumberField(
                value: widget.value,
                min: widget.min,
                max: widget.max,
                suffix: widget.suffix,
                onChanged: onChanged,
                onPreview: (next) => setState(() => _drag = next),
              ),
            ],
          ),
          Row(
            children: [
              Text(label(widget.min), style: text.labelSmall),
              Expanded(
                child: Slider(
                  // ignore: deprecated_member_use
                  year2023: false,
                  value: value.toDouble(),
                  min: widget.min.toDouble(),
                  max: widget.max.toDouble(),
                  divisions: widget.max - widget.min,
                  label: label(value),
                  semanticFormatterCallback: (v) => label(v.round()),
                  onChanged: onChanged == null
                      ? null
                      : (next) => setState(() => _drag = next.round()),
                  onChangeEnd: onChanged == null
                      ? null
                      : (next) {
                          setState(() => _drag = null);
                          if (next.round() != widget.value) {
                            onChanged(next.round());
                          }
                        },
                ),
              ),
              Text(
                label(widget.max),
                style: text.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
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
