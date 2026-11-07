import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../popups/bar_card_surface.dart';
import 'media_artwork.dart';

class MediaPreview extends StatelessWidget {
  const MediaPreview({
    super.key,
    required this.data,
    required this.onAction,
    this.styleVariant = .tonalSpot,
    this.seedColor,
    this.pill,
    this.emergence = const AlwaysStoppedAnimation(1),
  });

  final Rect? pill;
  final Animation<double> emergence;

  final DynamicSchemeVariant styleVariant;
  final Color? seedColor;
  final Map<String, Object?> data;
  final ValueChanged<Map<String, Object?>> onAction;

  @override
  Widget build(BuildContext context) {
    final players = _players(data['players']);
    final player = players.firstOrNull;
    final error = _text(data['error']);
    final output = data['output'];
    return MediaArtwork(
      url: _text(player?['artUrl']),
      styleVariant: styleVariant,
      builder: (context, artwork, _) {
        final fallback = Theme.of(context);
        final scheme = BarCardSurface.colors(fallback, seedColor, styleVariant);
        final theme = fallback.copyWith(
          colorScheme: scheme,
          textTheme: fallback.textTheme.apply(
            bodyColor: scheme.onSurface,
            displayColor: scheme.onSurface,
          ),
          primaryTextTheme: fallback.primaryTextTheme.apply(
            bodyColor: scheme.onPrimary,
            displayColor: scheme.onPrimary,
          ),
          iconTheme: fallback.iconTheme.copyWith(color: scheme.onSurface),
          primaryIconTheme: fallback.primaryIconTheme.copyWith(
            color: scheme.onPrimary,
          ),
        );
        return Theme(
          data: theme,
          child: BarCardSurface(
            seedColor: seedColor,
            pill: pill,
            emergence: emergence,
            styleVariant: styleVariant,
            child: Column(
              crossAxisAlignment: .stretch,
              spacing: 16,
              children: [
                _PlayerHeader(players: players, onAction: onAction),
                if (error.isNotEmpty)
                  Text(error, style: TextStyle(color: theme.colorScheme.error)),
                if (player == null && error.isEmpty)
                  const Text('No active player'),
                if (player != null)
                  _PlayerHero(
                    player: player,
                    artwork: artwork,
                    onAction: onAction,
                  ),
                if (player != null)
                  _OutputVolume(
                    output: output is Map ? output : const {},
                    onAction: onAction,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

typedef _Action = ValueChanged<Map<String, Object?>>;

List<Map> _players(Object? value) =>
    value is List ? value.whereType<Map>().toList() : const [];

class _PlayerHeader extends StatelessWidget {
  const _PlayerHeader({required this.players, required this.onAction});

  final List<Map> players;
  final _Action onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final player = players.firstOrNull;
    final playing = player?['status'] == 'Playing';
    return ConstrainedBox(
      constraints: const .new(minHeight: 48),
      child: Align(
        alignment: .centerLeft,
        child: LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            width: constraints.maxWidth,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: .spaceBetween,
              crossAxisAlignment: .center,
              children: [
                Text(
                  'Now playing',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: .w700,
                    color: theme.brightness == .dark
                        ? colors.primaryFixed
                        : colors.onSurface,
                  ),
                ),
                if (player != null)
                  PopupMenuButton<String>(
                    tooltip: 'Select media player',
                    initialValue: _text(player['name']),
                    enabled: players.length > 1,
                    onSelected: (name) =>
                        onAction({'action': 'media.select', 'player': name}),
                    itemBuilder: (context) => [
                      for (final choice in players)
                        PopupMenuItem(
                          value: _text(choice['name']),
                          child: Text(
                            _playerLabel(choice),
                            maxLines: 2,
                            overflow: .ellipsis,
                          ),
                        ),
                    ],
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.secondaryContainer,
                        borderRadius: .circular(999),
                      ),
                      child: Padding(
                        padding: const .fromLTRB(12, 6, 8, 6),
                        child: Row(
                          mainAxisSize: .min,
                          spacing: 6,
                          children: [
                            Semantics(
                              label: playing ? 'Playing' : 'Idle',
                              child: Image.asset(
                                'assets/icons/media-live-dot.png',
                                width: 8,
                                height: 8,
                                color: playing
                                    ? colors.tertiary
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                            ConstrainedBox(
                              constraints: const .new(maxWidth: 140),
                              child: Text(
                                _playerLabel(player),
                                maxLines: 1,
                                overflow: .ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colors.onSecondaryContainer,
                                  fontSize: 12,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.arrow_drop_down,
                              size: 18,
                              color: colors.onSecondaryContainer,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _playerLabel(Map player) =>
    _text(player['identity'], _text(player['name'], 'Media player'));

class _PlayerHero extends StatelessWidget {
  const _PlayerHero({
    required this.player,
    required this.artwork,
    required this.onAction,
  });

  final Map player;
  final ImageProvider? artwork;
  final _Action onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final playing = player['status'] == 'Playing';
    return Material(
      color: colors.primaryContainer,
      borderRadius: .circular(28),
      clipBehavior: .antiAlias,
      child: Padding(
        padding: const .all(20),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 16,
          children: [
            _Track(player: player, artwork: artwork),
            _PlaybackProgress(player: player, onAction: onAction),
            Row(
              mainAxisAlignment: .center,
              spacing: 8,
              children: [
                _transport(
                  colors,
                  Icons.skip_previous,
                  'Previous',
                  'previous',
                  enabled: player['canPrevious'] == true,
                ),
                Flexible(
                  child: _transport(
                    colors,
                    playing ? Icons.pause : Icons.play_arrow,
                    playing ? 'Pause' : 'Play',
                    'playPause',
                    enabled: player['canPlayPause'] == true,
                    primary: true,
                  ),
                ),
                _transport(
                  colors,
                  Icons.skip_next,
                  'Next',
                  'next',
                  enabled: player['canNext'] == true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _transport(
    ColorScheme colors,
    IconData icon,
    String label,
    String action, {
    required bool enabled,
    bool primary = false,
  }) => IconButton.filledTonal(
    onPressed: enabled
        ? () => onAction({'action': 'media.$action', 'player': player['name']})
        : null,
    tooltip: label,
    icon: Icon(icon),
    style: IconButton.styleFrom(
      fixedSize: primary ? const Size(128, 96) : const Size.square(56),
      minimumSize: Size.zero,
      padding: .zero,
      tapTargetSize: .shrinkWrap,
      iconSize: primary ? 32 : 24,
      backgroundColor: primary ? colors.primary : colors.onPrimary,
      foregroundColor: primary ? colors.onPrimary : colors.onPrimaryContainer,
      disabledBackgroundColor: colors.onPrimaryContainer.withValues(
        alpha: 0.12,
      ),
      disabledForegroundColor: colors.onPrimaryContainer.withValues(
        alpha: 0.38,
      ),
      shape: RoundedRectangleBorder(borderRadius: .circular(28)),
    ),
  );
}

class _Track extends StatelessWidget {
  const _Track({required this.player, required this.artwork});

  final Map player;
  final ImageProvider? artwork;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = _text(player['title'], 'Untitled');
    final length = _number(player['lengthSeconds']);
    final eyebrow = [
      if (_text(player['album']) case final album when album.isNotEmpty) album,
      if (length != null) _durationLabel(length),
    ].join(' · ').toUpperCase();
    final fallback = Image.asset(
      'assets/icons/media-artwork.png',
      semanticLabel: 'Artwork unavailable',
    );
    final cover = SizedBox.square(
      dimension: 104,
      child: artwork == null
          ? fallback
          : ClipRRect(
              borderRadius: .circular(16),
              child: Image(
                image: artwork!,
                fit: .cover,
                semanticLabel: 'Cover art for $title',
                errorBuilder: (context, error, stack) => fallback,
              ),
            ),
    );
    final metadata = Column(
      crossAxisAlignment: .start,
      spacing: 4,
      children: [
        if (eyebrow.isNotEmpty)
          Text(
            eyebrow,
            maxLines: 1,
            overflow: .ellipsis,
            style: TextStyle(
              color: colors.onPrimaryContainer,
              fontSize: 11,
              fontWeight: .w500,
              letterSpacing: 0.8,
            ),
          ),
        Text(
          title,
          maxLines: 2,
          overflow: .ellipsis,
          style: TextStyle(
            color: colors.onPrimaryContainer,
            fontSize: 20,
            height: 1.3,
            fontWeight: .w500,
          ),
        ),
        if (_text(player['artist']) case final artist when artist.isNotEmpty)
          Text(
            artist,
            maxLines: 1,
            overflow: .ellipsis,
            style: TextStyle(color: colors.onPrimaryContainer, fontSize: 14),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 228
          ? Row(
              spacing: 16,
              children: [
                cover,
                Expanded(child: metadata),
              ],
            )
          : Column(
              crossAxisAlignment: .start,
              spacing: 12,
              children: [cover, metadata],
            ),
    );
  }
}

class _PlaybackProgress extends StatelessWidget {
  const _PlaybackProgress({required this.player, required this.onAction});

  final Map player;
  final _Action onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final position = _number(player['positionSeconds']);
    final length = _number(player['lengthSeconds']);
    final track = _text(player['seekToken']);
    final known = position != null && length != null && length > 0;
    final seekable = known && track.isNotEmpty;
    return Column(
      spacing: 6,
      children: [
        if (known)
          _MediaSlider(
            key: ValueKey((player['name'], track)),
            label: 'Playback position',
            value: (position / length).clamp(0, 1),
            wave: player['status'] == 'Playing',
            seek: true,
            displayValue: (value) => _time(value * length),
            onCommit: seekable
                ? (value) => onAction({
                    'action': 'media.seek',
                    'player': player['name'],
                    'track': track,
                    'seconds': value * length,
                  })
                : null,
          ),
        Row(
          mainAxisAlignment: .spaceBetween,
          children: [
            Text(
              _time(position),
              style: TextStyle(color: colors.onPrimaryContainer, fontSize: 12),
            ),
            Text(
              _time(length),
              style: TextStyle(color: colors.onPrimaryContainer, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

class _OutputVolume extends StatelessWidget {
  const _OutputVolume({required this.output, required this.onAction});

  final Map output;
  final _Action onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final percent = _number(output['percent']);
    final name = _text(output['name']);
    final muted = output['muted'] == true;
    final description = _text(output['description'], 'Audio output');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: .circular(20),
      ),
      child: Padding(
        padding: const .symmetric(horizontal: 16, vertical: 12),
        child: Row(
          spacing: 12,
          children: [
            Icon(muted ? Icons.volume_off : Icons.volume_up, size: 24),
            Flexible(
              child: Tooltip(
                message: description,
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 2,
                  children: [
                    Text(
                      description,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        height: 1.2,
                      ),
                    ),
                    Text(
                      percent == null
                          ? 'Unavailable'
                          : muted
                          ? 'Muted'
                          : 'Default output',
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        height: 1.2,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: _MediaSlider(
                key: ValueKey(name),
                label: 'Output volume',
                live: true,
                value: ((percent ?? 0) / 100).clamp(0, 1),
                displayValue: (value) => '${(value * 100).round()}%',
                onCommit: percent != null && name.isNotEmpty
                    ? (value) => onAction({
                        'action': 'media.volume',
                        'output': name,
                        'percent': (value * 100).round(),
                      })
                    : null,
              ),
            ),
            Text(
              percent == null ? '—' : '${percent.round()}%',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 14,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaSlider extends StatefulWidget {
  const _MediaSlider({
    super.key,
    required this.label,
    required this.value,
    required this.displayValue,
    required this.onCommit,
    this.seek = false,
    this.wave = false,
    this.live = false,
  });

  final String label;
  final double value;
  final String Function(double) displayValue;
  final ValueChanged<double>? onCommit;
  final bool seek;
  final bool wave;
  final bool live;

  @override
  State<_MediaSlider> createState() => _MediaSliderState();
}

class _MediaSliderState extends State<_MediaSlider> {
  double? _drag;
  ({double value, DateTime committed})? _pending;
  Timer? _pendingTimer;
  Timer? _liveTimer;
  double? _trailing;

  @override
  void didUpdateWidget(covariant _MediaSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_pending case final pending?) {
      if ((widget.value - pending.value).abs() <= 0.005 ||
          DateTime.now().difference(pending.committed) >=
              const Duration(milliseconds: 1500)) {
        _pending = null;
        _pendingTimer?.cancel();
      }
    }
  }

  void _changed(double value) {
    setState(() => _drag = value);
    if (!widget.live) return;
    if (_liveTimer != null) {
      _trailing = value;
      return;
    }
    widget.onCommit?.call(value);
    _liveTimer = Timer(const Duration(milliseconds: 60), _sendTrailing);
  }

  void _sendTrailing() {
    _liveTimer = null;
    final value = _trailing;
    _trailing = null;
    if (value == null) return;
    widget.onCommit?.call(value);
    _liveTimer = Timer(const Duration(milliseconds: 60), _sendTrailing);
  }

  void _committed(double value) {
    _liveTimer?.cancel();
    _liveTimer = null;
    _trailing = null;
    _pendingTimer?.cancel();
    setState(() {
      _drag = null;
      _pending = (value: value, committed: DateTime.now());
    });
    _pendingTimer = Timer(const Duration(milliseconds: 1500), () {
      setState(() => _pending = null);
    });
    widget.onCommit?.call(value);
  }

  @override
  void dispose() {
    _pendingTimer?.cancel();
    _liveTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final seek = widget.seek;
    final active = seek && Theme.of(context).brightness == .light
        ? colors.onPrimaryContainer
        : colors.primary;
    final inactive = seek
        ? Color.alphaBlend(
            colors.onPrimary.withValues(alpha: 0.65),
            colors.primaryContainer,
          )
        : colors.secondaryContainer;
    return Semantics(
      label: widget.label,
      child: SizedBox(
        height: seek ? 24 : 32,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: seek ? 8 : 16,
            trackGap: seek ? 3 : 6,
            padding: const .symmetric(horizontal: 2),
            trackShape: seek
                ? _SeekTrack(wave: widget.wave)
                : const GappedSliderTrackShape(),
            thumbShape: const HandleThumbShape(),
            thumbSize: .all(Size(4, seek ? 24 : 32)),
            thumbColor: seek ? colors.onPrimaryContainer : active,
            activeTrackColor: active,
            inactiveTrackColor: inactive,
            disabledActiveTrackColor: widget.seek ? active : colors.outline,
            disabledInactiveTrackColor: inactive,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            value: widget.onCommit == null
                ? widget.value
                : _drag ?? _pending?.value ?? widget.value,
            semanticFormatterCallback: widget.displayValue,
            onChanged: widget.onCommit == null ? null : _changed,
            onChangeEnd: widget.onCommit == null ? null : _committed,
          ),
        ),
      ),
    );
  }
}

class _SeekTrack extends GappedSliderTrackShape {
  const _SeekTrack({required this.wave});

  final bool wave;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    if (!wave) {
      super.paint(
        context,
        offset,
        parentBox: parentBox,
        sliderTheme: sliderTheme,
        enableAnimation: enableAnimation,
        textDirection: textDirection,
        thumbCenter: thumbCenter,
        isEnabled: isEnabled,
      );
      return;
    }
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
    );
    final rtl = textDirection == .rtl;
    final width = rect.width;
    final progress =
        (rtl ? rect.right - thumbCenter.dx : thumbCenter.dx - rect.left).clamp(
          0.0,
          width,
        );
    final canvas = context.canvas
      ..save()
      ..translate(rtl ? rect.right : rect.left, rect.center.dy)
      ..scale(rtl ? -1 : 1);
    final start = progress + 3;
    if (start < width) {
      canvas.drawRRect(
        RRect.fromLTRBR(start, -4, width, 4, const Radius.circular(4)),
        Paint()..color = sliderTheme.inactiveTrackColor!,
      );
      if (start < width - 4) {
        canvas.drawCircle(
          Offset(width - 4, 0),
          2,
          Paint()..color = sliderTheme.thumbColor!,
        );
      }
    }
    final end = progress - 3;
    if (end > 0) {
      final path = Path()..moveTo(0, 0);
      for (var x = 1.0; x < end; x++) {
        path.lineTo(x, math.sin(x * math.pi / 20) * 3);
      }
      path.lineTo(end, math.sin(end * math.pi / 20) * 3);
      canvas.drawPath(
        path,
        Paint()
          ..color = sliderTheme.activeTrackColor!
          ..style = .stroke
          ..strokeWidth = 8
          ..strokeCap = .round,
      );
    }
    canvas.restore();
  }
}

String _durationLabel(double seconds) {
  final minutes = (seconds / 60).floor();
  if (minutes == 0) return '${seconds.floor()}s';
  if (minutes < 60) return '${minutes}m';
  return '${minutes ~/ 60}h ${minutes % 60}m';
}

String _text(Object? value, [String fallback = '']) =>
    value is String && value.isNotEmpty ? value : fallback;

double? _number(Object? value) =>
    value is num && value.isFinite && value >= 0 ? value.toDouble() : null;

String _time(double? seconds) {
  if (seconds == null) return '—';
  final duration = Duration(seconds: seconds.floor());
  final tail = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (duration.inHours == 0) return '${duration.inMinutes}:$tail';
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  return '${duration.inHours}:$minutes:$tail';
}
