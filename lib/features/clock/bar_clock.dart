import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../widgets/bar_pill.dart';
import 'clock_capsule.dart';

class BarClock extends StatefulWidget {
  const BarClock({super.key, this.showSeconds = true});

  final bool showSeconds;

  @override
  State<BarClock> createState() => _BarClockState();
}

class _BarClockState extends State<BarClock> {
  late DateTime _now;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() {
    _now = DateTime.now();
    // Re-align each tick after clock adjustments instead of accumulating drift.
    _timer = Timer(
      Duration(
        microseconds: 1000000 - _now.microsecond - _now.millisecond * 1000,
      ),
      () => setState(_tick),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BarPill(
    card: BarPillCard(
      kind: 'datetime',
      size: const Size(420, 673),
      openOnTap: true,
      data: {
        'unixMillis': _now.millisecondsSinceEpoch,
        'utcOffsetSeconds': _now.timeZoneOffset.inSeconds,
      },
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
