import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:remya_client/settings_contract.dart';
import 'package:remya_bar/features/settings/bar_preferences.dart';

import '../../src/rust/system_bridge/api.dart' as rust;
import '../system/system_backend.dart';
import 'ai_usage_data.dart';
import 'ai_usage_poll.dart';

/// Shares one process-wide sample and refresh state with every bar view.
class AiUsageBackend extends ChangeNotifier {
  AiUsageBackend({SettingsClient? settings})
    : _settings = settings ?? SettingsClient(),
      _ownsSettings = settings == null;

  Map<String, Object?> data = const {};
  final SettingsClient _settings;
  final bool _ownsSettings;
  late final _preferences = BarPreferences(client: _settings);
  Map<String, Object?> _sample = const {};
  Map<String, dynamic>? _bar;
  Future<void>? _readingBar;
  bool _barDirty = false;
  bool _retryBar = false;
  Timer? _timer;
  StreamSubscription<SettingsChange>? _changes;
  StreamSubscription<bool>? _availability;
  bool _disposed = false;
  bool _publishedVisible = false;
  bool refreshing = false;
  int tick = 0;

  bool get visible => aiPillProviders(data, DateTime.now()).isNotEmpty;

  void start() {
    if (_disposed || _timer != null) return;
    _changes = _settings.changes.listen((change) {
      if (change.topic == aiRingSettingId) {
        unawaited(_readBar());
      } else if (change.topic == aiProvidersSettingId) {
        _polling.invalidate();
        unawaited(_polling.read(false));
      }
    }, onError: (Object _) {});
    _availability = _settings.serviceAvailableChanges.listen((available) {
      if (!available) return;
      unawaited(_readBar());
      _polling.invalidate();
      unawaited(_polling.read(false));
    }, onError: (Object _) {});
    unawaited(_readBar());
    unawaited(_polling.read(false));
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(_polling.read(false));
      if (_retryBar) unawaited(_readBar());
      if (_publishedVisible || visible) {
        tick++;
        _publish();
      }
    });
  }

  Future<void> _readBar() {
    _barDirty = true;
    return _readingBar ??= _readBarChanges().whenComplete(() {
      _readingBar = null;
      if (_barDirty && !_disposed) unawaited(_readBar());
    });
  }

  Future<void> _readBarChanges() async {
    while (_barDirty && !_disposed) {
      _barDirty = false;
      try {
        final next = await _preferences.readAiRing();
        if (_disposed) return;
        _bar = next;
        _retryBar = false;
        _publish();
        _notifyAlerts(aiLowPercent(_bar));
      } catch (_) {
        // Keep the last valid preferences while Core reconnects.
        _retryBar = true;
      }
    }
  }

  void _publish() {
    final wasVisible = _publishedVisible;
    data = {
      ..._sample,
      'showUsed': _bar?['showUsed'] == true,
      'ringOrder': _bar?['ringOrder'] == '5h-outer' ? '5h-outer' : '5h-inner',
      'threshold': aiLowPercent(_bar),
      'pinned': [...?(_bar?['pinned'] as List?)?.whereType<String>()],
    };
    _publishedVisible = visible;
    if (wasVisible || _publishedVisible) notifyListeners();
  }

  Future<void> refresh() async {
    if (_disposed || refreshing) return;
    refreshing = true;
    notifyListeners();
    try {
      await _polling.read(true);
    } finally {
      refreshing = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_changes?.cancel());
    unawaited(_availability?.cancel());
    if (_ownsSettings) unawaited(_settings.close());
    super.dispose();
  }

  static final _random = Random.secure();
  final _token = base64UrlEncode(
    List<int>.generate(32, (_) => _random.nextInt(256)),
  );
  final _alerts = AiQuotaAlerts();
  late final _polling = AiUsagePoll(_poll);

  Future<bool> _poll(bool force) async {
    if (_disposed) return false;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 2)
      ..findProxy = (_) => 'DIRECT';
    try {
      await SystemBackend.initialize();
      final port = await rust.codexbarServerPort(token: _token);
      final (shell, _, configured, (usage, _), (cost, costCurrent)) = await (
        _get(
          client,
          port,
          '/dashboard/v1/snapshot?detail=shell',
          authenticate: true,
        ),
        _readingBar ?? Future<void>.value(),
        _cli('providers'),
        _endpoint(client, port, 'usage', refresh: true),
        _endpoint(client, port, 'cost', refresh: force),
      ).wait;
      if (_disposed || usage == null || (configured == null && shell is! Map)) {
        return false;
      }
      final data = aiProviderSamples(
        configured ?? aiRows(aiMap(shell)['providers']),
        usage,
        previous: aiRows(_sample['providers']),
        automatic: configured == null,
      );
      final updated =
          [
            for (final row in data)
              if (row['error'] == null) ?aiDate(row['updatedAt']),
          ].fold<DateTime?>(
            null,
            (latest, time) =>
                latest == null || time.isAfter(latest) ? time : latest,
          );
      final previousCost = aiRows(_sample['cost']);
      _sample = {
        'providers': data,
        'updatedAt': updated?.toIso8601String(),
        'cost': cost != null && (costCurrent || previousCost.isEmpty)
            ? _costData(cost, data)
            : [
                for (final row in previousCost)
                  if (data.any((provider) => provider['id'] == row['id'])) row,
              ],
      };
      tick++;
      _publish();
      _notifyAlerts(aiLowPercent(_bar));
      return costCurrent;
    } finally {
      client.close(force: true);
    }
  }

  void _notifyAlerts(double threshold) {
    final now = DateTime.now();
    for (final (name, window, left) in _alerts.update([
      for (final row in aiRows(_sample['providers']))
        AiQuotaProvider(row, now, threshold),
    ])) {
      unawaited(
        rust.codexbarNotify(provider: name, window: window, remaining: left),
      );
    }
  }

  Future<(List<Map<String, Object?>>?, bool)> _endpoint(
    HttpClient client,
    int? port,
    String endpoint, {
    required bool refresh,
  }) async {
    // CodexBar 0.84 only honors the HTTP refresh flag on /usage.
    final refreshCost = endpoint == 'cost' && refresh;
    if (refreshCost) {
      final fresh = await _cli(endpoint, refresh: true);
      if (fresh != null) return (fresh, true);
    }
    // Tracked providers are filtered locally, so always probe all of them.
    final selection = endpoint == 'cost' ? 'provider=both&' : 'provider=all&';
    final value = await _get(
      client,
      port,
      '/$endpoint?$selection${refresh ? 'refresh=1' : ''}',
    );
    if (value is List) return (aiRows(value), !refreshCost);
    final rows = refreshCost ? null : await _cli(endpoint, refresh: refresh);
    return (rows, rows != null);
  }

  Future<Object?> _get(
    HttpClient client,
    int? port,
    String path, {
    bool authenticate = false,
  }) async {
    if (port == null) return null;
    try {
      return await (() async {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port$path'),
        );
        request.followRedirects = false;
        if (authenticate) {
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer $_token',
          );
        }
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          await response.drain<void>();
          return null;
        }
        var bytes = 0;
        final body = await utf8.decoder
            .bind(
              response.map((chunk) {
                bytes += chunk.length;
                if (bytes > 32 * 1024 * 1024) {
                  throw const FormatException('Response too large');
                }
                return chunk;
              }),
            )
            .join();
        return _decode(body);
      })().timeout(const Duration(seconds: 35));
    } catch (_) {
      return null;
    }
  }

  Future<Object?> _decode(String body) async =>
      body.length < 64 * 1024 ? jsonDecode(body) : compute(jsonDecode, body);

  Future<List<Map<String, Object?>>?> _cli(
    String kind, {
    bool refresh = false,
  }) async {
    try {
      final output = await rust.codexbarJson(kind: kind, refresh: refresh);
      final value = output == null ? null : await _decode(output);
      return value is List ? aiRows(value) : null;
    } catch (_) {
      return null;
    }
  }
}

List<Map<String, Object?>> _costData(
  List<Map<String, Object?>>? rows,
  List<Map<String, Object?>> providers,
) {
  final enabled = {for (final row in providers) row['id']};
  final byProvider = {for (final row in rows ?? const []) row['provider']: row};
  return [
    for (final id in const ['claude', 'codex'])
      if (byProvider[id] case final row? when enabled.contains(id))
        if (row['error'] == null &&
            row['source'] == 'local' &&
            (row['currencyCode'] == null || row['currencyCode'] == 'USD'))
          {
            'id': row['provider'],
            'total': aiNumber(row['last30DaysCostUSD']),
            'tokens': aiNumber(row['last30DaysTokens']),
            'partial':
                row['historyCoverageIsEstablished'] == false ||
                (aiNumber(row['historyDays']) ?? 30) < 30 ||
                (aiNumber(row['incompleteRequestCount']) ?? 0) > 0,
            'daily': {
              for (final day in aiRows(row['daily']))
                ?aiText(day['date']): ?aiNumber(day['totalCost']),
            },
          },
  ];
}
