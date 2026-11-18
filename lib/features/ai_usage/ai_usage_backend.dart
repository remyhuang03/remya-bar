import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart';
import 'package:remya_client/settings_contract.dart';
import 'package:remya_bar/features/settings/bar_preferences.dart';

import '../../src/rust/system_bridge/api.dart' as rust;
import '../system/system_backend.dart';
import 'ai_usage_data.dart';
import 'ai_usage_poll.dart';

const _workerName = 'top.remya.bar/ai-usage';
ReceivePort? _workerInbox;

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
  Timer? _timer;
  StreamSubscription<SettingsChange>? _changes;
  bool _disposed = false;
  SendPort? _readingWorker;
  final _replies = <ReceivePort>{};
  int _nextRead = 0;
  int _appliedRead = 0;
  bool refreshing = false;
  int tick = 0;

  bool get visible => aiPillProviders(data, DateTime.now()).isNotEmpty;

  void start() {
    if (_disposed || _timer != null) return;
    unawaited(_read());
    unawaited(_readBar());
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(_read());
      unawaited(_readBar());
    });
    _changes = _settings.changes.listen((change) {
      if (change.topic == aiRingSettingId) {
        unawaited(_readBar());
      } else if (change.topic == aiProvidersSettingId) {
        unawaited(_read());
      }
    }, onError: (Object _) {});
  }

  Future<void> _readBar() {
    _barDirty = true;
    return _readingBar ??= _readBarChanges().whenComplete(
      () => _readingBar = null,
    );
  }

  Future<void> _readBarChanges() async {
    while (_barDirty && !_disposed) {
      _barDirty = false;
      try {
        final next = await _preferences.readAiRing();
        if (_disposed) return;
        _bar = next;
        _publish();
      } catch (_) {
        // Keep the last valid preferences while Core reconnects.
      }
    }
  }

  void _publish() {
    final hadProviders = aiRows(data['providers']).isNotEmpty;
    data = {
      ..._sample,
      'showUsed': _bar?['showUsed'] == true,
      'ringOrder': _bar?['ringOrder'] == '5h-outer' ? '5h-outer' : '5h-inner',
      'threshold': aiLowPercent(_bar),
      'pinned': [...?(_bar?['pinned'] as List?)?.whereType<String>()],
    };
    if (visible || hadProviders) notifyListeners();
  }

  Future<void> refresh() async {
    if (_disposed || refreshing) return;
    refreshing = true;
    notifyListeners();
    try {
      await _read(force: true);
    } finally {
      refreshing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _read({bool force = false}) async {
    if (_disposed || (!force && refreshing)) return;
    final worker = IsolateNameServer.lookupPortByName(_workerName);
    if (worker == null) return;
    if (!force) {
      if (_readingWorker == worker) return;
      _readingWorker = worker;
    }
    final sequence = ++_nextRead;
    final reply = ReceivePort();
    _replies.add(reply);
    try {
      worker.send([reply.sendPort, force]);
      // A forced read can wait for an ordinary round and then run its own.
      final value = await reply.first.timeout(const Duration(minutes: 3));
      if (!_disposed && sequence > _appliedRead && value is Map) {
        _appliedRead = sequence;
        _sample = aiMap(value);
        tick++;
        _publish();
      }
    } on TimeoutException {
      // The next poll can reconnect after an engine restart.
    } on StateError {
      if (!_disposed) rethrow;
    } finally {
      reply.close();
      _replies.remove(reply);
      if (!force && _readingWorker == worker) _readingWorker = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    for (final reply in _replies) {
      reply.close();
    }
    unawaited(_changes?.cancel());
    if (_ownsSettings) unawaited(_settings.close());
    super.dispose();
  }
}

/// Lives in the application engine, which survives monitor removal.
void startAiUsageWorker() {
  if (_workerInbox != null) return;
  // Replace stale registrations after an engine restart.
  IsolateNameServer.removePortNameMapping(_workerName);
  final inbox = ReceivePort();
  if (!IsolateNameServer.registerPortWithName(inbox.sendPort, _workerName)) {
    inbox.close();
    return;
  }
  _workerInbox = inbox;
  final worker = _AiUsageWorker();
  inbox.listen((message) async {
    final [SendPort reply, bool force] = message as List;
    try {
      reply.send(await worker.read(force));
    } catch (_) {
      reply.send(null);
    }
  });
}

class _AiUsageWorker {
  _AiUsageWorker() {
    _settings.changes.listen((change) {
      if (change.topic == aiRingSettingId) {
        unawaited(_readBar().then((bar) => _notifyAlerts(aiLowPercent(bar))));
      } else if (change.topic == aiProvidersSettingId) {
        _polling.invalidate();
      }
    }, onError: (Object _) {});
  }

  final _settings = SettingsClient();
  late final _preferences = BarPreferences(client: _settings);
  Map<String, dynamic>? _bar;

  /// Bar preferences from Core; the last value is kept while Core
  /// reconnects. Tracking itself is CodexBar's enabled set, which Settings
  /// writes, so polling never makes Core probe every provider.
  Future<Map<String, dynamic>?> _readBar() async {
    try {
      _bar = await _preferences.readAiRing();
    } catch (_) {}
    return _bar;
  }

  static final _random = Random.secure();
  final _token = base64UrlEncode(
    List<int>.generate(32, (_) => _random.nextInt(256)),
  );
  final _alerts = AiQuotaAlerts();
  Map<String, Object?> _sample = const {};
  late final _polling = AiUsagePoll(_poll);

  Future<Map<String, Object?>> read(bool force) async {
    await _polling.read(force);
    return _sample;
  }

  Future<bool> _poll(bool force) async {
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
        _readBar(),
        _cli('providers'),
        _endpoint(client, port, 'usage', refresh: true),
        _endpoint(client, port, 'cost', refresh: force),
      ).wait;
      if (usage == null || (configured == null && shell is! Map)) return false;
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
        return jsonDecode(body);
      })().timeout(const Duration(seconds: 35));
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, Object?>>?> _cli(
    String kind, {
    bool refresh = false,
  }) async {
    try {
      final output = await rust.codexbarJson(kind: kind, refresh: refresh);
      final value = output == null ? null : jsonDecode(output);
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
