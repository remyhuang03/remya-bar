part of 'right_sidebar.dart';

class _SidebarLabel extends StatelessWidget {
  const _SidebarLabel(
    this.title,
    this.subtitle, {
    this.titleSize = 14,
    this.bold = false,
    this.titleColor,
    this.subtitleColor,
  });

  final String title;
  final String subtitle;
  final double titleSize;
  final bool bold;
  final Color? titleColor;
  final Color? subtitleColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .start,
      mainAxisAlignment: .center,
      mainAxisSize: .min,
      spacing: 2,
      children: [
        Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: titleSize,
            height: 1.15,
            fontWeight: bold ? .bold : .w500,
            color: titleColor ?? (bold ? theme.colorScheme.onSurface : null),
          ),
          maxLines: 1,
          overflow: .ellipsis,
        ),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: subtitleColor ?? theme.colorScheme.onSurfaceVariant,
            fontSize: 12,
            height: 1.2,
          ),
          maxLines: 1,
          overflow: .ellipsis,
        ),
      ],
    );
  }
}

class _AccountAvatar extends StatefulWidget {
  const _AccountAvatar({super.key, this.path, this.initial});

  final String? path;
  final String? initial;

  @override
  State<_AccountAvatar> createState() => _AccountAvatarState();
}

class _AccountAvatarState extends State<_AccountAvatar> {
  late final Future<Uint8List>? _bytes = widget.path == null
      ? null
      : File(widget.path!).readAsBytes();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback = Material(
      color: colors.primaryContainer,
      shape: const CircleBorder(),
      child: Center(
        child: widget.initial == null
            ? Icon(Icons.person_rounded, color: colors.onPrimaryContainer)
            : Text(
                widget.initial!,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: .bold,
                  color: colors.onPrimaryContainer,
                ),
              ),
      ),
    );
    return SizedBox.square(
      dimension: 44,
      child: ClipOval(
        child: FutureBuilder<Uint8List>(
          future: _bytes,
          builder: (context, snapshot) => snapshot.hasData
              ? Image.memory(
                  snapshot.data!,
                  fit: .cover,
                  semanticLabel: 'Account avatar',
                  errorBuilder: (_, _, _) => fallback,
                )
              : fallback,
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton(
    this.icon,
    this.label,
    this.onPressed, {
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
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

class _LargeTile extends StatefulWidget {
  const _LargeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.editing,
    this.onToggle,
    this.onDetail,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool active;
  final bool editing;
  final VoidCallback? onToggle;
  final VoidCallback? onDetail;

  @override
  State<_LargeTile> createState() => _LargeTileState();
}

class _LargeTileState extends State<_LargeTile> {
  bool _hovered = false;
  bool _pressed = false;

  void _highlight(bool pressed) => setState(() => _pressed = pressed);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = widget.active;
    final editing = widget.editing;
    final onToggle = widget.onToggle;
    final onDetail = widget.onDetail;
    final interactive = !editing && (onToggle != null || onDetail != null);
    final pressed = interactive && _pressed;
    final base = active && !editing
        ? colors.primaryContainer
        : colors.surfaceContainerHighest;
    final stateLayer = active ? colors.onPrimaryContainer : colors.onSurface;
    final background = Color.alphaBlend(
      stateLayer.withValues(
        alpha: pressed
            ? .16
            : interactive && _hovered
            ? .08
            : 0,
      ),
      base,
    );
    final iconRadius = BorderRadius.circular(active ? 16 : 24);
    final iconButton = Material(
      borderRadius: iconRadius,
      clipBehavior: .antiAlias,
      color: active ? colors.primary : colors.surfaceContainerHigh,
      child: Semantics(
        label: widget.title,
        toggled: onToggle == null ? null : active,
        button: onToggle != null,
        child: InkWell(
          onTap: onToggle,
          onHighlightChanged: _highlight,
          splashFactory: NoSplash.splashFactory,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Icon(
            widget.icon,
            size: 22,
            color: active ? colors.onPrimary : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: background,
        borderRadius: .circular(pressed ? 16 : 28),
        clipBehavior: .antiAlias,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              const SizedBox(width: 8),
              SizedBox.square(
                dimension: 48,
                child: onToggle == null
                    ? iconButton
                    : Tooltip(message: widget.title, child: iconButton),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: editing ? null : onDetail ?? onToggle,
                  onHighlightChanged: _highlight,
                  splashFactory: NoSplash.splashFactory,
                  hoverColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  child: Padding(
                    padding: const .only(right: 8),
                    child: Row(
                      spacing: 4,
                      children: [
                        Expanded(
                          child: _SidebarLabel(
                            widget.title,
                            widget.subtitle,
                            titleColor: active && !editing
                                ? colors.onPrimaryContainer
                                : null,
                            subtitleColor: active && !editing
                                ? colors.onPrimaryContainer
                                : null,
                          ),
                        ),
                        if (editing)
                          const Icon(Icons.drag_indicator_rounded, size: 18)
                        else if (onDetail != null)
                          const Icon(Icons.chevron_right_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallTile extends StatelessWidget {
  const _SmallTile({
    required this.icon,
    required this.title,
    required this.selected,
    required this.editing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final bool? selected;
  final bool editing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = selected == true && !editing;
    final tile = Material(
      color: active ? colors.primaryContainer : colors.surfaceContainerHighest,
      borderRadius: .circular(active ? 16 : 26),
      clipBehavior: .antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Icon(
            icon,
            size: 22,
            color: active ? colors.onPrimaryContainer : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
    if (editing) return tile;
    return Tooltip(
      message: title,
      excludeFromSemantics: true,
      child: Semantics(
        label: title,
        button: true,
        enabled: onTap != null,
        toggled: selected,
        child: tile,
      ),
    );
  }
}

class _EditableTile extends StatelessWidget {
  const _EditableTile({
    required this.id,
    required this.label,
    required this.icon,
    required this.child,
    this.onActivate,
    this.onDrop,
  });

  final String id;
  final String label;
  final IconData icon;
  final Widget child;
  final VoidCallback? onActivate;
  final ValueChanged<String>? onDrop;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tile = Draggable<String>(
      data: id,
      maxSimultaneousDrags: onActivate == null ? 0 : 1,
      feedback: Material(
        shape: const StadiumBorder(),
        color: colors.primaryContainer,
        child: Padding(
          padding: const .all(12),
          child: Icon(icon, color: colors.onPrimaryContainer),
        ),
      ),
      childWhenDragging: Opacity(opacity: .5, child: child),
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: child),
    );
    if (onDrop == null) return Tooltip(message: 'Restore $label', child: tile);
    return DragTarget<String>(
      onWillAcceptWithDetails: (drag) =>
          onActivate != null &&
          id != drag.data &&
          _RightSidebarState._large.containsKey(id) ==
              _RightSidebarState._large.containsKey(drag.data),
      onAcceptWithDetails: (drag) => onDrop!(drag.data),
      builder: (context, candidates, _) => Stack(
        fit: .passthrough,
        clipBehavior: .none,
        children: [
          CustomPaint(
            foregroundPainter: _TileOutline(
              candidates.isEmpty ? colors.outlineVariant : colors.primary,
            ),
            child: tile,
          ),
          Positioned(
            left: -5.5,
            top: -5.5,
            child: Tooltip(
              message: 'Hide $label',
              child: Material(
                shape: CircleBorder(
                  side: BorderSide(color: colors.surfaceContainer, width: 2),
                ),
                color: colors.errorContainer,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onActivate,
                  child: SizedBox.square(
                    dimension: 22,
                    child: Icon(
                      Icons.remove_rounded,
                      size: 14,
                      color: colors.onErrorContainer,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TileOutline extends CustomPainter {
  const _TileOutline(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(1),
          const Radius.circular(26),
        ),
      );
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = .stroke;
    for (final metric in path.computeMetrics()) {
      for (double start = 0; start < metric.length; start += 8) {
        canvas.drawPath(metric.extractPath(start, start + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_TileOutline oldDelegate) => oldDelegate.color != color;
}

class _PowerButton extends StatelessWidget {
  const _PowerButton({
    required this.label,
    required this.icon,
    required this.confirm,
    this.onPressed,
  });
  final String label;
  final IconData icon;
  final bool confirm;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 76),
        padding: const .all(4),
        tapTargetSize: .shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: .circular(confirm ? 16 : 24),
        ),
        backgroundColor: confirm
            ? colors.errorContainer
            : colors.surfaceContainerHighest,
        foregroundColor: confirm ? colors.onErrorContainer : colors.onSurface,
        overlayColor: confirm ? colors.onErrorContainer : colors.onSurface,
      ),
      child: Column(
        mainAxisSize: .min,
        spacing: 6,
        children: [
          Icon(icon, size: 22),
          Text(
            confirm ? 'Confirm?' : label,
            textAlign: .center,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SidebarSlider extends StatefulWidget {
  const _SidebarSlider({
    super.key,
    required this.icon,
    required this.label,
    this.percent,
    this.muted = false,
    this.onChange,
    this.onIcon,
    this.onSecondary,
  });

  final IconData icon;
  final String label;
  final num? percent;
  final bool muted;
  final ValueChanged<double>? onChange;
  final VoidCallback? onIcon;
  final VoidCallback? onSecondary;

  @override
  State<_SidebarSlider> createState() => _SidebarSliderState();
}

class _SidebarSliderState extends State<_SidebarSlider> {
  double? _draft;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final percent = (_draft ?? widget.percent?.toDouble() ?? 0).clamp(
      0.0,
      100.0,
    );
    final muted = widget.muted && _draft == null;
    final label = muted
        ? 'Muted'
        : widget.percent == null
        ? '—'
        : '${(_draft ?? widget.percent!).round()}%';
    final onChange = widget.onChange;
    final active = muted ? colors.onSurface : colors.primary;
    final inactive = colors.secondaryContainer;

    return Listener(
      onPointerSignal: (event) {
        if (onChange == null ||
            event is! PointerScrollEvent ||
            event.scrollDelta.dy == 0) {
          return;
        }
        GestureBinding.instance.pointerSignalResolver.register(event, (_) {
          onChange(
            (percent + (event.scrollDelta.dy < 0 ? 5 : -5)).clamp(0, 100),
          );
        });
      },
      child: GestureDetector(
        behavior: .opaque,
        onSecondaryTap: widget.onSecondary,
        child: SizedBox(
          height: 52,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const inset = 2.0;
              final trackWidth = (constraints.maxWidth - inset * 2).clamp(
                1.0,
                double.infinity,
              );
              final value = muted
                  ? (6000 / trackWidth).clamp(0.0, 100.0)
                  : percent;
              final handle = inset + trackWidth * value / 100;
              final readoutStyle = Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontSize: 12);
              final readoutPainter = TextPainter(
                text: TextSpan(text: label, style: readoutStyle),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout();
              final readoutWidth = readoutPainter.width;
              readoutPainter.dispose();
              final inactiveSpace = constraints.maxWidth - handle;
              final onActiveTrack =
                  inactiveSpace < readoutWidth + 22 && value > 50;
              final iconColor = handle < 38 || widget.percent == null
                  ? colors.onSecondaryContainer
                  : muted
                  ? colors.surface
                  : onChange == null
                  ? colors.onSurface
                  : colors.onPrimary;
              return Stack(
                children: [
                  Positioned.fill(
                    child: Semantics(
                      label: widget.label,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          padding: const .symmetric(horizontal: inset),
                          trackShape: const _SidebarTrackShape(),
                          thumbShape: const HandleThumbShape(),
                          trackHeight: 40,
                          trackGap: _draft == null ? 6 : 5,
                          thumbSize: WidgetStatePropertyAll(
                            Size(_draft == null ? 4 : 2, 52),
                          ),
                          activeTrackColor: active,
                          inactiveTrackColor: inactive,
                          thumbColor: active,
                          disabledActiveTrackColor:
                              colors.surfaceContainerHighest,
                          disabledInactiveTrackColor: inactive,
                          disabledThumbColor: colors.outline,
                          showValueIndicator: .onDrag,
                          valueIndicatorShape: const _SidebarValueIndicator(),
                          valueIndicatorColor: colors.inverseSurface,
                          valueIndicatorTextStyle: TextStyle(
                            color: colors.onInverseSurface,
                            fontSize: 14,
                            fontWeight: .w500,
                          ),
                        ),
                        child: Slider(
                          value: value,
                          max: 100,
                          label: '${percent.round()}',
                          overlayColor: .resolveWith(
                            (states) =>
                                states.contains(WidgetState.focused) &&
                                    !states.contains(WidgetState.dragged)
                                ? active.withValues(alpha: .12)
                                : Colors.transparent,
                          ),
                          semanticFormatterCallback: (_) => label,
                          onChangeStart: onChange == null
                              ? null
                              : (_) => setState(() => _draft = percent),
                          onChanged: onChange == null
                              ? null
                              : (value) {
                                  if (_draft != null) {
                                    setState(() => _draft = value);
                                  } else {
                                    onChange(value);
                                  }
                                },
                          onChangeEnd: onChange == null
                              ? null
                              : (value) {
                                  setState(() => _draft = null);
                                  onChange(value);
                                },
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: onActiveTrack ? inactiveSpace + 12 : 14,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: Center(
                          child: Text(
                            label,
                            style: readoutStyle?.copyWith(
                              color: onActiveTrack
                                  ? onChange == null
                                        ? colors.onSurface
                                        : colors.onPrimary
                                  : colors.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 6,
                    top: 0,
                    bottom: 0,
                    width: 36,
                    child: widget.onIcon == null
                        ? IgnorePointer(
                            child: Icon(
                              widget.icon,
                              size: 20,
                              color: iconColor,
                            ),
                          )
                        : IconButton(
                            tooltip: muted
                                ? 'Unmute ${widget.label}'
                                : 'Mute ${widget.label}',
                            onPressed: widget.onIcon,
                            padding: .zero,
                            icon: Icon(widget.icon, size: 20, color: iconColor),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SidebarTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  const _SidebarTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final track = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
    );
    final gap = sliderTheme.trackGap!;
    final active = Color.lerp(
      sliderTheme.disabledActiveTrackColor,
      sliderTheme.activeTrackColor,
      enableAnimation.value,
    )!;
    final inactive = Color.lerp(
      sliderTheme.disabledInactiveTrackColor,
      sliderTheme.inactiveTrackColor,
      enableAnimation.value,
    )!;
    final (leftColor, rightColor) = textDirection == .ltr
        ? (active, inactive)
        : (inactive, active);
    final leftEdge = thumbCenter.dx - gap;
    final rightEdge = thumbCenter.dx + gap;
    const outer = Radius.circular(16);
    const inner = Radius.circular(4);
    final canvas = context.canvas;
    if (leftEdge > track.left) {
      canvas.drawRRect(
        RRect.fromLTRBAndCorners(
          track.left,
          track.top,
          leftEdge,
          track.bottom,
          topLeft: outer,
          bottomLeft: outer,
          topRight: inner,
          bottomRight: inner,
        ),
        Paint()..color = leftColor,
      );
    }
    if (rightEdge < track.right) {
      canvas.drawRRect(
        RRect.fromLTRBAndCorners(
          rightEdge,
          track.top,
          track.right,
          track.bottom,
          topLeft: inner,
          bottomLeft: inner,
          topRight: outer,
          bottomRight: outer,
        ),
        Paint()..color = rightColor,
      );
    }
  }
}

class _SidebarValueIndicator extends SliderComponentShape {
  const _SidebarValueIndicator();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(50, 41);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final width = labelPainter.width + 32;
    final height = labelPainter.height + 24;
    final halfWidth = width / 2;
    final globalX = parentBox.localToGlobal(center).dx;
    final x =
        center.dx +
        globalX.clamp(
          halfWidth,
          (sizeWithOverflow.width - halfWidth).clamp(
            halfWidth,
            double.infinity,
          ),
        ) -
        globalX;
    final rect = Rect.fromCenter(
      center: Offset(x, center.dy - 35 - height / 2),
      width: width,
      height: height,
    );
    final scale = activationAnimation.value;
    final canvas = context.canvas;
    canvas
      ..save()
      ..translate(rect.center.dx, rect.center.dy)
      ..scale(scale, scale)
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: .zero, width: width, height: height),
          const Radius.circular(22),
        ),
        Paint()..color = sliderTheme.valueIndicatorColor!,
      );
    labelPainter.paint(
      canvas,
      Offset(-labelPainter.width / 2, -labelPainter.height / 2),
    );
    canvas.restore();
  }
}
