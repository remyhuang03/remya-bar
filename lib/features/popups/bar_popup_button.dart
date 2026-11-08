import 'package:material_ui/material_ui.dart';

class BarPopupButton extends StatelessWidget {
  const BarPopupButton(
    this.icon,
    this.label,
    this.onPressed, {
    super.key,
    this.selected = false,
  });

  final Widget icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      icon: icon,
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        fixedSize: const WidgetStatePropertyAll(Size.square(40)),
        minimumSize: const WidgetStatePropertyAll(Size.square(40)),
        tapTargetSize: .shrinkWrap,
        backgroundColor: selected ? .all(colors.primary) : null,
        foregroundColor: .resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? null
              : selected
              ? colors.onPrimary
              : colors.onSurfaceVariant,
        ),
        overlayColor: .resolveWith((states) {
          final color = selected ? colors.onPrimary : colors.onSurfaceVariant;
          if (states.contains(WidgetState.pressed)) {
            return color.withValues(alpha: .16);
          }
          if (states.contains(WidgetState.hovered)) {
            return color.withValues(alpha: .08);
          }
          return null;
        }),
        shape: .resolveWith(
          (states) => RoundedRectangleBorder(
            borderRadius: .circular(
              states.contains(WidgetState.pressed)
                  ? 10
                  : selected
                  ? 14
                  : 20,
            ),
          ),
        ),
      ),
    );
  }
}
