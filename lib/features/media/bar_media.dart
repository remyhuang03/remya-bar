import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../widgets/bar_pill.dart';
import '../popups/bar_popup.dart';
import '../system/system_backend.dart';
import '../system/system_popup_data.dart';
import 'media_artwork.dart';

class BarMedia extends StatelessWidget {
  const BarMedia({
    super.key,
    required this.players,
    this.output = const {},
    this.error,
    this.onAction,
  });

  static const width = 204.0;
  final List<MediaPlayerSnapshot> players;
  final Map<String, Object?> output;
  final String? error;
  final Future<void> Function(String player, String action)? onAction;

  @override
  Widget build(BuildContext context) {
    final player = players.firstOrNull;
    if (player == null) return const SizedBox.shrink();
    final playing = player.playbackStatus == 'Playing';
    final toggle = onAction;
    return MediaArtwork(
      url: player.artUrl,
      styleVariant: BarPopupScope.themeOf(context).styleVariant,
      builder: (_, _, scheme) => _MediaPill(
        card: BarPillCard(
          kind: 'media',
          seedColor: scheme?.primary,
          size: const Size(420, 505),
          data: {
            ...mediaPopupData(players, error: error),
            'output': output,
          },
        ),
        scheme: scheme,
        title: player.title.isEmpty ? player.identity : player.title,
        playing: playing,
        progress: switch ((player.positionSeconds, player.lengthSeconds)) {
          (final position?, final length?) when length > 0 =>
            (position / length).clamp(0, 1),
          _ => 0,
        },
        onToggle:
            toggle != null &&
                player.canControl &&
                (playing ? player.canPause : player.canPlay)
            ? () async {
                try {
                  await toggle(player.busName, 'playPause');
                } catch (error) {
                  debugPrint('Media action: $error');
                }
              }
            : null,
      ),
    );
  }
}

class _MediaPill extends StatelessWidget {
  const _MediaPill({
    required this.title,
    required this.playing,
    required this.progress,
    required this.onToggle,
    required this.scheme,
    required this.card,
  });

