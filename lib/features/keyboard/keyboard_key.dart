part of 'keyboard_panel.dart';

enum _KeyKind { character, modifier, accent, space }

class _KeySpec {
  const _KeySpec(
    this.code,
    this.label, {
    this.units = 1,
    this.icon,
    this.alternate,
    this.send,
    this.modifier,
    this.kind = .modifier,
    this.repeat = false,
  });

  final int code;
  final String label;
  final double units;
  final String? icon;
  final String? alternate;
  final int? send;
  final _Modifier? modifier;
  final _KeyKind kind;
  final bool repeat;
}

class _KeyboardIcon extends StatelessWidget {
  const _KeyboardIcon(this.name);
  final String name;

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color;
    return SvgPicture.asset(
      'assets/icons/keyboard/$name.svg',
      colorFilter: color == null ? null : ColorFilter.mode(color, .srcIn),
    );
  }
}

class _KeyboardKey extends StatefulWidget {
  const _KeyboardKey({
    super.key,
    required this.spec,
    required this.state,
    required this.onActivate,
    this.onPreview,
  });

  final _KeySpec spec;
  final _KeyState state;
  final VoidCallback onActivate;
  final ValueChanged<bool>? onPreview;

  @override
  State<_KeyboardKey> createState() => _KeyboardKeyState();
}

class _KeyboardKeyState extends State<_KeyboardKey> {
  int? _pointer;
  bool _hovered = false;
  bool _repeated = false;
  Timer? _repeat;
  VoidCallback? _activate;
  ValueChanged<bool>? _preview;

  void _down(PointerDownEvent event) {
    if (_pointer != null || event.buttons != 1) return;
    setState(() => _pointer = event.pointer);
    _activate = widget.onActivate;
    _repeated = false;
    if (event.kind == .touch) {
      _preview = widget.onPreview;
      _preview?.call(true);
    }
    if (widget.spec.repeat) {
      _repeat = Timer(const Duration(milliseconds: 400), () {
        _repeated = true;
        _activate?.call();
        _repeat = Timer.periodic(
          const Duration(microseconds: 33333),
          (_) => _activate?.call(),
        );
      });
    }
  }

  void _finish(PointerEvent event, {bool activate = false}) {
    if (_pointer != event.pointer) return;
    _repeat?.cancel();
    _preview?.call(false);
    _preview = null;
    final box = context.findRenderObject() as RenderBox;
    if (activate &&
        !_repeated &&
        (Offset.zero & box.size).contains(event.localPosition)) {
      _activate?.call();
    }
    _activate = null;
    setState(() => _pointer = null);
  }

