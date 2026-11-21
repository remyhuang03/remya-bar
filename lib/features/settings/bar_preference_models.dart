import 'dart:convert';

const barLayoutSettingId = 'remya-bar.layout';

/// Pill IDs in their default order. The service rejects any other ID.
const barPillIds = [
  'notifications',
  'window',
  'resources',
  'media',
  'workspaces',
  'clock',
  'tray',
  'ai-usage',
  'weather',
  'battery',
  'sidebar',
];

/// Pills that open a detail card. Each opens it on hover or on click; the
/// notification and quick settings pills toggle their own panels instead.
const barCardPillIds = [
  'resources',
  'media',
  'clock',
  'ai-usage',
  'weather',
  'battery',
];

/// System resources metrics in display order.
const barResourceIds = ['cpu', 'memory', 'gpu', 'network'];

/// Bar-owned pill groups and per-pill options.
class BarLayout {
  const BarLayout({
    required this.groups,
    this.workspaceCount = 8,
    this.resources = barResourceIds,
    this.windowAppName = false,
    this.mediaMarquee = false,
    this.clickCards = const [],
    this.center,
  });

  static const defaults = BarLayout(
    groups: [
      ['notifications', 'window', 'resources'],
      ['workspaces', 'clock'],
      ['tray'],
      ['ai-usage', 'weather', 'battery', 'sidebar'],
    ],
    resources: ['cpu', 'memory', 'network'],
    center: 1,
  );

  /// Ordered groups; a pill missing from every group is hidden.
  final List<List<String>> groups;
  final int workspaceCount;
  final List<String> resources;
  final bool windowAppName;
  final bool mediaMarquee;

  /// Card pills that open their card on click; the others open on hover.
  final List<String> clickCards;

  /// Index of the group centered on the bar, or null. Groups before and after
  /// it are spaced evenly within their own side.
  final int? center;

  factory BarLayout.fromJson(Object? json) {
    if (json
        case {
          'groups': final List groups,
          'workspace-count': final int workspaceCount,
          'resources': final List resources,
          'window-app-name': final bool windowAppName,
          'media-marquee': final bool mediaMarquee,
        }
        when json['center'] is int? && json['click-cards'] is List?) {
      return .new(
        groups: [for (final group in groups) List<String>.from(group as List)],
        workspaceCount: workspaceCount,
        resources: List<String>.from(resources),
        windowAppName: windowAppName,
        mediaMarquee: mediaMarquee,
        clickCards: switch (json['click-cards']) {
          final List cards => List<String>.from(cards),
          _ => const [],
        },
        center: json['center'] as int?,
      );
    }
    throw const FormatException('Invalid Remy\'a Bar layout');
  }

  Map<String, Object> toJson() => {
    'groups': groups,
    'workspace-count': workspaceCount,
    'resources': resources,
    'window-app-name': windowAppName,
    'media-marquee': mediaMarquee,
    'click-cards': clickCards,
    'center': ?center,
  };

  List<String> get hidden => [
    for (final id in barPillIds)
      if (!groups.any((group) => group.contains(id))) id,
  ];

  BarLayout copyWith({
    int? workspaceCount,
    List<String>? resources,
    bool? windowAppName,
    bool? mediaMarquee,
    List<String>? clickCards,
  }) => .new(
    groups: groups,
    workspaceCount: workspaceCount ?? this.workspaceCount,
    resources: resources ?? this.resources,
    windowAppName: windowAppName ?? this.windowAppName,
    mediaMarquee: mediaMarquee ?? this.mediaMarquee,
    clickCards: clickCards ?? this.clickCards,
    center: center,
  );

  /// Returns this layout with new groups and centered group, keeping options.
  BarLayout withGroups(List<List<String>> groups, {int? center}) => .new(
    groups: groups,
    workspaceCount: workspaceCount,
    resources: resources,
    windowAppName: windowAppName,
    mediaMarquee: mediaMarquee,
    clickCards: clickCards,
    center: center,
  );

  /// Applies [edit] to copies of the groups, then drops emptied groups while
  /// the centered group keeps its flag.
  BarLayout _edit(void Function(List<List<String>> groups) edit) {
    final next = [
      for (final pills in groups) [...pills],
    ];
    final centered = center == null ? null : next[center!];
    edit(next);
    final kept = [
      for (final pills in next)
        if (pills.isNotEmpty) pills,
    ];
    final index = kept.indexWhere((pills) => identical(pills, centered));
    return withGroups(kept, center: index < 0 ? null : index);
  }

  /// Moves [id] (visible or hidden) into [group] at [index], appending when
  /// null. A [group] equal to the group count adds a new last group.
  BarLayout movePill(String id, int group, [int? index]) => _edit((next) {
    for (final pills in next) {
      pills.remove(id);
    }
    if (group == next.length) next.add([]);
    final target = next[group];
    target.insert((index ?? target.length).clamp(0, target.length), id);
  });

  /// Moves [id] into a new group of its own at [group], counted before the
  /// pill leaves its old group.
  BarLayout insertGroup(String id, int group) => _edit((next) {
    for (final pills in next) {
      pills.remove(id);
    }
    next.insert(group.clamp(0, next.length), [id]);
  });