  final String title;
  final bool playing;
  final double progress;
  final VoidCallback? onToggle;
  final ColorScheme? scheme;
  final BarPillCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = scheme ?? theme.colorScheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    return BarPill(
      scheme: colors,
      card: card,
      semanticsLabel: title,
      semanticsHint: onToggle == null
          ? null
          : playing
          ? 'Pause'
          : 'Play',
      onTap: onToggle,
      padding: const .symmetric(horizontal: 16),
      expandedPadding: const .fromLTRB(8, 0, 14, 0),
      background: FractionallySizedBox(
        alignment: .centerLeft,
        widthFactor: progress,
        child: ColoredBox(
          color: playing
              ? colors.secondaryContainer
              : colors.surfaceContainerHighest,
        ),
      ),
      builder: (context, state) {
        final foreground = state.pressed
            ? state.foreground
            : !playing
            ? colors.onSurfaceVariant
            : state.expanded && theme.brightness == .dark
            ? colors.primaryFixed
            : colors.primary;
        return Row(
          spacing: 8,
          children: [
            AnimatedContainer(
              duration: duration,
              width: state.expanded ? 28 : 24,
              height: state.expanded ? 28 : 24,
              decoration: BoxDecoration(
                color: state.expanded ? colors.primary : Colors.transparent,
                borderRadius: .circular(
                  state.pressed
                      ? 10
                      : state.expanded
                      ? 14
                      : 12,
                ),
              ),
              child: Icon(
                !state.expanded
                    ? Icons.music_note
                    : playing
                    ? Icons.pause
                    : Icons.play_arrow,
                size: 20,
                color: state.expanded ? colors.onPrimary : foreground,
              ),
            ),
            Expanded(
              child: ExcludeSemantics(
                child: _MediaTitle(
                  text: title,
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: foreground,
                    fontSize: 15,
                    height: 1.25,
                    fontWeight: .w500,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

enum _MarqueeProbe { baseline, boundary, cached, noMask, flow, hz30 }

class _MediaTitle extends StatelessWidget {
  const _MediaTitle({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      var title = text;
      var probe = _MarqueeProbe.baseline;
      if (Platform.environment['REMYA_BAR_PERF'] == '1' &&
          text.startsWith('BAR_PERF:')) {
        final separator = text.indexOf(':', 'BAR_PERF:'.length);
        if (separator != -1) {
          probe = _MarqueeProbe.values.byName(text.substring(9, separator));
          title = text.substring(separator + 1);
        }
      }
      final label = Text(title, style: style, maxLines: 1, softWrap: false);
      final direction = Directionality.of(context);
      final painter = TextPainter(
        text: TextSpan(text: title, style: style),
        textDirection: direction,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final textWidth = painter.width;
      painter.dispose();
      if (textWidth <= constraints.maxWidth ||
          MediaQuery.disableAnimationsOf(context)) {
        return Text(title, style: style, maxLines: 1, overflow: .ellipsis);
      }
      return ValueListenableBuilder<bool>(
        valueListenable: BarPopup.keyboardOpen,
        builder: (_, keyboardOpen, child) =>
            TickerMode(enabled: !keyboardOpen, child: child!),
        child: _ScrollingTitle(
          key: ValueKey((title, probe)),
          probe: probe,
          textWidth: textWidth,
          direction: direction,
          child: label,
        ),
      );
    },
  );
}

class _ScrollingTitle extends StatefulWidget {
  const _ScrollingTitle({
    super.key,
    required this.textWidth,
    required this.direction,
    required this.child,
    required this.probe,
  });

  final _MarqueeProbe probe;
  final double textWidth;
  final TextDirection direction;
  final Widget child;

  @override
  State<_ScrollingTitle> createState() => _ScrollingTitleState();
}

class _ScrollingTitleState extends State<_ScrollingTitle>
    with SingleTickerProviderStateMixin {
  static const _gap = 32.0;
  static const _speed = 16.0;
  late final AnimationController _scroll = AnimationController(vsync: this);

  final _fade = ValueNotifier(false);
  final _limited = ValueNotifier(0.0);
  final _elapsed = Stopwatch();
  Timer? _timer;
  Rect? _maskBounds;
  final _shaders = <bool, Shader>{};

  double get _distance => widget.textWidth + _gap;

  @override
  void initState() {
    super.initState();
    if (widget.probe == .hz30) {
      _elapsed.start();
    } else {
      if (widget.probe == .flow) _scroll.addListener(_updateFade);
      _scroll.repeat(period: _period);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.probe != .hz30) return;
    _timer?.cancel();
    _timer = TickerMode.valuesOf(context).enabled
        ? Timer.periodic(const Duration(microseconds: 33333), (_) {
            final micros = _elapsed.elapsedMicroseconds;
            _limited.value =
                (micros % _period.inMicroseconds) / _period.inMicroseconds;
          })
        : null;
  }

  bool _leadingFade(double offset) => offset > 0 && offset < widget.textWidth;

  void _updateFade() {
    _fade.value = _leadingFade(_scroll.value * _distance);
  }

  Duration get _period =>
      Duration(milliseconds: (_distance / _speed * 1000).round());

  @override
  void didUpdateWidget(_ScrollingTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.direction != oldWidget.direction) _shaders.clear();
    if (widget.probe != .hz30 &&
        (widget.textWidth - oldWidget.textWidth).abs() >= 0.5) {
      _scroll.repeat(period: _period);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _limited.dispose();
    _fade.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Shader _mask(Rect bounds, bool leadingFade) {
    Shader create() {
      final leftToRight = widget.direction == .ltr;
      return LinearGradient(
        begin: leftToRight ? .centerLeft : .centerRight,
        end: leftToRight ? .centerRight : .centerLeft,
        colors: [
          leadingFade ? Colors.transparent : Colors.white,
          Colors.white,
          Colors.white,
          Colors.transparent,
        ],
        stops: const [0, 0.12, 0.88, 1],
      ).createShader(bounds);
    }

    if (widget.probe != .cached && widget.probe != .flow) return create();
    if (bounds != _maskBounds) {
      _maskBounds = bounds;
      _shaders.clear();
    }
    return _shaders.putIfAbsent(leadingFade, create);
  }

  Widget _masked(Widget child, bool leadingFade) => ShaderMask(
    blendMode: .dstIn,
    shaderCallback: (bounds) => _mask(bounds, leadingFade),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final strip = Row(
      mainAxisSize: .min,
      spacing: _gap,
      textDirection: widget.direction,
      children: [widget.child, widget.child],
    );
    if (widget.probe == .flow) {
      return ClipRect(
        child: ValueListenableBuilder<bool>(
          valueListenable: _fade,
          child: Flow(
            clipBehavior: .none,
            delegate: _TitleFlow(_scroll, _distance, widget.direction),
            children: [strip],
          ),
          builder: (_, leadingFade, child) => _masked(child!, leadingFade),
        ),
      );
    }
    final phase = widget.probe == .hz30 ? _limited : _scroll;
    return AnimatedBuilder(
      animation: phase,
      child: widget.probe == .boundary ? RepaintBoundary(child: strip) : strip,
      builder: (_, child) {
        final offset = phase.value * _distance;
        final leftToRight = widget.direction == .ltr;
        final translated = OverflowBox(
          maxWidth: double.infinity,
          alignment: leftToRight ? .centerLeft : .centerRight,
          child: Transform.translate(
            offset: Offset(leftToRight ? -offset : offset, 0),
            child: child,
          ),
        );
        return ClipRect(
          child: widget.probe == .noMask
              ? translated
              : _masked(translated, _leadingFade(offset)),
        );
      },
    );
  }
}

class _TitleFlow extends FlowDelegate {
  _TitleFlow(this.phase, this.distance, this.direction) : super(repaint: phase);

  final Animation<double> phase;
  final double distance;
  final TextDirection direction;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      BoxConstraints(maxHeight: constraints.maxHeight);

  @override
  void paintChildren(FlowPaintingContext context) {
    final child = context.getChildSize(0)!;
    final offset = phase.value * distance;
    final x = direction == .ltr
        ? -offset
        : context.size.width - child.width + offset;
    context.paintChild(
      0,
      transform: Matrix4.translationValues(
        x,
        (context.size.height - child.height) / 2,
        0,
      ),
    );
  }

  @override
  bool shouldRepaint(_TitleFlow oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.distance != distance ||
      oldDelegate.direction != direction;
}
