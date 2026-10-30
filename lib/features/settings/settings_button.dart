import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

import '../../widgets/bar_tooltip.dart';

class SettingsButton extends StatefulWidget {
  const SettingsButton({super.key, this.onOpen = openRemyaSettings});
  final Future<void> Function() onOpen;

  @override
  State<SettingsButton> createState() => _SettingsButtonState();
}

class _SettingsButtonState extends State<SettingsButton> {
  bool _opening = false;
  String? _error;

  Future<void> _open() async {
    setState(() => _opening = true);
    try {
      await widget.onOpen();
      if (mounted) setState(() => _error = null);
    } catch (failure) {
      debugPrint('Could not open Settings: $failure');
      if (mounted) {
        setState(
          () => _error = failure is FileSystemException
              ? 'Build Settings first'
              : 'Settings unavailable',
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => BarTooltip(
    message: _error ?? 'Settings',
    child: IconButton(
      onPressed: _opening ? null : _open,
      icon: Icon(
        _error == null ? Icons.settings_rounded : Icons.error_outline_rounded,
      ),
      iconSize: 20,
      style: const .new(tapTargetSize: .shrinkWrap),
      padding: .zero,
      constraints: const .tightFor(width: 40, height: 40),
    ),
  );
}
