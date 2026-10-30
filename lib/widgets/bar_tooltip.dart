import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../features/popups/bar_popup.dart';

/// A Flutter tooltip hosted outside the bar's fixed-height surface.
class BarTooltip extends StatefulWidget {
  const BarTooltip({super.key, required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  State<BarTooltip> createState() => _BarTooltipState();
}

class _BarTooltipState extends State<BarTooltip> {
  Timer? _timer;
  bool _hovered = false;
  bool _shown = false;

  void _show() {
    final box = context.findRenderObject() as RenderBox?;
    if (!_hovered || box == null || !box.hasSize || widget.message.isEmpty) {
      return;
    }
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final painter = TextPainter(
      text: TextSpan(text: widget.message, style: theme.textTheme.bodySmall),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )..layout(maxWidth: 320);
    final size = Size(
      painter.width.ceilToDouble() + 24,
      painter.height.ceilToDouble() + 16,
    );
    painter.dispose();
    _shown = true;
    _send(
      BarPopup.show(
        kind: 'tooltip',
        anchor: box.localToGlobal(.zero) & box.size,
        size: size,
        data: {'message': widget.message, 'scale': scaler.scale(12) / 12},
        theme: BarPopupScope.themeOf(context),
      ),
    );
  }

  void _send(Future<void> request) {
    request.catchError((Object error) => debugPrint('Bar popup: $error'));
  }

  void _hide() {
    _timer?.cancel();
    if (_shown) _send(BarPopup.hide());
    _shown = false;
  }

  void _refresh() {
    if (_shown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _show();
      });
    }
  }

  @override
  void didUpdateWidget(BarTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refresh();
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    tooltip: widget.message,
    child: MouseRegion(
      onEnter: (_) {
        _hovered = true;
        _timer = Timer(const Duration(milliseconds: 500), _show);
      },
      onExit: (_) {
        _hovered = false;
        _hide();
      },
      child: widget.child,
    ),
  );
}
