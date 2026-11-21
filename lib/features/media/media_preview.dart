import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../widgets/percent_text.dart';
import '../popups/bar_card_surface.dart';
import '../popups/bar_popup.dart';
import 'media_artwork.dart';
import 'media_slider.dart';

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
        final scheme = BarCardSurface.colors(
          fallback,
          seedColor,
          styleVariant,
          contrastLevel: BarPopupScope.contrastOf(context),
        );
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
            child: BarCardSections(
              header: _PlayerHeader(players: players, onAction: onAction),
              children: [
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
    return Row(
      crossAxisAlignment: .center,
      spacing: 8,
      children: [
        Expanded(
          child: Text(
            'Now playing',
            maxLines: 1,
            overflow: .ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: .w700,
              height: 30 / 24,
              leadingDistribution: .even,
              color: theme.brightness == .dark
                  ? colors.primaryFixed
                  : colors.onSurface,
            ),
          ),
        ),
        if (players.length > 1)
          PopupMenuButton<String>(
            tooltip: 'Select media player',
            position: .under,
            borderRadius: .circular(999),
            initialValue: _text(player!['name']),
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

class _PlaybackProgress extends StatefulWidget {
  const _PlaybackProgress({required this.player, required this.onAction});

  final Map player;
  final _Action onAction;

  @override
  State<_PlaybackProgress> createState() => _PlaybackProgressState();
}

class _PlaybackProgressState extends State<_PlaybackProgress> {
  Timer? _timer;
  DateTime _capturedAt = DateTime.now();

  double? get _basePosition => _number(widget.player['positionSeconds']);
  double? get _length => _number(widget.player['lengthSeconds']);
  bool get _playing => widget.player['status'] == 'Playing';
  bool get _known => _basePosition != null && _length != null && _length! > 0;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(_PlaybackProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_number(widget.player['positionSeconds']) !=
            _number(oldWidget.player['positionSeconds']) ||
        widget.player['status'] != oldWidget.player['status'] ||
        widget.player['seekToken'] != oldWidget.player['seekToken'] ||
        widget.player['name'] != oldWidget.player['name']) {
      _capturedAt = DateTime.now();
      _syncTimer();
    }
  }

  void _syncTimer() {
    if (_playing && _known) {
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final basePosition = _basePosition;
    final length = _length;
    final track = _text(widget.player['seekToken']);
    final known = _known;
    final position = known && _playing
        ? (basePosition! +
                  DateTime.now().difference(_capturedAt).inMilliseconds / 1000)
              .clamp(0.0, length!)
        : basePosition;
    final seekable = known && track.isNotEmpty;
    return Column(
      spacing: 6,
      children: [
        if (known)
          MediaSlider(
            key: ValueKey((widget.player['name'], track)),
            label: 'Playback position',
            value: (position! / length!).clamp(0, 1),
            wave: _playing,
            seek: true,
            displayValue: (value) => _time(value * length),
            onCommit: seekable
                ? (value) => widget.onAction({
                    'action': 'media.seek',
                    'player': widget.player['name'],
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
              child: MediaSlider(
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
            Builder(
              builder: (context) {
                final style = theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  height: 1.2,
                );
                return percent == null
                    ? Text('—', style: style)
                    : PercentText('${percent.round()}', style: style);
              },
            ),
          ],
        ),
      ),
    );
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
