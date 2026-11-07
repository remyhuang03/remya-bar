import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../features/popups/bar_card_surface.dart';
import '../features/popups/bar_popup.dart';

/// A live Flutter card hosted outside the fixed-height bar surface.
class BarHoverCard extends StatefulWidget {
  const BarHoverCard({
    super.key,
    required this.kind,
    required this.size,
    required this.data,
    this.child,
    this.builder,
    this.onTap,
    this.openOnTap = false,
    this.seedColor,
  }) : assert((child == null) != (builder == null));

  final String kind;
  final Size size;
  final Map<String, Object?> data;
  final Widget? child;
  final Widget Function(BuildContext context, VoidCallback? onTap)? builder;
  final VoidCallback? onTap;
  final bool openOnTap;
  final Color? seedColor;

  @override
  State<BarHoverCard> createState() => _BarHoverCardState();
}

class _BarHoverCardState extends State<BarHoverCard> {
  Timer? _timer;
  bool _hovered = false;
  bool _shown = false;

  void _send(Future<void> request) {
    request.catchError((Object error) => debugPrint('Bar card: $error'));
  }

  void _show({bool update = false, bool activated = false}) {
    final box = context.findRenderObject() as RenderBox?;
    if ((!update && !activated && !_hovered) || box == null || !box.hasSize) {
      return;
    }
    final request = update ? BarPopup.update : BarPopup.show;
    _shown = true;
    _send(
      request(
        kind: widget.kind,
        anchor: box.localToGlobal(.zero) & box.size,
        size: Size(
          widget.size.width + BarCardSurface.shadowInsets.horizontal,
          widget.size.height + BarCardSurface.shadowInsets.vertical,
        ),
        data: {
          ...widget.data,
          if (widget.seedColor case final seed?)
            'cardSeed': seed.toARGB32() & 0xFFFFFF,
          'scale': MediaQuery.textScalerOf(context).scale(1),
        },
        theme: BarPopupScope.themeOf(context),
      ),
    );
  }

  void _activate() {
    _timer?.cancel();
    _show(activated: true);
  }

  void _refresh() {
    if (!_shown) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _show(update: true);
    });
  }

  @override
  void didUpdateWidget(BarHoverCard oldWidget) {
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
    _timer?.cancel();
    if (_shown) _send(BarPopup.hide(kind: widget.kind));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) {
      _hovered = true;
      _send(BarPopup.enter(kind: widget.kind));
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 300), _show);
    },
    onExit: (_) {
      _hovered = false;
      _timer?.cancel();
      if (_shown) _send(BarPopup.leave(kind: widget.kind));
    },
    child: widget.builder != null
        ? widget.builder!(context, widget.openOnTap ? _activate : widget.onTap)
        : widget.onTap == null && !widget.openOnTap
        ? widget.child!
        : InkWell(
            onTap: widget.openOnTap ? _activate : widget.onTap,
            child: widget.child,
          ),
  );
}