  BarLayout hidePill(String id) => _edit((next) {
    for (final pills in next) {
      pills.remove(id);
    }
  });

  /// Hides every pill of [group] and removes it.
  BarLayout removeGroup(int group) => _edit((next) => next[group].clear());

  /// Moves [from] to position [to] counted after its removal.
  BarLayout moveGroup(int from, int to) =>
      _edit((next) => next.insert(to, next.removeAt(from)));

  BarLayout withCenter(int? group) => withGroups(groups, center: group);

  @override
  bool operator ==(Object other) =>
      other is BarLayout && jsonEncode(this) == jsonEncode(other);

  @override
  int get hashCode => jsonEncode(this).hashCode;
}

const barResourceRefreshChoices = [500, 1000, 2000, 5000, 10000];
const barResourceTimeRangeChoices = [30, 60, 120, 300, 600];

/// Refresh interval and history window for the System card, owned by Bar.
class BarResourcePreferences {
  const BarResourcePreferences({
    this.refreshIntervalMs = 1000,
    this.timeRangeSeconds = 60,
  });

  static const defaults = BarResourcePreferences();

  final int refreshIntervalMs;
  final int timeRangeSeconds;

  factory BarResourcePreferences.fromJson(Object? json) {
    if (json
        case {
          'refresh-interval-ms': final int refreshIntervalMs,
          'time-range-seconds': final int timeRangeSeconds,
        }
        when barResourceRefreshChoices.contains(refreshIntervalMs) &&
            barResourceTimeRangeChoices.contains(timeRangeSeconds)) {
      return .new(
        refreshIntervalMs: refreshIntervalMs,
        timeRangeSeconds: timeRangeSeconds,
      );
    }
    throw const FormatException("Invalid Remy'a Bar system card preferences");
  }

  Map<String, Object> toJson() => {
    'refresh-interval-ms': refreshIntervalMs,
    'time-range-seconds': timeRangeSeconds,
  };

  BarResourcePreferences copyWith({
    int? refreshIntervalMs,
    int? timeRangeSeconds,
  }) => .new(
    refreshIntervalMs: refreshIntervalMs ?? this.refreshIntervalMs,
    timeRangeSeconds: timeRangeSeconds ?? this.timeRangeSeconds,
  );

  @override
  bool operator ==(Object other) =>
      other is BarResourcePreferences &&
      other.refreshIntervalMs == refreshIntervalMs &&
      other.timeRangeSeconds == timeRangeSeconds;

  @override
  int get hashCode => Object.hash(refreshIntervalMs, timeRangeSeconds);
}

const barOsdSettingId = 'remya-bar.osd';
const barOsdSettingIds = {barOsdSettingId};

/// Preferences of the Remy'a Bar on-screen display, owned by Bar.
class BarOsdPreferences {
  const BarOsdPreferences({
    this.volumeStep = 3,
    this.volumeMax = 150,
    this.brightnessStep = 3,
    this.gammaMin = 10,
  });

  final int volumeStep;

  /// Highest output volume percentage reachable from the bar (100–150).
  final int volumeMax;
  final int brightnessStep;
  final int gammaMin;

  factory BarOsdPreferences.fromJson(Object? json) {
    if (json case {
      'volume_step': final int volumeStep,
      'volume_max': final int volumeMax,
      'brightness_step': final int brightnessStep,
      'gamma_min': final int gammaMin,
    }) {
      return .new(
        volumeStep: volumeStep,
        volumeMax: volumeMax,
        brightnessStep: brightnessStep,
        gammaMin: gammaMin,
      );
    }
    throw const FormatException("Invalid Remy'a Bar OSD preferences");
  }

  Map<String, Object> toJson() => {
    'volume_step': volumeStep,
    'volume_max': volumeMax,
    'brightness_step': brightnessStep,
    'gamma_min': gammaMin,
  };

  @override
  bool operator ==(Object other) =>
      other is BarOsdPreferences && jsonEncode(this) == jsonEncode(other);

  @override
  int get hashCode => jsonEncode(this).hashCode;
}

const notificationSettingIds = {
  'remya-bar.notifications',
  'remya-bar.quiet-schedule',
  'remya-bar.priority-notifications',
};

const quietRepeats = ['every-day', 'weekdays', 'weekends'];

/// An app whose notifications break through Do Not Disturb, matched by
/// desktop entry ID or app name.
typedef PriorityApp = ({String id, String name});

/// Preferences of the desktop notification service, owned by Bar.
class NotificationPreferences {
  const NotificationPreferences({
    this.doNotDisturb = false,
    this.popupDuration = 5,
    this.sounds = true,
    this.schedule = false,
    this.scheduleStart = '22:00',
    this.scheduleEnd = '07:00',
    this.scheduleRepeat = 'every-day',
    this.fullscreen = false,
    this.priorityCalls = true,
    this.priorityApps = const [],
  });

  final bool doNotDisturb;
  final int popupDuration;
  final bool sounds;
  final bool schedule;
  final String scheduleStart;
  final String scheduleEnd;
  final String scheduleRepeat;
  final bool fullscreen;
  final bool priorityCalls;
  final List<PriorityApp> priorityApps;
}
