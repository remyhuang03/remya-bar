import 'package:flutter/physics.dart';
import 'package:material_ui/material_ui.dart';

const notificationSpatialDuration = Duration(milliseconds: 350);
final notificationSpatialCurve = _NotificationSpring();

class _NotificationSpring extends Curve {
  final _spring = SpringSimulation(
    SpringDescription.withDampingRatio(mass: 1, stiffness: 700, ratio: .9),
    0,
    1,
    0,
  );

  @override
  double transformInternal(double t) => _spring
      .x(t * notificationSpatialDuration.inMilliseconds / 1000)
      .clamp(0.0, 1.0);
}

/// The trailing split control shared by notification rows and group headers.
class NotificationRowControls extends StatelessWidget {
  const NotificationRowControls({
    super.key,
    required this.expanded,
    required this.onToggle,
    required this.onDismiss,
    required this.showDismiss,
    this.hitHeight = 40,
    this.count,
    this.dismissLabel = 'Dismiss',
  });

  final bool expanded;
  final VoidCallback? onToggle;
  final VoidCallback onDismiss;
  final bool showDismiss;
  final double hitHeight;
  final int? count;
  final String dismissLabel;

  @override
  Widget build(BuildContext context) {
    const outer = Radius.circular(12);
    const inner = Radius.circular(4);
    final colors = Theme.of(context).colorScheme;
    final foreground = colors.onSecondaryContainer;

    Widget segment(
      String label,
      VoidCallback onPressed,
      Widget icon, {
      required BorderRadius radius,
      bool counted = false,
    }) => GestureDetector(
      behavior: .opaque,
      excludeFromSemantics: true,
      onTap: onPressed,
      child: SizedBox(
        height: hitHeight,
        child: Center(
          widthFactor: 1,
          child: IconButton(
            tooltip: label,
            onPressed: onPressed,
            icon: icon,
            style: IconButton.styleFrom(
              foregroundColor: foreground,
              backgroundColor: colors.secondaryContainer,
              minimumSize: Size(counted ? 40 : 32, 24),
              padding: counted ? const .symmetric(horizontal: 8) : .zero,
              visualDensity: .standard,
              tapTargetSize: .shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: radius),
            ),
          ),
        ),
      ),
    );

    final arrow = AnimatedRotation(
      turns: expanded ? .5 : 0,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : notificationSpatialDuration,
      curve: notificationSpatialCurve,
      child: const Icon(Icons.keyboard_arrow_down, size: 16),
    );
    return Row(
      mainAxisSize: .min,
      spacing: 2,
      children: [
        if (showDismiss)
          segment(
            dismissLabel,
            onDismiss,
            const Icon(Icons.close_rounded, size: 16),
            radius: .horizontal(
              left: outer,
              right: onToggle == null ? outer : inner,
            ),
          ),
        if (onToggle case final toggle?)
          segment(
            expanded ? 'Collapse' : 'Expand',
            toggle,
            count == null
                ? arrow
                : Row(
                    mainAxisSize: .min,
                    spacing: 2,
                    children: [
                      Text(
                        '$count',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: foreground,
                          fontSize: 12,
                          height: 16 / 12,
                        ),
                      ),
                      arrow,
                    ],
                  ),
            radius: .horizontal(
              left: showDismiss ? inner : outer,
              right: outer,
            ),
            counted: count != null,
          ),
      ],
    );
  }
}
