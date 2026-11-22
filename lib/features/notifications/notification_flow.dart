import 'package:material_ui/material_ui.dart';

/// Keeps removed rows around long enough to animate their departure and reflow.
class NotificationFlow extends StatefulWidget {
  const NotificationFlow({
    super.key,
    required this.children,
    required this.spacing,
    this.slideOut = 24,
  });

  static const exitDuration = Duration(milliseconds: 300);

  final List<Widget> children;
  final double spacing;
  final double slideOut;

  @override
  State<NotificationFlow> createState() => _NotificationFlowState();
}

class _NotificationFlowState extends State<NotificationFlow> {
  final _departing = <Key, Widget>{};
  List<Key> _order = [];

  @override
  void initState() {
    super.initState();
    _order = [for (final child in widget.children) child.key!];
  }

  @override
  void didUpdateWidget(NotificationFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final keys = [for (final child in widget.children) child.key!];
    final active = keys.toSet();
    _departing.removeWhere((key, _) => active.contains(key));
    for (final child in oldWidget.children) {
      final key = child.key!;
      if (!active.contains(key)) _departing[key] = child;
    }
    Key? next;
    for (final key in _order.reversed) {
      if (active.contains(key)) {
        next = key;
      } else if (_departing.containsKey(key)) {
        keys.insert(next == null ? keys.length : keys.indexOf(next), key);
        next = key;
      }
    }
    _order = keys;
  }

  @override
  Widget build(BuildContext context) {
    final active = {for (final child in widget.children) child.key!: child};
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        for (final (index, key) in _order.indexed)
          TweenAnimationBuilder<double>(
            key: key,
            duration: active.containsKey(key)
                ? Duration.zero
                : reduceMotion
                ? const Duration(milliseconds: 200)
                : NotificationFlow.exitDuration,
            tween: Tween(begin: 1, end: active.containsKey(key) ? 1 : 0),
            onEnd: () {
              if (_departing.remove(key) != null) {
                setState(() => _order.remove(key));
              }
            },
            builder: (context, progress, child) {
              final fade = reduceMotion
                  ? progress
                  : (progress * 1.5 - .5).clamp(0.0, 1.0);
              final opacity =
                  1 - Easing.emphasizedAccelerate.transform(1 - fade);
              return ClipRect(
                clipBehavior: progress == 1 ? .none : .hardEdge,
                child: Align(
                  alignment: .topCenter,
                  heightFactor: reduceMotion ? 1 : progress,
                  child: Opacity(
                    opacity: opacity,
                    child: Transform.translate(
                      offset: Offset(
                        reduceMotion ? 0 : (1 - opacity) * widget.slideOut,
                        0,
                      ),
                      child: child,
                    ),
                  ),
                ),
              );
            },
            child: Padding(
              padding: .only(
                bottom: index == _order.length - 1 ? 0 : widget.spacing,
              ),
              child: ExcludeFocus(
                excluding: !active.containsKey(key),
                child: ExcludeSemantics(
                  excluding: !active.containsKey(key),
                  child: IgnorePointer(
                    ignoring: !active.containsKey(key),
                    child: active[key] ?? _departing[key]!,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
