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
    this.loadData,
    this.dataChanges,
    this.child,
    this.builder,
    this.onTap,
    this.openOnTap = false,
    this.hoverOpens = true,
    this.seedColor,
  }) : assert((child == null) != (builder == null));

  final String kind;
  final Size size;
  final Map<String, Object?> data;
  final ValueGetter<Map<String, Object?>>? loadData;
  final Listenable? dataChanges;
  final Widget? child;
  final Widget Function(BuildContext context, VoidCallback? onTap)? builder;
  final VoidCallback? onTap;
  final bool openOnTap;
  final bool hoverOpens;
  final Color? seedColor;

  @override
  State<BarHoverCard> createState() => _BarHoverCardState();
}

class _BarHoverCardState extends State<BarHoverCard> {
  Timer? _timer;
  bool _hovered = false;
  bool _shown = false;
  bool _tracking = false;
  Map<String, Object?>? _lastContent;
  Rect? _lastAnchor;
  BarPopup? _popup;

  void _send(Future<void> request) {
    request.catchError((Object error) => debugPrint('Bar card: $error'));
  }

  void _show({bool update = false, bool activated = false}) {
    final popup = _popup;
    if (popup == null || update && popup.openCard.value != widget.kind) return;
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
      if (update) {
        _shown = false;
        _lastAnchor = null;
        _send(popup.hide(kind: widget.kind));
      }
      return;
    }
    final data = {
      ...(widget.loadData?.call() ?? widget.data),
      if (widget.seedColor case final seed?)
        'cardSeed': seed.toARGB32() & 0xFFFFFF,
      'scale': MediaQuery.textScalerOf(context).scale(1),
    };
    final theme = BarPopupScope.themeOf(context);
    final content = {
      'data': data,
      'theme': (
        theme.seedColor,
        theme.styleVariant,
        theme.mode,
        theme.contrast,
      ),
    };
    final anchorChanged = _lastAnchor != anchor;
    final contentChanged = !const DeepCollectionEquality().equals(
      content,
      _lastContent,
    );
    if (update && !anchorChanged && !contentChanged) return;
    _lastAnchor = anchor;
    _lastContent = content;
    final request = update ? popup.update : popup.show;
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
    final popup = _popup;
    if (!widget.hoverOpens && popup?.openCard.value == widget.kind) {
      _send(popup!.hide(kind: widget.kind));
    } else {
      _show(activated: true);
    }
  }

  // An anchor can move on a rendered frame without this widget rebuilding,
  // so follow it for as long as the native side reports this card open.
  // Only the reported state counts: switching cards briefly reports none
  // open, which must not end tracking of the card that is opening.
  void _trackAnchor(Duration _) {
    if (!mounted || _popup?.openCard.value != widget.kind) {
      _tracking = false;
      return;
    }
    _show(update: true);
    WidgetsBinding.instance.addPostFrameCallback(_trackAnchor);
  }

  void _onOpenCard() {
    if (_popup?.openCard.value != widget.kind || _tracking) return;
    _tracking = true;
    WidgetsBinding.instance.addPostFrameCallback(_trackAnchor);
  }

  void _onDataChanged() {
    // The open card already tracks its anchor at the end of each frame.
    if (_popup?.openCard.value == widget.kind) {
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  @override
  void initState() {
    super.initState();
    widget.dataChanges?.addListener(_onDataChanged);
  }

  @override
  void didUpdateWidget(BarHoverCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataChanges == widget.dataChanges) return;
    oldWidget.dataChanges?.removeListener(_onDataChanged);
    widget.dataChanges?.addListener(_onDataChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final popup = BarPopup.maybeOf(context);
    if (_popup == popup) return;
    _popup?.openCard.removeListener(_onOpenCard);
    _popup = popup;
    _popup?.openCard.addListener(_onOpenCard);
    _onOpenCard();
  }

  @override
  void dispose() {
    widget.dataChanges?.removeListener(_onDataChanged);
    _popup?.openCard.removeListener(_onOpenCard);
    _timer?.cancel();
    if (_popup case final popup? when _shown) {
      _send(popup.hide(kind: widget.kind));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) {
      _hovered = true;
      if (_popup case final popup?) _send(popup.enter(kind: widget.kind));
      _timer?.cancel();
      if (widget.hoverOpens) {
        _timer = Timer(const Duration(milliseconds: 300), _show);
      }
    },
    onExit: (_) {
      _hovered = false;
      _timer?.cancel();
      if (_popup case final popup? when _shown) {
        _send(popup.leave(kind: widget.kind));
      }
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
