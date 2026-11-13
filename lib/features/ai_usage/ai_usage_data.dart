import 'dart:math' as math;

const aiUsageKind = 'ai-usage';
const aiRefreshInterval = Duration(minutes: 5);
const aiStaleAfter = Duration(minutes: 10);
const quotaSlots = ['primary', 'secondary', 'tertiary'];

Map<String, Object?> aiMap(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : const {};

List<Map<String, Object?>> aiRows(Object? value) =>
    value is List ? value.whereType<Map>().map(aiMap).toList() : const [];

String? aiText(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

double? aiNumber(Object? value) =>
    value is num && value.isFinite && value >= 0 ? value.toDouble() : null;

double? aiPercent(Object? value) {
  final number = aiNumber(value);
  return number != null && number <= 100 ? number : null;
}

DateTime? aiDate(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

Iterable<AiQuotaProvider> aiVisibleProviders(
  Map<String, Object?> data,
  DateTime now,
) sync* {
  final threshold = aiPercent(data['threshold']) ?? 20;
  for (final row in aiRows(data['providers'])) {
    final provider = AiQuotaProvider(row, now, threshold);
    if (provider.pillWindows.isNotEmpty) yield provider;
  }
}

/// Pinned providers in pinned order, else the first three with data.
List<AiQuotaProvider> aiPillProviders(Map<String, Object?> data, DateTime now) {
  final visible = {
    for (final provider in aiVisibleProviders(data, now)) provider.id: provider,
  };
  final pinned = data['pinned'] is List ? data['pinned'] as List : const [];
  return [
    if (pinned.isEmpty)
      ...visible.values
    else
      ...pinned.map((id) => visible[id]).nonNulls,
  ].take(3).toList();
}

/// Settings `bar.lowPercent`, defaulting to 20 when unset or invalid.
double aiLowPercent(Object? bar) =>
    aiNumber(aiMap(bar)['lowPercent'])?.clamp(1, 100).toDouble() ?? 20;

class AiQuotaProvider {
  AiQuotaProvider(this.data, this.now, this.threshold);

  final Map<String, Object?> data;
  final DateTime now;
  final double threshold;

  String get id => aiText(data['id']) ?? '';
  String get name => aiText(data['name']) ?? id;
  String? get error {
    if (aiText(data['error']) case final error?) return error;
    final updated = aiDate(data['updatedAt']);
    return updated != null && now.difference(updated) > aiStaleAfter
        ? 'Usage data is out of date.'
        : null;
  }

  AiQuotaWindow? window(String slot) {
    final data = aiMap(this.data[slot]);
    return error == null && aiPercent(data['used']) != null
        ? AiQuotaWindow(data, slot, now, threshold)
        : null;
  }

  List<AiQuotaWindow> get pillWindows {
    final windows = [?window('primary'), ?window('secondary')];
    return windows.isEmpty ? [?window('tertiary')] : windows;
  }

  AiQuotaWindow? get tightest => pillWindows.fold<AiQuotaWindow?>(
    null,
    (tightest, window) =>
        tightest == null || window.left < tightest.left ? window : tightest,
  );

  String get tooltip => tooltipText();

  String tooltipText({bool showUsed = false}) => [
    [name, ?aiText(data['plan'])].join(' · '),
    ?error,
    for (final window in pillWindows)
      [
        '${window.cadence} ${window.percentText(showUsed: showUsed)} '
            '${showUsed ? 'used' : 'left'}',
        ?window.resetLabel,
        ?window.paceLabel,
      ].join(' · '),
  ].join('\n');
}

class AiQuotaWindow {
  AiQuotaWindow(this.data, this.slot, this.now, this.threshold);

  final Map<String, Object?> data;
  final String slot;
  final DateTime now;
  final double threshold;

  double get used => aiPercent(data['used'])!;
  double get left => 100 - used;
  bool get low => left <= threshold;
  int percentValue({bool showUsed = false}) => (showUsed ? used : left).round();
  String percentText({bool showUsed = false}) =>
      '${percentValue(showUsed: showUsed)}%';
  String get percent => '${left.round()}%';
  DateTime? get reset => aiDate(data['resetsAt']);
  double? get expectedLeft {
    final used = aiPercent(data['expectedUsed']);
    if (used != null) return 100 - used;
    // CodexBar omits pace for some providers; a linear pace is the share of
    // the window's time still left.
    final minutes = aiNumber(data['minutes']);
    final reset = this.reset;
    if (minutes == null || minutes <= 0 || reset == null) return null;
    final remaining = reset.difference(now).inSeconds / 60;
    if (remaining < 0 || remaining > minutes) return null;
    return remaining / minutes * 100;
  }

  double? get expectedUsed => expectedLeft == null ? null : 100 - expectedLeft!;

  bool get runningOut => data['willLast'] == false;

  String get name =>
      aiText(data['label']) ??
      switch (slot) {
        'primary' => 'Session',
        'secondary' => 'Weekly',
        _ => 'Model quota',
      };

  String get cadence => switch (aiNumber(data['minutes'])) {
    10080 => '1W',
    1440 => '1D',
    final minutes? when minutes >= 40320 => 'MO',
    final minutes? when minutes % 60 == 0 => '${(minutes / 60).round()}H',
    final minutes? when minutes > 0 => '${minutes.round()}M',
    _ => name,
  };

  String? get resetShort {
    final date = reset?.toLocal();
    if (date == null) return null;
    final duration = date.difference(now);
    if (duration <= Duration.zero) return 'Due';
    if (duration < const Duration(days: 1)) return aiDuration(duration);
    return _weekdays[date.weekday - 1];
  }

  String? get resetLabel {
    final date = reset?.toLocal();
    final short = resetShort;
    if (date == null || short == null) return null;
    if (short == 'Due') return 'Reset due';
    if (date.difference(now) < const Duration(days: 1)) {
      return 'Resets in $short';
    }
    String padded(int value) => value.toString().padLeft(2, '0');
    return 'Resets $short ${padded(date.hour)}:${padded(date.minute)}';
  }

  ({int delta, bool reserve})? get pacePercent {
    if (aiNumber(data['eta']) case final seconds?
        when runningOut &&
            seconds > 0 &&
            seconds < const Duration(days: 366).inSeconds) {
      return null;
    }
    final expected = expectedLeft;
    if (expected == null) return null;
    final delta = (left - expected).round();
    if (delta.abs() <= 2) return null;
    return (delta: delta.abs(), reserve: delta > 0);
  }

  String? get paceLabel {
    if (aiNumber(data['eta']) case final seconds?
        when runningOut &&
            seconds > 0 &&
            seconds < const Duration(days: 366).inSeconds) {
      return 'Empty in ~${aiDuration(Duration(seconds: seconds.round()))}';
    }
    final expected = expectedLeft;
    if (expected == null) return null;
    final delta = (left - expected).round();
    if (delta.abs() <= 2) return 'On pace';
    return '${delta.abs()}% in ${delta > 0 ? 'reserve' : 'deficit'}';
  }
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String aiDuration(Duration duration) {
  final minutes = math.max(1, (duration.inSeconds / 60).ceil());
  final hours = minutes ~/ 60;
  return [
    if (hours > 0) '${hours}h',
    if (minutes % 60 > 0) '${minutes % 60}m',
  ].join(' ');
}

/// Retain a previously discovered provider through a failed fetch, while
/// honoring explicit disables in CodexBar's saved configuration.
List<Map<String, Object?>> aiProviderSamples(
  List<Map<String, Object?>> configured,
  List<Map<String, Object?>>? usage, {
  required List<Map<String, Object?>> previous,
  required bool automatic,
}) {
  bool hasUsage(Map<String, Object?> row) =>
      row['error'] == null && _hasQuota(aiMap(row['usage']));

  final readings = <String, Map<String, Object?>>{};
  for (final row in usage ?? const <Map<String, Object?>>[]) {
    final id = aiText(row['provider']);
    if (id == null) continue;
    final prior = readings[id];
    if (prior == null || (!hasUsage(prior) && hasUsage(row))) {
      readings[id] = row;
    }
  }
  final providers = {
    for (final row in configured) ?aiText(row['id'] ?? row['provider']): row,
  };
  final prior = {for (final row in previous) row['id']: row};
  final ids = {
    ...providers.keys,
    ...readings.keys,
    ...prior.keys.whereType<String>(),
  };
  return [
    for (final id in ids)
      if ((automatic || providers[id]?['enabled'] == true) &&
          (hasUsage(readings[id] ?? const {}) ||
              (prior.containsKey(id) &&
                  (usage == null || readings.containsKey(id)))))
        aiProviderData({
          'id': id,
          'name':
              aiText(providers[id]?['name'] ?? providers[id]?['displayName']) ??
              aiText(prior[id]?['name']) ??
              id,
        }, readings[id] ?? const {}),
  ];
}

Map<String, Object?> aiProviderData(
  Map<String, Object?> provider,
  Map<String, Object?> row,
) {
  final usage = aiMap(row['usage']);
  final pace = aiMap(row['pace']);
  final status = aiMap(row['status']);
  final credits = aiMap(row['credits']);
  return {
    'id': provider['id'],
    'name': provider['name'],
    'source': aiText(row['source']),
    'plan': aiText(aiMap(usage['identity'])['loginMethod']),
    'updatedAt': aiText(usage['updatedAt']),
    'incident': switch (aiText(status['indicator'])) {
      'minor' ||
      'major' ||
      'critical' ||
      'maintenance' => aiText(status['description']) ?? 'Provider incident',
      _ => null,
    },
    'credits': credits['balanceReadSucceeded'] == false
        ? aiNumber(aiMap(credits['codexCreditLimit'])['remaining'])
        : aiNumber(credits['remaining']),
    if (aiMap(row['resetCredits'])['available'] case final int count
        when count > 0)
      'bankedResets': count,
    'error':
        aiText(aiMap(row['error'])['message']) ??
        (_hasQuota(usage) ? null : 'Usage unavailable'),
    for (final slot in quotaSlots)
      if (usage[slot] is Map)
        slot: _windowData(
          aiMap(usage[slot]),
          aiMap(pace[slot]),
          aiMap(row['rateWindowLabels'])[slot],
        ),
  };
}

bool _hasQuota(Map<String, Object?> usage) => quotaSlots.any(
  (slot) => aiPercent(aiMap(usage[slot])['usedPercent']) != null,
);

Map<String, Object?> _windowData(
  Map<String, Object?> row,
  Map<String, Object?> pace,
  Object? label,
) => {
  'used': aiPercent(row['usedPercent']),
  'minutes': aiNumber(row['windowMinutes']),
  'resetsAt': aiText(row['resetsAt']),
  'label': aiText(label),
  'expectedUsed': aiPercent(pace['expectedUsedPercent']),
  'eta': aiNumber(pace['etaSeconds']),
  'willLast': pace['willLastToReset'],
};

/// Track one cycle per provider/window and tolerate transient errors.
class AiQuotaAlerts {
  final _seen =
      <(String, String), ({DateTime reset, double left, Set<int> sent})>{};

  List<(String, String, int)> update(List<AiQuotaProvider> providers) {
    final ids = {for (final provider in providers) provider.id};
    _seen.removeWhere((key, _) => !ids.contains(key.$1));
    final alerts = <(String, String, int)>[];
    for (final provider in providers) {
      for (final slot in quotaSlots) {
        final window = provider.window(slot);
        final reset = window?.reset;
        if (window == null || reset == null || !reset.isAfter(provider.now)) {
          continue;
        }
        final key = (provider.id, slot);
        final previous = _seen[key];
        final sameCycle = previous != null && previous.reset == reset;
        final sent = sameCycle ? previous.sent : <int>{};
        if (sameCycle) {
          for (final threshold in {provider.threshold, 0.0}) {
            if (previous.left > threshold &&
                window.left <= threshold &&
                sent.add(threshold.round())) {
              alerts.add((provider.name, window.name, threshold.round()));
            }
          }
        }
        _seen[key] = (reset: reset, left: window.left, sent: sent);
      }
    }
    return alerts;
  }
}
