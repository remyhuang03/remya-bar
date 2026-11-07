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

class _MediaTitle extends StatelessWidget {
  const _MediaTitle({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final label = Text(text, style: style, maxLines: 1, softWrap: false);
      final direction = Directionality.of(context);
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final textWidth = painter.width;
      painter.dispose();
      if (textWidth <= constraints.maxWidth ||
          MediaQuery.disableAnimationsOf(context)) {
        return Text(text, style: style, maxLines: 1, overflow: .ellipsis);
      }
      return _ScrollingTitle(
        key: ValueKey(text),
        textWidth: textWidth,
        direction: direction,
        child: label,
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
  });

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

  double get _distance => widget.textWidth + _gap;

  @override
  void initState() {
    super.initState();
    _scroll.repeat(period: _period);
  }

  Duration get _period =>
      Duration(milliseconds: (_distance / _speed * 1000).round());

  @override
  void didUpdateWidget(_ScrollingTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.textWidth - oldWidget.textWidth).abs() >= 0.5) {
      _scroll.repeat(period: _period);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _scroll,
    child: Row(
      mainAxisSize: .min,
      spacing: _gap,
      textDirection: widget.direction,
      children: [widget.child, widget.child],
    ),
    builder: (context, child) {
      final offset = _scroll.value * _distance;
      final leftToRight = widget.direction == .ltr;
      return ClipRect(
        child: ShaderMask(
          blendMode: .dstIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: leftToRight ? .centerLeft : .centerRight,
            end: leftToRight ? .centerRight : .centerLeft,
            colors: [
              if (offset > 0 && offset < widget.textWidth)
                Colors.transparent
              else
                Colors.white,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: const [0, 0.12, 0.88, 1],
          ).createShader(bounds),
          child: OverflowBox(
            maxWidth: double.infinity,
            alignment: leftToRight ? .centerLeft : .centerRight,
            child: Transform.translate(
              offset: Offset(leftToRight ? -offset : offset, 0),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}
