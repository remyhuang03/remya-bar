import 'dart:async';
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:material_ui/material_ui.dart';

import '../hyprland/hyprland_backend.dart';
import '../popups/bar_popup.dart';
import 'workspace_slot.dart';

const workspaceOverviewKind = 'workspace-overview';
const _slotWidth = 26.0;
const _padding = 3.0;
const _tagWidth = 28.0;
const _resizeDuration = Duration(milliseconds: 280);
const _indicatorDuration = Duration(milliseconds: 250);
final _resizeCurve = _SpatialSpring(
  _resizeDuration,
  stiffness: 380,
  damping: .8,
);
final _indicatorCurve = _SpatialSpring(
  _indicatorDuration,
  stiffness: 800,
  damping: .6,
);

class BarWorkspaces extends StatefulWidget {
  const BarWorkspaces({super.key, this.backend});

  static const maxWidth = 282.0;

  final HyprlandBackend? backend;

  @override
  State<BarWorkspaces> createState() => _BarWorkspacesState();
}

class _BarWorkspacesState extends State<BarWorkspaces> {
  bool _hovered = false;

  Future<void> _overview(HyprlandBackend backend) async {
    final box = context.findRenderObject() as RenderBox;
    final slots = backend.workspaceSlots;
    final workspaces = {
      for (final workspace in backend.allWorkspaces)
        workspace.id: {
          'id': workspace.id,
          'name': workspace.name,
          'owner': workspace.monitorName,
          'count': workspace.windowCount,
          'active': workspace.id == backend.output?.activeWorkspaceId,
        },
      for (final slot in slots)
        if (slot.id != 0 && !backend.allWorkspaces.any((w) => w.id == slot.id))
          slot.id: {
            'id': slot.id,
            'name': slot.name,
            'owner': backend.output!.name,
            'count': 0,
            'active': slot.active,
          },
    };
    final ids = workspaces.keys.toList()..sort();
    try {
      await BarPopup.show(
        kind: workspaceOverviewKind,
        anchor: box.localToGlobal(Offset.zero) & box.size,
        size: const Size(320, 392),
        data: {
          'workspaces': [for (final id in ids) workspaces[id]],
        },
        theme: BarPopupScope.themeOf(context),
      );
    } catch (error) {
      debugPrint('Workspace overview: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final backend = widget.backend;
    if (backend == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: backend,
      builder: (context, _) {
        final output = backend.output;
        if (!backend.connected ||
            backend.error != null ||
            output == null ||
            output.workspaceSlots.isEmpty) {
          return const SizedBox.shrink();
        }
        final special = output.specialWorkspaceId == null
            ? null
            : output.specialWorkspaceName?.replaceFirst('special:', '') ??
                  'Special';
        final named = output.activeWorkspaceId < 0
            ? backend.allWorkspaces
                  .where((item) => item.id == output.activeWorkspaceId)
                  .firstOrNull
                  ?.name
            : null;
        final overlay = backend.superHeld || _hovered ? null : special ?? named;
        final colors = Theme.of(context).colorScheme;
        return MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Listener(
            behavior: .opaque,
            onPointerSignal: (event) {
              if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
                // Claim the wheel so the scrollable bar does not also move.
                GestureBinding.instance.pointerSignalResolver.register(
                  event,
                  (_) => unawaited(
                    backend.scroll(event.scrollDelta.dy > 0 ? 1 : -1),
                  ),
                );
              }
            },
            onPointerDown: (event) {
              if (event.buttons & kBackMouseButton != 0) {
                unawaited(backend.toggleSpecial());
              }
            },
            child: GestureDetector(
              behavior: .opaque,
              onSecondaryTap: () => unawaited(_overview(backend)),
              child: Material(
                color: colors.surfaceContainerHigh,
                shape: const StadiumBorder(),
                child: SizedBox(
                  height: 32,
                  child: Padding(
                    padding: const .symmetric(horizontal: _padding),
                    child: Row(
                      mainAxisSize: .min,
                      children: [
                        if (backend.monitors.length > 1)
                          SizedBox(
                            width: _tagWidth,
                            child: Align(
                              alignment: .centerLeft,
                              child: SizedBox(
                                width: _slotWidth,
                                height: _slotWidth,
                                child: Center(
                                  child: OutputMark(
                                    number: output.outputNumber,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Stack(
                          alignment: .center,
                          children: [
                            AnimatedOpacity(
                              opacity: overlay == null ? 1 : .35,
                              duration: const Duration(milliseconds: 180),
                              child: ImageFiltered(
                                enabled: overlay != null,
                                // Figma layer blur radius 2 ≈ sigma 1.
                                imageFilter: ImageFilter.blur(
                                  sigmaX: 1,
                                  sigmaY: 1,
                                ),
                                child: _WorkspaceSlots(
                                  backend: backend,
                                  output: output,
                                ),
                              ),
                            ),
                            if (overlay != null)
                              IgnorePointer(
                                child: Material(
                                  color: colors.primary,
                                  shape: const StadiumBorder(),
                                  child: ConstrainedBox(
                                    constraints: const .new(maxWidth: 190),
                                    child: Padding(
                                      padding: const .symmetric(
                                        horizontal: 12,
                                        vertical: 3,
                                      ),
                                      child: Text(
                                        overlay,
                                        key: const ValueKey(
                                          'workspace-overlay',
                                        ),
                                        maxLines: 1,
                                        overflow: .ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(color: colors.onPrimary),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WorkspaceSlots extends StatefulWidget {
  const _WorkspaceSlots({required this.backend, required this.output});

  final HyprlandBackend backend;
  final HyprlandMonitor output;

  @override
  State<_WorkspaceSlots> createState() => _WorkspaceSlotsState();
}

class _WorkspaceSlotsState extends State<_WorkspaceSlots> {
  int? _pressed;

  @override
  Widget build(BuildContext context) {
    final backend = widget.backend;
    final output = widget.output;
    final slots = output.workspaceSlots;
    final colors = Theme.of(context).colorScheme;
    final numbers = backend.superHeld;
    final widths = [
      for (final slot in slots)
        _slotWidth +
            (slot.active && !numbers
                ? (slot.apps.length - 1).clamp(0, 2) * 20
                : 0),
    ];
    final active = slots.indexWhere((slot) => slot.active);
    final offset = widths
        .take(active < 0 ? 0 : active)
        .fold(0.0, (sum, width) => sum + width);

    return Stack(
      alignment: .centerLeft,
      children: [
        Row(
          mainAxisSize: .min,
          children: [
            for (var i = 0; i < slots.length; i++)
              AnimatedContainer(
                duration: _resizeDuration,
                curve: _resizeCurve,
                width: widths[i],
                height: 26,
                child: slots[i].occupied
                    ? CustomPaint(
                        painter: _Band(
                          color: slots[i].owner == output.name
                              ? colors.secondaryContainer
                              : colors.outlineVariant,
                          outline: slots[i].owner != output.name,
                          before: i > 0 && slots[i - 1].occupied
                              ? slots[i - 1]
                              : null,
                          slot: slots[i],
                          after: i + 1 < slots.length && slots[i + 1].occupied
                              ? slots[i + 1]
                              : null,
                        ),
                      )
                    : null,
              ),
          ],
        ),
        if (active >= 0)
          Positioned.fill(
            child: IgnorePointer(
              child: TweenAnimationBuilder<Rect>(
                tween: _IndicatorTween(
                  Rect.fromLTWH(offset + 2, 5, widths[active] - 4, 22),
                ),
                duration: _indicatorDuration,
                builder: (context, rect, child) => Stack(
                  children: [Positioned.fromRect(rect: rect, child: child!)],
                ),
                child: AnimatedContainer(
                  key: const ValueKey('workspace-active-indicator'),
                  duration: const Duration(milliseconds: 120),
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: .circular(
                      _pressed == slots[active].id ? 7 : 11,
                    ),
                  ),
                ),
              ),
            ),
          ),
        Row(
          mainAxisSize: .min,
          children: [
            for (var i = 0; i < slots.length; i++)
              AnimatedContainer(
                duration: _resizeDuration,
                curve: _resizeCurve,
                width: widths[i],
                height: 32,
                alignment: .center,
                child: WorkspaceSlot(
                  key: ValueKey('workspace-${slots[i].id}'),
                  backend: backend,
                  slot: slots[i],
                  output: output,
                  onPressed: (pressed) {
                    if (pressed || _pressed == slots[i].id) {
                      setState(() => _pressed = pressed ? slots[i].id : null);
                    }
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SpatialSpring extends Curve {
  _SpatialSpring(
    this.duration, {
    required double stiffness,
    required double damping,
  }) : _spring = SpringSimulation(
         SpringDescription.withDampingRatio(
           mass: 1,
           stiffness: stiffness,
           ratio: damping,
         ),
         0,
         1,
         0,
       );

  final Duration duration;
  final SpringSimulation _spring;

  @override
  double transformInternal(double t) =>
      _spring.x(t * duration.inMilliseconds / 1000).clamp(0.0, 1.0);
}

class _IndicatorTween extends Tween<Rect> {
  _IndicatorTween(Rect value) : super(begin: value, end: value);

  @override
  Rect lerp(double t) {
    final from = begin!;
    final to = end!;
    final front = _indicatorCurve.transform(t);
    final tail = _indicatorCurve.transform(const Interval(.12, 1).transform(t));
    final rightward = to.center.dx >= from.center.dx;
    return Rect.fromLTRB(
      lerpDouble(from.left, to.left, rightward ? tail : front)!,
      to.top,
      lerpDouble(from.right, to.right, rightward ? front : tail)!,
      to.bottom,
    );
  }
}

class _Band extends CustomPainter {
  const _Band({
    required this.color,
    required this.outline,
    required this.before,
    required this.slot,
    required this.after,
  });

  final Color color;
  final bool outline;
  final HyprlandWorkspaceSlot? before;
  final HyprlandWorkspaceSlot slot;
  final HyprlandWorkspaceSlot? after;

  @override
  void paint(Canvas canvas, Size size) {
    double inset(HyprlandWorkspaceSlot? neighbor) => neighbor == null
        ? 0
        : neighbor.owner == slot.owner
        ? -13
        : 1;
    var rect = Rect.fromLTRB(
      inset(before),
      0,
      size.width - inset(after),
      size.height,
    );
    if (outline) rect = rect.deflate(.5);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const .circular(13)),
      Paint()
        ..color = color
        ..style = outline ? .stroke : .fill,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Band old) =>
      color != old.color ||
      outline != old.outline ||
      slot.owner != old.slot.owner ||
      before?.owner != old.before?.owner ||
      after?.owner != old.after?.owner ||
      (before == null) != (old.before == null) ||
      (after == null) != (old.after == null);
}
