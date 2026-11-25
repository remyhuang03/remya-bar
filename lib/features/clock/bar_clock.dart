import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../widgets/bar_pill.dart';
import 'clock_card_controls.dart';
import 'clock_capsule.dart';

final barClockSource = BarClockSource();

class BarClockSource {
  BarClockSource({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final _listeners = <void Function(DateTime), bool>{};
  Timer? _timer;
  DateTime? _lastTick;

  DateTime attach(void Function(DateTime) listener, {required bool seconds}) {
    _listeners[listener] = seconds;
    final now = _now();
    _lastTick ??= now;
    _schedule(now);
    return now;
  }

  void detach(void Function(DateTime) listener) {
    if (_listeners.remove(listener) != null) _schedule(_now());
  }

  void _schedule(DateTime now) {
    _timer?.cancel();
    if (_listeners.isEmpty) {
      _lastTick = null;
      return;
    }
    final offset = now.millisecond * 1000 + now.microsecond;
    final delay = _listeners.containsValue(true)
        ? Duration.microsecondsPerSecond - offset
        : (60 - now.second) * Duration.microsecondsPerSecond - offset;
    _timer = Timer(Duration(microseconds: delay), () {
      final next = _now();
      final previous = _lastTick!;
      _lastTick = next;
      final minuteChanged =
          previous.difference(next).inMinutes != 0 ||
          previous.minute != next.minute ||
          previous.timeZoneOffset != next.timeZoneOffset;
      for (final MapEntry(key: listener, value: seconds)
          in _listeners.entries) {
        if (seconds || minuteChanged) listener(next);
      }
      _schedule(next);
    });
  }
}

class BarClock extends StatefulWidget {
  const BarClock({super.key, this.showSeconds = true});

  final bool showSeconds;

  @override
  State<BarClock> createState() => _BarClockState();
}

class _BarClockState extends State<BarClock> {
  DateTime _now = DateTime.now();
  bool _visible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible == _visible) return;
    _visible = visible;
    if (visible) {
      _subscribe();
    } else {
      barClockSource.detach(_update);
    }
  }

  @override
  void didUpdateWidget(BarClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_visible && oldWidget.showSeconds != widget.showSeconds) _subscribe();
  }

  void _subscribe() =>
      _now = barClockSource.attach(_update, seconds: widget.showSeconds);

  void _update(DateTime now) => setState(() => _now = now);

  @override
  void dispose() {
    barClockSource.detach(_update);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BarPill(
    card: BarPillCard(
      kind: 'datetime',
      size: const Size(clockCardWideWidth, clockCardMaxHeight),
      openOnTap: true,
    ),
    builder: (context, state) => ClockCapsule(
      time: _now,
      showSeconds: widget.showSeconds,
      foreground: state.pressed
          ? state.foreground
          : Theme.of(context).colorScheme.primary,
    ),
  );
}
