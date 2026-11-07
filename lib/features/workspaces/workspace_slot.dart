import 'dart:async';
import 'dart:io';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../../widgets/bar_tooltip.dart';
import '../hyprland/hyprland_backend.dart';

const _triangleOutline = 'assets/icons/workspaces/soft-triangle-outline.svg';
const _triangleTag = 'assets/icons/workspaces/soft-triangle-tag.svg';

bool _isTriangle(int number) => (number - 1) % 4 == 2;

class OutputMark extends StatelessWidget {
  const OutputMark({super.key, required this.number, required this.size});

  final int number;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // Compact marks are the Super-held owner pips: shape only, outlined in
    // the pill colour so they stay legible over slot content.
    final compact = size <= 10;
    final fill = compact ? colors.tertiary : colors.tertiaryContainer;
    final outline = BorderSide(
      color: colors.surfaceContainerHigh,
      width: 1.5,
      strokeAlign: BorderSide.strokeAlignOutside,
    );
    final label = compact
        ? null
        : Center(
            child: Text(
              '$number',
              textScaler: .noScaling,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onTertiaryContainer,
                fontSize: 11,
                fontWeight: .w600,
              ),
            ),
          );
    return SizedBox.square(
      dimension: size,
      child: _isTriangle(number)
          ? Stack(
              alignment: .center,
              children: [
                OverflowBox(
                  maxWidth: compact ? size : 23,
                  maxHeight: compact ? size : 22,
                  child: SvgPicture.asset(
                    _triangleTag,
                    colorMapper: _TriangleTagColors(
                      fill,
                      compact ? outline.color : null,
                    ),
                    excludeFromSemantics: true,
                  ),
                ),
                ?label,
              ],
            )
          : DecoratedBox(
              decoration: ShapeDecoration(
                color: fill,
                shape: MaterialShapeBorder(
                  shape: _outputShape(number),
                  side: compact ? outline : .none,
                ),
              ),
              child: label,
            ),
    );
  }
}

class _TriangleTagColors extends ColorMapper {
  const _TriangleTagColors(this.fill, this.stroke);

  final Color fill;
  final Color? stroke;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) => id != 'Shape'
      ? color
      : attributeName == 'fill'
      ? fill
      : stroke ?? color;

  @override
  bool operator ==(Object other) =>
      other is _TriangleTagColors &&
      fill == other.fill &&
      stroke == other.stroke;

  @override
  int get hashCode => Object.hash(fill, stroke);
}

RoundedPolygon _outputShape(int number) => switch ((number - 1) % 4) {
  0 => MaterialShapes.circle,
  1 => MaterialShapes.cookie4Sided,
  2 => MaterialShapes.triangle,
  _ => MaterialShapes.sunny,
};

class _VisibleRing extends StatelessWidget {
  const _VisibleRing({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (_isTriangle(number)) {
      return SvgPicture.asset(
        _triangleOutline,
        width: 24,
        height: 24,
        colorFilter: ColorFilter.mode(colors.tertiary, .srcIn),
        excludeFromSemantics: true,
      );
    }
    return SizedBox.square(
      dimension: 22,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: MaterialShapeBorder(
            shape: _outputShape(number),
            side: BorderSide(
              color: colors.tertiary,
              width: 1.5,
              strokeAlign: BorderSide.strokeAlignCenter,
            ),
          ),
        ),
      ),
    );
  }
}

class WorkspaceSlot extends StatefulWidget {
  const WorkspaceSlot({
    super.key,
    required this.backend,
    required this.slot,
    required this.output,
    required this.onPressed,
  });

  final HyprlandBackend backend;
  final HyprlandWorkspaceSlot slot;
  final HyprlandMonitor output;
  final ValueChanged<bool> onPressed;

  @override
  State<WorkspaceSlot> createState() => _WorkspaceSlotState();
}

