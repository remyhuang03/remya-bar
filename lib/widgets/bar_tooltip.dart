import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../features/popups/bar_popup.dart';

/// A Flutter tooltip hosted outside the bar's fixed-height surface.
class BarTooltip extends StatefulWidget {
  const BarTooltip({
    super.key,
    required this.message,
    required this.child,
    this.trayStyle = false,
    this.showOnFocus = false,
    this.suppressWhenCardOpen,
  });

  final String message;
  final Widget child;
  final bool trayStyle;
  final bool showOnFocus;
  final String? suppressWhenCardOpen;

  @override
  State<BarTooltip> createState() => _BarTooltipState();
}

class _BarTooltipState extends State<BarTooltip> {
  Timer? _timer;
  bool _hovered = false;
  bool _focused = false;
  bool _shown = false;
  BarPopup? _popup;

  bool get _suppressed =>
      widget.suppressWhenCardOpen != null &&
      _popup?.openCard.value == widget.suppressWhenCardOpen;

  void _show() {
    final popup = _popup;
    if (popup == null) return;
    final box = context.findRenderObject() as RenderBox?;
    if ((!_hovered && !_focused) ||
        _suppressed ||
        box == null ||
        !box.hasSize ||
        widget.message.isEmpty) {
      return;
    }
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final tray = widget.trayStyle;
    final style = theme.textTheme.bodySmall?.copyWith(
      fontSize: tray ? 12 : null,
    );
    final painter = TextPainter(
      text: TextSpan(text: widget.message, style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )..layout(maxWidth: 320);
    final size = Size(
      painter.width.ceilToDouble() + (tray ? 16 : 24),
      painter.height.ceilToDouble() + (tray ? 8 : 16),
    );
    painter.dispose();
    _shown = true;
    _send(
      popup.show(
        kind: 'tooltip',
        anchor: box.localToGlobal(Offset(0, tray ? 2 : 0)) & box.size,
        size: size,
        data: {
          'message': widget.message,
          'scale': scaler.scale(12) / 12,
          if (tray) 'tray': true,
        },
        theme: BarPopupScope.themeOf(context),
      ),
    );
  }

  void _send(Future<void> request) {
    request.catchError((Object error) => debugPrint('Bar popup: $error'));
  }

  void _hide() {
    _timer?.cancel();
    if (_popup case final popup? when _shown) {
      _send(popup.hide(kind: 'tooltip'));
    }
    _shown = false;
  }

  void _refresh() {
    if (_shown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _show();
      });
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (_suppressed || (!_hovered && !_focused)) {
      _hide();
    } else if (!_shown) {
      _timer = Timer(const Duration(milliseconds: 500), _show);
    }
  }

  @override
  void didUpdateWidget(BarTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message.isEmpty) {
      _hide();
    } else if (oldWidget.message != widget.message ||
        oldWidget.trayStyle != widget.trayStyle) {
      _refresh();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final popup = BarPopup.maybeOf(context);
    if (popup != _popup) {
      _popup?.openCard.removeListener(_schedule);
      _popup = popup;
      if (widget.suppressWhenCardOpen != null) {
        _popup?.openCard.addListener(_schedule);
      }
    }
    _refresh();
  }

  @override
  void dispose() {
    _popup?.openCard.removeListener(_schedule);
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    tooltip: widget.message,
    child: MouseRegion(
      onEnter: (_) {
        _hovered = true;
        _schedule();
      },
      onExit: (_) {
        _hovered = false;
        _schedule();
      },
      child: widget.showOnFocus
          ? Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (focused) {
                _focused = focused;
                _schedule();
              },
              child: widget.child,
            )
          : widget.child,
    ),
  );
}