  void _move(PointerMoveEvent event) {
    if (_pointer != event.pointer) return;
    final box = context.findRenderObject() as RenderBox;
    if (!(Offset.zero & box.size).contains(event.localPosition)) _finish(event);
  }

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final key = widget.spec;
    final colors = Theme.of(context).colorScheme;
    final pressed = _pointer != null;
    final state = widget.state;
    final active = pressed || state != .idle;
    final (base, foreground) = switch ((pressed, state, key.kind)) {
      (true, _, .character) ||
      (_, .locked, _) => (colors.primary, colors.onPrimary),
      (_, .latched, _) => (colors.primaryContainer, colors.onPrimaryContainer),
      (_, _, .accent) => (colors.tertiaryContainer, colors.onTertiaryContainer),
      (_, _, .modifier) => (
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      _ => (colors.surfaceContainerHighest, colors.onSurface),
    };
    final color = Color.alphaBlend(
      foreground.withValues(
        alpha: pressed
            ? .16
            : _hovered
            ? .08
            : 0,
      ),
      base,
    );
    final text = Text(
      key.label,
      maxLines: 1,
      overflow: .ellipsis,
      style: TextStyle(
        color: key.kind == .space && !active
            ? colors.onSurfaceVariant
            : foreground,
        fontSize: switch (key.kind) {
          .character => 18,
          .space => 12,
          _ => 14,
        },
        fontWeight: key.kind == .space ? .w400 : .w500,
      ),
    );
    return Semantics(
      button: true,
      label: key.kind == .space ? 'Space' : key.label,
      toggled: key.modifier != null || key.code == 58 ? state != .idle : null,
      excludeSemantics: true,
      onTap: widget.onActivate,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Listener(
          behavior: .opaque,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: (event) => _finish(event, activate: true),
          onPointerCancel: _finish,
          child: RepaintBoundary(
            child: SizedBox(
              width: key.units * 62 - 6,
              height: 52,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: active ? 8 : 18),
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutBack,
                builder: (_, radius, child) => DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: .circular(radius),
                  ),
                  child: child,
                ),
                child: Stack(
                  alignment: .center,
                  children: [
                    if (key.icon case final icon?)
                      IconTheme(
                        data: IconThemeData(color: foreground),
                        child: Row(
                          mainAxisSize: .min,
                          spacing: 6,
                          children: [
                            _KeyboardIcon(
                              icon == 'shift' && state != .idle
                                  ? 'shift-active'
                                  : icon,
                            ),
                            if (const {
                              'Tab',
                              'Caps',
                              'Enter',
                              'Shift',
                            }.contains(key.label))
                              text,
                          ],
                        ),
                      )
                    else
                      Padding(
                        padding: const .symmetric(horizontal: 6),
                        child: text,
                      ),
                    if (key.alternate case final alternate?)
                      Positioned(
                        top: 5,
                        right: 6,
                        child: Text(
                          alternate,
                          style: TextStyle(
                            color: active
                                ? foreground
                                : colors.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    if (state == .locked)
                      Positioned(
                        bottom: 5,
                        child: Container(
                          width: 16,
                          height: 2,
                          decoration: BoxDecoration(
                            color: foreground,
                            borderRadius: .circular(1),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DragHandle extends StatefulWidget {
  const _DragHandle({
    required this.action,
    required this.readCursor,
    required this.color,
  });

  final Future<void> Function(String, [Object?]) action;
  final Future<Map<Object?, Object?>?> Function() readCursor;
  final Color color;

  @override
  State<_DragHandle> createState() => _DragHandleState();
}

class _DragHandleState extends State<_DragHandle> {
  Future<void>? _update;
  Future<Offset?>? _origin;
  Offset _touchDelta = .zero;

  Future<Offset?> _cursor() async {
    try {
      final data = await widget.readCursor();
      return data == null
          ? null
          : Offset(
              (data['x'] as num).toDouble(),
              (data['y'] as num).toDouble(),
            );
    } catch (error) {
      debugPrint('Virtual keyboard cursor: $error');
      return null;
    }
  }

  Future<void> _start(DragStartDetails details) async {
    _touchDelta = .zero;
    _origin = details.kind == PointerDeviceKind.touch ? null : _cursor();
    await widget.action('drag-start');
  }

  Future<void> _move({bool drop = false}) async {
    final request = _origin;
    final origin = await request;
    final cursor = origin == null ? null : await _cursor();
    if (!mounted || _origin != request) return;
    if (origin != null && cursor != null) {
      final delta = cursor - origin;
      await widget.action(drop ? 'drag-end' : 'drag', [
        delta.dx.round(),
        delta.dy.round(),
        if (drop) ...[cursor.dx.round(), cursor.dy.round()],
      ]);
    } else if (drop) {
      await widget.action('drag-end');
    }
  }

  void _drag(DragUpdateDetails details) {
    if (_origin == null) {
      // shortcut: touch moves on release until the compositor supplies global touch coordinates.
      _touchDelta += details.delta;
      return;
    }
    _update ??= _move().whenComplete(() => _update = null);
  }

  Future<void> _end({bool canceled = false}) async {
    final request = _origin;
    final delta = _touchDelta;
    await _update;
    if (!mounted || _origin != request) return;
    if (canceled) {
      await widget.action('drag-end');
    } else if (request == null) {
      await widget.action('drag-end', [delta.dx.round(), delta.dy.round()]);
    } else {
      await _move(drop: true);
    }
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.grab,
    child: GestureDetector(
      behavior: .opaque,
      onDoubleTap: () => widget.action('reset-position'),
      onPanStart: _start,
      onPanUpdate: _drag,
      onPanEnd: (_) => _end(),
      onPanCancel: () => _end(canceled: true),
      child: SizedBox(
        width: 88,
        height: 24,
        child: Align(
          alignment: .topCenter,
          child: Container(
            margin: const .only(top: 9),
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: .circular(2),
            ),
          ),
        ),
      ),
    ),
  );
}
