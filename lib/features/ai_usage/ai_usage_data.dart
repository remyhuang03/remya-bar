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

  List<AiQuotaWindow> get pillWindows => [
    for (final slot in quotaSlots.take(2)) ?window(slot),
  ];

  AiQuotaWindow? get tightest => pillWindows.fold<AiQuotaWindow?>(
    null,
    (tightest, window) =>
        tightest == null || window.left < tightest.left ? window : tightest,
  );

  String get tooltip => [
    [name, ?aiText(data['plan'])].join(' · '),
    ?error,
    for (final window in pillWindows)
      [
        '${window.cadence} ${window.percent} left',
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

  double get left => 100 - aiPercent(data['used'])!;
  bool get low => left <= threshold;
  String get percent => '${left.round()}%';
  DateTime? get reset => aiDate(data['resetsAt']);
  double? get expectedLeft {
    final used = aiPercent(data['expectedUsed']);
    return used == null ? null : 100 - used;
  }

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
    'error':
        aiText(aiMap(row['error'])['message']) ??
        (quotaSlots.any(
              (slot) => aiPercent(aiMap(usage[slot])['usedPercent']) != null,
            )
            ? null
            : 'Usage unavailable'),
    for (final slot in quotaSlots)
      if (usage[slot] is Map)
        slot: _windowData(
          aiMap(usage[slot]),
          aiMap(pace[slot]),
          aiMap(row['rateWindowLabels'])[slot],
        ),
  };
}

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
