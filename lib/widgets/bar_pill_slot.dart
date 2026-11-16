import 'package:material_ui/material_ui.dart';

/// Animates a bar pill appearing, disappearing and changing width.
///
/// A null [child] collapses the slot to zero width while the last pill fades
/// out, so neighbours slide instead of jumping. [leading] adds the gap that
/// separates this pill from an earlier visible pill in its group.
class BarPillSlot extends StatefulWidget {
  const BarPillSlot({super.key, this.child, this.leading = false});

  static const gap = 8.0;
  static const duration = Duration(milliseconds: 350);
  static const curve = Curves.easeInOutCubicEmphasized;

  final Widget? child;
  final bool leading;

  @override
  State<BarPillSlot> createState() => _BarPillSlotState();
}

class _BarPillSlotState extends State<BarPillSlot>
    with SingleTickerProviderStateMixin {
  late Widget? _last = widget.child;
  late final _visibility = AnimationController(
    vsync: this,
    duration: BarPillSlot.duration,
    value: widget.child == null ? 0 : 1,
  )..addStatusListener(_release);
  late final _curved = CurvedAnimation(
    parent: _visibility,
    curve: BarPillSlot.curve,
  );

  // Drop the stale pill once it has fully collapsed.
  void _release(AnimationStatus status) {
    if (status.isDismissed && widget.child == null) {
      setState(() => _last = null);
    }
  }

  @override
  void didUpdateWidget(BarPillSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.child case final child?) {
      _last = child;
      _visibility.forward();
    } else {
      _visibility.reverse();
    }
  }

  @override
  void dispose() {
    _curved.dispose();
    _visibility.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    if (still) _visibility.value = widget.child == null ? 0 : 1;
    final child = _last;
    if (child == null) return const SizedBox.shrink();
    final duration = still ? Duration.zero : BarPillSlot.duration;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: widget.leading ? BarPillSlot.gap : 0),
      duration: duration,
      curve: BarPillSlot.curve,
      builder: (context, gap, child) => AnimatedBuilder(
        animation: _curved,
        builder: (context, child) {
          final t = _curved.value;
          return Padding(
            padding: .only(left: gap * t),
            child: ClipRect(
              child: Align(
                widthFactor: t,
                child: Opacity(
                  opacity: t,
                  child: Transform.scale(scale: .8 + .2 * t, child: child),
                ),
              ),
            ),
          );
        },
        child: child,
      ),
      child: AnimatedSize(
        duration: duration,
        curve: BarPillSlot.curve,
        child: child,
      ),
    );
  }
}
