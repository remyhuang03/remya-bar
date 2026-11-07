import 'package:material_ui/material_ui.dart';

import 'bar_hover_card.dart';

class BarPillCard {
  const BarPillCard({
    required this.kind,
    required this.size,
    required this.data,
    this.seedColor,
    this.openOnTap = false,
  });

  final String kind;
  final Size size;
  final Map<String, Object?> data;
  final Color? seedColor;
  final bool openOnTap;
}

class BarPillState {
  const BarPillState({
    required this.expanded,
    required this.pressed,
    required this.foreground,
  });

  final bool expanded;
  final bool pressed;
  final Color foreground;
}

class BarPill extends StatefulWidget {
  const BarPill({
    super.key,
    required this.builder,
    this.scheme,
    this.color,
    this.background,
    this.padding = EdgeInsets.zero,
    this.expandedPadding,
    this.onTap,
    this.toggled,
    this.attached = false,
    this.semanticsLabel,
    this.semanticsHint,
    this.card,
    this.pillKey,
  });

  final Widget Function(BuildContext context, BarPillState state) builder;
  final ColorScheme? scheme;
  final Color? color;
  final Widget? background;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? expandedPadding;
  final VoidCallback? onTap;
  final bool? toggled;
  final bool attached;
  final String? semanticsLabel;
  final String? semanticsHint;
  final BarPillCard? card;
  final GlobalKey? pillKey;

  @override
  State<BarPill> createState() => _BarPillState();
}

class _BarPillState extends State<BarPill> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: card == null
          ? _buildPill(context, widget.onTap)
          : BarHoverCard(
              kind: card.kind,
              size: card.size,
              data: card.data,
              seedColor: card.seedColor,
              openOnTap: card.openOnTap,
              onTap: widget.onTap,
              builder: _buildPill,
            ),
    );
  }

  Widget _buildPill(BuildContext context, VoidCallback? onTap) {
    final scheme = widget.scheme ?? Theme.of(context).colorScheme;
    final expanded = _hovered || _focused || _pressed || widget.attached;
    final base = _pressed
        ? scheme.primaryContainer
        : widget.toggled == true
        ? scheme.primary
        : widget.attached
        ? scheme.surfaceContainer
        : widget.color ?? scheme.surfaceContainerHigh;
    final surface = !_pressed && (_hovered || _focused)
        ? Color.alphaBlend(scheme.onSurface.withValues(alpha: .08), base)
        : base;
    final foreground = _pressed
        ? scheme.onPrimaryContainer
        : widget.toggled == true
        ? scheme.onPrimary
        : scheme.onSurface;
    final radius = widget.attached
        ? const BorderRadius.vertical(top: Radius.circular(20))
        : BorderRadius.circular(
            _pressed
                ? 12
                : expanded
                ? 20
                : 16,
          );
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    return Semantics(
      label: widget.semanticsLabel,
      hint: widget.semanticsHint,
      button: onTap != null,
      toggled: widget.toggled,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          key: widget.pillKey,
          duration: duration,
          curve: Easing.emphasizedDecelerate,
          height: expanded ? 40 : 32,
          decoration: BoxDecoration(color: surface, borderRadius: radius),
          foregroundDecoration: _focused
              ? BoxDecoration(
                  border: .all(color: scheme.primary, width: 2),
                  borderRadius: radius,
                )
              : null,
          clipBehavior: .antiAlias,
          child: Stack(
            children: [
              if (widget.background case final background?)
                Positioned.fill(child: background),
              Material(
                type: .transparency,
                child: InkWell(
                  onTap: onTap,
                  onFocusChange: (value) => setState(() => _focused = value),
                  onHighlightChanged: (value) =>
                      setState(() => _pressed = value),
                  overlayColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  splashFactory: NoSplash.splashFactory,
                  // Fill the pill height so content is centred and the whole
                  // pill is the tap target.
                  child: SizedBox(
                    height: double.infinity,
                    child: Align(
                      widthFactor: 1,
                      child: AnimatedPadding(
                        duration: duration,
                        curve: Easing.emphasizedDecelerate,
                        padding: expanded
                            ? widget.expandedPadding ?? widget.padding
                            : widget.padding,
                        child: widget.builder(
                          context,
                          BarPillState(
                            expanded: expanded,
                            pressed: _pressed,
                            foreground: foreground,
                          ),
                        ),
                      ),
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
