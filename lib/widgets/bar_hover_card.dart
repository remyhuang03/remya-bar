import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
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
  Map<String, Object?>? _lastContent;
  Rect? _lastAnchor;

  void _send(Future<void> request) {
    request.catchError((Object error) => debugPrint('Bar card: $error'));
  }

  void _show({bool update = false, bool activated = false}) {
    if (update && BarPopup.openCard.value != widget.kind) return;
    final box = context.findRenderObject() as RenderBox?;
    if ((!update && !activated && !_hovered) || box == null || !box.hasSize) {
      return;
    }
    final view = View.of(context);
    final viewport = Offset.zero & (view.physicalSize / view.devicePixelRatio);
    var anchor = (box.localToGlobal(.zero) & box.size).intersect(viewport);
    if (RenderAbstractViewport.maybeOf(box) case final RenderBox scroll) {
      anchor = anchor.intersect(scroll.localToGlobal(.zero) & scroll.size);
    }
    if (anchor.isEmpty) {
      if (update && _shown) {
        _shown = false;
        _lastAnchor = null;
        _send(BarPopup.hide(kind: widget.kind));
      }
      return;
    }
    final data = {
      ...widget.data,
      if (widget.seedColor case final seed?)
        'cardSeed': seed.toARGB32() & 0xFFFFFF,
      'scale': MediaQuery.textScalerOf(context).scale(1),
    };
    final theme = BarPopupScope.themeOf(context);
    final content = {
      'data': data,
      'theme': (theme.seedColor, theme.styleVariant, theme.mode),
    };
    final anchorChanged = _lastAnchor != anchor;
    final contentChanged = !const DeepCollectionEquality().equals(
      content,
      _lastContent,
    );
    if (update && !anchorChanged && !contentChanged) return;
    _lastAnchor = anchor;
    _lastContent = content;
    final request = update ? BarPopup.update : BarPopup.show;
    _shown = true;
    _send(
      request(
        kind: widget.kind,
        anchor: anchor,
        size: Size(
          widget.size.width + BarCardSurface.shadowInsets.horizontal,
          widget.size.height + BarCardSurface.shadowInsets.vertical,
        ),
        data: data,
        theme: theme,
      ),
    );
  }

  void _activate() {
    _timer?.cancel();
    _show(activated: true);
  }

  // An anchor can move on a rendered frame without this widget rebuilding.
  void _trackAnchor(Duration _) {
    if (!mounted || BarPopup.openCard.value != widget.kind) return;
    _show(update: true);
    if (_shown) WidgetsBinding.instance.addPostFrameCallback(_trackAnchor);
  }

  void _onOpenCard() {
    if (BarPopup.openCard.value == widget.kind) {
      WidgetsBinding.instance.addPostFrameCallback(_trackAnchor);
    } else {
      _shown = false;
    }
  }

  @override
  void initState() {
    super.initState();
    BarPopup.openCard.addListener(_onOpenCard);
  }

  @override
  void dispose() {
    BarPopup.openCard.removeListener(_onOpenCard);
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
