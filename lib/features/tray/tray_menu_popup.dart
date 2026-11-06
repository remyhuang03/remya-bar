import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'tray_icon.dart';

class TrayMenuPopup extends StatefulWidget {
  const TrayMenuPopup({super.key, required this.data, required this.onAction});
  final Map<String, Object?> data;
  final Future<void> Function(Map<String, Object?>) onAction;

  @override
  State<TrayMenuPopup> createState() => _TrayMenuPopupState();
}

class _TrayMenuPopupState extends State<TrayMenuPopup> {
  bool _busy = false;

  Future<void> _dispatch(String action, [Map<String, Object?>? entry]) async {
    if (_busy && action != 'close') return;
    setState(() => _busy = true);
    try {
      await widget.onAction({
        'action': action,
        'token': widget.data['token'],
        ...?entry,
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final root = data['parent'] == 0;
    final entries = (data['entries'] as List).whereType<Map>().toList();
    final lastDivider = entries.lastIndexWhere(
      (entry) => entry['separator'] == true,
    );
    final destructiveIndex = entries.indexWhere(_isDestructive);
    final foldIndex = lastDivider == -1 ? destructiveIndex : lastDivider;
    final canFold = root && data['canFold'] == true;
    final colors = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: 12,
      fontWeight: .w500,
      color: colors.onSurfaceVariant,
    );
    final fold = _MenuRow(
      label: data['folded'] == true ? 'Pin to tray' : 'Move to overflow',
      icon: data['folded'] == true
          ? const Icon(Icons.push_pin_outlined)
          : const _DrawerIcon(),
      onTap: _busy ? null : () => _dispatch('tray.fold'),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _dispatch('close'),
        if (!root)
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _dispatch('tray.back'),
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: colors.surfaceContainer,
          borderRadius: .circular(16),
          elevation: 2,
          clipBehavior: .antiAlias,
          child: Padding(
            padding: const .all(4),
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .stretch,
              children: [
                if (root)
                  Container(
                    constraints: const BoxConstraints(minHeight: 32),
                    padding: const .symmetric(horizontal: 12, vertical: 5),
                    child: Row(
                      spacing: 8,
                      children: [
                        TrayIcon(data: data['artwork'] as Map, size: 18),
                        Expanded(
                          child: Text(
                            data['title'] as String,
                            style: titleStyle,
                            overflow: .ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  _MenuRow(
                    label: data['title'] as String,
                    icon: const Icon(Icons.chevron_left_rounded),
                    onTap: _busy ? null : () => _dispatch('tray.back'),
                  ),
                const _MenuDivider(),
                if (data['nativeMenu'] == true) ...[
                  _MenuRow(
                    label: 'Open application',
                    icon: const Icon(Icons.open_in_new_rounded),
                    onTap: _busy ? null : () => _dispatch('tray.activate'),
                  ),
                  _MenuRow(
                    label: 'Application menu',
                    icon: const Icon(Icons.more_horiz_rounded),
                    onTap: _busy ? null : () => _dispatch('tray.context'),
                  ),
                ],
                for (final (index, entry) in entries.indexed) ...[
                  if (index == foldIndex && canFold) ...[
                    fold,
                    if (lastDivider == -1) const _MenuDivider(),
                  ],
                  if (entry['separator'] == true)
                    const _MenuDivider()
                  else
                    _applicationRow(entry),
                ],
                if (entries.isEmpty && !root)
                  const _MenuRow(label: 'No menu items'),
                if (canFold && foldIndex == -1) ...[
                  if (entries.isNotEmpty || data['nativeMenu'] == true)
                    const _MenuDivider(),
                  fold,
                ],
                if (data['error'] case final String error)
                  Padding(
                    padding: const .all(12),
                    child: Text(error, style: TextStyle(color: colors.error)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _applicationRow(Map entry) {
    final label = entry['label'] as String;
    final submenu = entry['submenu'] == true;
    final state = entry['toggleState'];
    final destructive = _isDestructive(entry);
    final icon = switch (entry['toggleType']) {
      'radio' => Icon(
        state == 1 ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      ),
      'checkmark' => Icon(switch (state) {
        1 => Icons.check_box_outlined,
        0 => Icons.check_box_outline_blank_rounded,
        _ => Icons.indeterminate_check_box_outlined,
      }),
      (_) when entry['icon'] is Uint8List => Image.memory(
        entry['icon'] as Uint8List,
        width: 18,
        height: 18,
        filterQuality: .medium,
        fit: .contain,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
      _ when destructive => const Icon(Icons.close_rounded),
      _ => null,
    };
    return _MenuRow(
      label: label,
      icon: icon,
      destructive: destructive,
      submenu: submenu,
      onTap: _busy || entry['enabled'] != true
          ? null
          : () => _dispatch(submenu ? 'tray.submenu' : 'tray.menu', {
              'entry': entry['id'],
              'label': label,
            }),
    );
  }
}

final _exitLabel = RegExp(r'^(quit|exit)\b', caseSensitive: false);

bool _isDestructive(Map entry) =>
    entry['iconName'] == 'application-exit' ||
    entry['iconName'] == 'system-log-out' ||
    _exitLabel.hasMatch(entry['label'] as String? ?? '');

class _DrawerIcon extends StatelessWidget {
  const _DrawerIcon();

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DrawerPainter(IconTheme.of(context).color!),
    size: const Size.square(18),
  );
}

class _DrawerPainter extends CustomPainter {
  const _DrawerPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = .round
      ..style = .stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(2, 2, 14, 14),
        const .circular(2),
      ),
      stroke,
    );
    canvas.drawLine(const Offset(2, 9), const Offset(16, 9), stroke);
    canvas.drawLine(const Offset(7, 5.5), const Offset(11, 5.5), stroke);
    canvas.drawLine(const Offset(7, 12.5), const Offset(11, 12.5), stroke);
  }

  @override
  bool shouldRepaint(_DrawerPainter oldDelegate) => oldDelegate.color != color;
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) => Divider(
    indent: 12,
    endIndent: 12,
    height: 9,
    thickness: 1,
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.label,
    this.icon,
    this.onTap,
    this.destructive = false,
    this.submenu = false,
  });

  final String label;
  final Widget? icon;
  final VoidCallback? onTap;
  final bool destructive;
  final bool submenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = destructive
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;
    return TextButton(
      onPressed: onTap,
      style: ButtonStyle(
        alignment: .centerLeft,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
        tapTargetSize: .shrinkWrap,
        visualDensity: .standard,
        shape: .all(RoundedRectangleBorder(borderRadius: .circular(12))),
        textStyle: .all(theme.textTheme.bodySmall?.copyWith(fontSize: 14)),
        foregroundColor: .resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? theme.colorScheme.onSurface.withValues(alpha: .38)
              : color,
        ),
        overlayColor: .resolveWith(
          (states) => color.withValues(
            alpha:
                states.contains(WidgetState.pressed) ||
                    states.contains(WidgetState.focused)
                ? .10
                : .08,
          ),
        ),
      ),
      child: Row(
        spacing: 12,
        children: [
          SizedBox.square(
            dimension: 18,
            child: IconTheme.merge(
              data: const IconThemeData(size: 18),
              child: icon ?? const SizedBox.shrink(),
            ),
          ),
          Expanded(child: Text(label, maxLines: 2, overflow: .ellipsis)),
          if (submenu) const Icon(Icons.chevron_right_rounded, size: 18),
        ],
      ),
    );
  }
}
