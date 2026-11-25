import 'package:material_ui/material_ui.dart';

const clockCardWideWidth = 816.0;
const clockCardNarrowWidth = 420.0;
const clockCardMaxHeight = 720.0;

const _connectedInnerRadius = Radius.circular(4);
const _connectedOuterRadius = Radius.circular(16);

BorderRadius connectedClockRowRadius({
  required bool first,
  required bool last,
}) => .vertical(
  top: first ? _connectedOuterRadius : _connectedInnerRadius,
  bottom: last ? _connectedOuterRadius : _connectedInnerRadius,
);

class ClockCardHeader extends StatelessWidget {
  const ClockCardHeader({
    super.key,
    required this.title,
    required this.newTooltip,
    required this.googleLabel,
    required this.onNew,
    required this.onGoogle,
    required this.onRefresh,
    required this.onSettings,
  });

  final String title;
  final String newTooltip;
  final String googleLabel;
  final VoidCallback onNew;
  final VoidCallback onGoogle;
  final VoidCallback onRefresh;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              maxLines: 1,
              overflow: .ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontSize: 24,
                fontWeight: .w700,
                height: 29 / 24,
              ),
            ),
          ),
        ),
        _ClockHeaderButton(
          tooltip: newTooltip,
          onPressed: onNew,
          icon: Icons.add,
        ),
        MenuAnchor(
          menuChildren: [
            MenuItemButton(onPressed: onGoogle, child: Text(googleLabel)),
            MenuItemButton(onPressed: onRefresh, child: const Text('Refresh')),
            MenuItemButton(
              onPressed: onSettings,
              child: const Text('Settings'),
            ),
          ],
          builder: (context, controller, _) => _ClockHeaderButton(
            tooltip: '$title menu',
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            icon: Icons.more_vert,
          ),
        ),
      ],
    );
  }
}

class _ClockHeaderButton extends StatefulWidget {
  const _ClockHeaderButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<_ClockHeaderButton> createState() => _ClockHeaderButtonState();
}

class _ClockHeaderButtonState extends State<_ClockHeaderButton> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _focus,
    child: IconButton.filledTonal(
      focusNode: _focus,
      tooltip: widget.tooltip,
      onPressed: widget.onPressed,
      icon: Icon(widget.icon),
    ),
    builder: (context, child) => CustomPaint(
      foregroundPainter: _focus.hasPrimaryFocus
          ? ClockCardRowFocus(
              const .all(.circular(24)),
              Theme.of(context).colorScheme.secondary,
            )
          : null,
      child: child,
    ),
  );
}

class ClockCardStatusBanner extends StatelessWidget {
  const ClockCardStatusBanner({
    super.key,
    required this.message,
    required this.icon,
    required this.action,
    required this.onAction,
  });

  final String message;
  final IconData icon;
  final String action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textStyle = theme.textTheme.bodySmall;
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: .all(_connectedOuterRadius),
          color: colors.errorContainer,
        ),
        child: Padding(
          padding: const .fromLTRB(14, 0, 6, 0),
          child: Row(
            spacing: 8,
            children: [
              Icon(icon, size: 18, color: colors.onErrorContainer),
              Expanded(
                child: Text(
                  message,
                  style: textStyle?.copyWith(color: colors.onErrorContainer),
                ),
              ),
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: colors.onErrorContainer,
                  textStyle: textStyle?.copyWith(fontWeight: .w500),
                ),
                child: Text(action),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ClockCardScrollFade extends StatelessWidget {
  const ClockCardScrollFade({
    super.key,
    required this.child,
    this.top = false,
    this.bottom = false,
  });

  final Widget child;
  final bool top;
  final bool bottom;

  @override
  Widget build(BuildContext context) => ShaderMask(
    blendMode: .dstIn,
    shaderCallback: (bounds) {
      final edge = bounds.height > 0
          ? (32 / bounds.height).clamp(0.0, .5)
          : 0.0;
      return LinearGradient(
        begin: .topCenter,
        end: .bottomCenter,
        colors: [
          top ? Colors.transparent : Colors.black,
          Colors.black,
          Colors.black,
          bottom ? Colors.transparent : Colors.black,
        ],
        stops: [0, edge, 1 - edge, 1],
      ).createShader(bounds);
    },
    child: child,
  );
}

class ClockCardRowFocus extends CustomPainter {
  const ClockCardRowFocus(this.radius, this.color);

  final BorderRadius radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      radius.toRRect(Offset.zero & size).inflate(3),
      Paint()
        ..color = color
        ..style = .stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(ClockCardRowFocus oldDelegate) =>
      radius != oldDelegate.radius || color != oldDelegate.color;
}