class _WorkspaceSlotState extends State<WorkspaceSlot>
    with SingleTickerProviderStateMixin {
  final _states = WidgetStatesController();
  late final _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  late final _ringScale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1, end: 1.15), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 1.15, end: 1), weight: 2),
  ]).animate(_bounce);

  Future<void> _activate(bool remote) async {
    final switched = await widget.backend.switchWorkspace(widget.slot.id);
    if (mounted && switched && remote) _bounce.forward(from: 0);
  }

  @override
  void dispose() {
    _states.dispose();
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
    final backend = widget.backend;
    final owner = backend.monitors
        .where((m) => m.name == slot.owner)
        .firstOrNull;
    final other = slot.owner != null && slot.owner != widget.output.name;
    final visible = other && owner?.activeWorkspaceId == slot.id;
    final showOwner = other && owner != null && backend.monitors.length > 1;
    final outputName = owner == null
        ? slot.owner ?? widget.output.name
        : 'Display ${owner.outputNumber} (${owner.name})';
    final apps = slot.apps.where((name) => name.isNotEmpty).join(', ');
    final label =
        'Workspace ${slot.name} · $outputName${apps.isEmpty ? '' : '\n$apps'}';
    final colors = Theme.of(context).colorScheme;
    final numbers = backend.superHeld;
    final color = slot.active
        ? colors.onPrimary
        : slot.occupied && !other
        ? colors.onSecondaryContainer
        : colors.onSurfaceVariant;

    final content = _SlotContent(
      slot: slot,
      backend: backend,
      color: color,
      bandColor: other
          ? colors.surfaceContainerHigh
          : colors.secondaryContainer,
    );
    final button = Semantics(
      button: true,
      selected: slot.active,
      label: label,
      child: ListenableBuilder(
        listenable: _states,
        builder: (context, _) {
          final pressed = _states.value.contains(WidgetState.pressed);
          final hovered = _states.value.contains(WidgetState.hovered);
          final focused = _states.value.contains(WidgetState.focused);
          return Stack(
            alignment: .center,
            clipBehavior: .none,
            children: [
              Positioned.fill(
                left: 2,
                top: 2,
                right: 2,
                bottom: 2,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: BoxDecoration(
                    borderRadius: .circular(pressed ? 7 : 11),
                    color: (slot.active ? colors.onPrimary : colors.onSurface)
                        .withValues(
                          alpha: pressed
                              ? .10
                              : hovered
                              ? .08
                              : 0,
                        ),
                  ),
                ),
              ),
              // Only app icons of other outputs are dimmed; Super-held IDs
              // and visible workspaces stay at full strength.
              Opacity(
                opacity: other && !visible && !numbers ? .6 : 1,
                child: content,
              ),
              if (visible && showOwner)
                ScaleTransition(
                  scale: _ringScale,
                  child: _VisibleRing(number: owner.outputNumber),
                ),
              if (focused)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      shape: StadiumBorder(
                        side: BorderSide(color: colors.secondary, width: 2),
                      ),
                    ),
                  ),
                ),
              if (numbers && showOwner)
                Positioned(
                  right: 0,
                  bottom: 1,
                  child: OutputMark(number: owner.outputNumber, size: 9),
                ),
              if (slot.urgent)
                Positioned(
                  top: 1,
                  right: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.error,
                      shape: .circle,
                      border: Border.all(
                        color: colors.surfaceContainerHigh,
                        width: 1.5,
                        strokeAlign: BorderSide.strokeAlignOutside,
                      ),
                    ),
                    child: const SizedBox.square(dimension: 6),
                  ),
                ),
              Positioned.fill(
                child: Material(
                  type: .transparency,
                  child: InkWell(
                    statesController: _states,
                    borderRadius: .circular(13),
                    overlayColor: const WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                    onHighlightChanged: widget.onPressed,
                    onTap: slot.id == 0
                        ? null
                        : () => unawaited(_activate(showOwner)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    return BarTooltip(
      message: label,
      trayStyle: true,
      child: SizedBox(width: double.infinity, height: 26, child: button),
    );
  }
}

class _SlotContent extends StatelessWidget {
  const _SlotContent({
    required this.slot,
    required this.backend,
    required this.color,
    required this.bandColor,
  });
  final HyprlandWorkspaceSlot slot;
  final HyprlandBackend backend;
  final Color color;
  final Color bandColor;

  @override
  Widget build(BuildContext context) {
    if (backend.superHeld || slot.active && !slot.occupied) {
      return Text(
        slot.id == 0 ? '—' : '${slot.id}',
        maxLines: 1,
        textScaler: .noScaling,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: color, fontSize: 12, fontWeight: .w600),
      );
    }
    if (!slot.occupied) {
      return DecoratedBox(
        decoration: BoxDecoration(color: color, shape: .circle),
        child: const SizedBox.square(dimension: 4),
      );
    }
    final apps = slot.apps;
    if (apps.length <= 1) return _icon(apps.firstOrNull, 18);
    if (slot.active) {
      return LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < (apps.length == 2 ? 42 : 62)) {
            return _icon(apps.first, 18);
          }
          return Row(
            mainAxisSize: .min,
            spacing: 2,
            children: [
              _icon(apps.first, 18),
              _icon(apps[1], 18),
              if (apps.length > 2)
                _Count(
                  value: apps.length - 2,
                  size: 18,
                  color: Theme.of(context).colorScheme.onPrimary,
                  textColor: Theme.of(context).colorScheme.primary,
                ),
            ],
          );
        },
      );
    }
    // Primary 16 px at (3, 3); secondary 13 px at (11, 11) with a 1.5 px
    // band-coloured outline outside it, as in the Slot spec.
    return SizedBox.square(
      dimension: 24,
      child: Stack(
        clipBehavior: .none,
        children: [
          Positioned(top: 2, left: 2, child: _icon(apps.first, 16)),
          Positioned(
            right: 1,
            bottom: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: .circle,
                border: Border.all(
                  color: bandColor,
                  width: 1.5,
                  strokeAlign: BorderSide.strokeAlignOutside,
                ),
              ),
              child: apps.length == 2
                  ? _icon(apps[1], 13)
                  : _Count(
                      value: apps.length - 1,
                      size: 13,
                      color: color,
                      textColor: bandColor,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _icon(String? app, double size) => _WorkspaceIcon(
    path: app == null ? null : backend.iconPath(app),
    color: color,
    size: size,
  );
}

class _Count extends StatelessWidget {
  const _Count({
    required this.value,
    required this.size,
    required this.color,
    required this.textColor,
  });
  final int value;
  final double size;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, shape: .circle),
        child: Center(
          child: FittedBox(
            child: Text(
              '+$value',
              textScaler: .noScaling,
              style: TextStyle(
                color: textColor,
                fontSize: size == 18 ? 9 : 7,
                fontWeight: .w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceIcon extends StatelessWidget {
  const _WorkspaceIcon({
    required this.path,
    required this.color,
    required this.size,
  });

  final String? path;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(Icons.apps_rounded, size: size, color: color);
    return path == null
        ? fallback
        : ClipOval(
            child: Image.file(
              File(path!),
              width: size,
              height: size,
              fit: .contain,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => fallback,
            ),
          );
  }
}
