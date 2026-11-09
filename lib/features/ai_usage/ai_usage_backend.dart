import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart';

import '../../src/rust/system_bridge/api.dart' as rust;
import '../system/system_backend.dart';
import 'ai_usage_data.dart';

const _workerName = 'top.remya.bar/ai-usage';

/// Per-output view of the process-wide sample. Revisit it for countdowns and
/// to pick up a refresh initiated on another monitor.
class AiUsageBackend extends ChangeNotifier {
  Map<String, Object?> data = const {};
  Timer? _timer;
  bool _disposed = false;
  bool refreshing = false;
  int tick = 0;

  bool get visible => aiRows(data['providers']).isNotEmpty;

  void start() {
    unawaited(_read());
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _read());
  }

  Future<void> refresh() async {
    if (refreshing) return;
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
    if (!force && refreshing) return;
    final worker = IsolateNameServer.lookupPortByName(_workerName);
    if (worker == null) return;
    final reply = ReceivePort();
    try {
      worker.send([reply.sendPort, force]);
      final value = await reply.first.timeout(const Duration(seconds: 90));
      if (!_disposed) {
        final wasVisible = visible;
        data = aiMap(value);
        tick++;
        if (visible || wasVisible) notifyListeners();
      }
    } on TimeoutException {
      // The next poll can reconnect after an engine restart.
    } finally {
      reply.close();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

/// Lives in the warm popup engine, which survives monitor removal.
void startAiUsageWorker() {
  final inbox = ReceivePort();
  if (!IsolateNameServer.registerPortWithName(inbox.sendPort, _workerName)) {
    inbox.close();
    return;
  }
  final worker = _AiUsageWorker();
  inbox.listen((message) async {
    final [SendPort reply, bool force] = message as List;
    try {
      reply.send(await worker.read(force));
    } catch (_) {
      reply.send(const <String, Object?>{});
    }
  });
}

class _AiUsageWorker {
  static final _random = Random.secure();
  final _token = base64UrlEncode(
    List<int>.generate(32, (_) => _random.nextInt(256)),
  );
  final _alerts = AiQuotaAlerts();
  late final _rustReady = SystemBackend.initialize();
  final _threshold =
      int.tryParse(Platform.environment['REMYA_BAR_AI_QUOTA_LOW_PERCENT'] ?? '')
          ?.clamp(1, 100)
          .toDouble() ??
      20.0;
  Map<String, Object?> _sample = const {};
  DateTime? _nextPoll;
  Future<void>? _pending;

  Future<Map<String, Object?>> read(bool force) async {
    final now = DateTime.now();
    if (force || _nextPoll == null || !now.isBefore(_nextPoll!)) {
      await (_pending ??= _poll(force).whenComplete(() => _pending = null));
    } else if (_sample.isEmpty) {
      await _pending;
    }
    return _sample;
  }

  Future<void> _poll(bool force) async {
    _nextPoll = DateTime.now().add(aiRefreshInterval);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 2)
      ..findProxy = (_) => 'DIRECT';
    try {
      await _rustReady;
      final port = await rust.codexbarServerPort(token: _token);
      final shell = aiMap(
        await _get(
          client,
          port,
          '/dashboard/v1/snapshot?detail=shell',
          authenticate: true,
        ),
      );
      final configured = shell['providers'] is List
          ? aiRows(shell['providers'])
          : await _cli('providers');
      if (configured != null &&
          !configured.any((row) => row['enabled'] == true)) {
        _sample = const {};
        _alerts.update(const []);
        return;
      }

      final (usage, cost) = await (
        _endpoint(client, port, 'usage', refresh: true),
        _endpoint(client, port, 'cost', refresh: force),
      ).wait;
      final byProvider = <String, Map<String, Object?>>{};
      for (final row in usage ?? const <Map<String, Object?>>[]) {
        if (aiText(row['provider']) case final id?) {
          byProvider.putIfAbsent(id, () => row);
        }
      }
      final providers = configured == null
          ? [
              if (usage == null) ...aiRows(_sample['providers']),
              for (final id in byProvider.keys) {'id': id, 'name': id},
            ]
          : [
              for (final row in configured)
                if (row['enabled'] == true)
                  if (aiText(row['id'] ?? row['provider']) case final id?)
                    {
                      'id': id,
                      'name': aiText(row['name'] ?? row['displayName']) ?? id,
                    },
            ];
      final data = [
        for (final provider in providers)
          aiProviderData(provider, byProvider[provider['id']] ?? const {}),
      ];
      final now = DateTime.now();
      final updated =
          [
            for (final row in data)
              if (row['error'] == null) ?aiDate(row['updatedAt']),
          ].fold<DateTime?>(
            null,
            (latest, time) =>
                latest == null || time.isAfter(latest) ? time : latest,
          );
      _sample = {
        'providers': data,
        'showUsed': aiMap(shell['host'])['usageBarsShowUsed'] == true,
        'threshold': _threshold,
        'updatedAt': updated?.toIso8601String(),
        'cost': _costData(cost, data),
      };
      for (final (name, window, left) in _alerts.update([
        for (final row in data) AiQuotaProvider(row, now, _threshold),
      ])) {
        unawaited(
          rust.codexbarNotify(provider: name, window: window, remaining: left),
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<List<Map<String, Object?>>?> _endpoint(
    HttpClient client,
    int? port,
    String endpoint, {
    required bool refresh,
  }) async {
    // CodexBar 0.84 only honors the HTTP refresh flag on /usage.
    final refreshCost = endpoint == 'cost' && refresh;
    if (refreshCost) {
      final fresh = await _cli(endpoint, refresh: true);
      if (fresh != null) return fresh;
    }
    final value = await _get(
      client,
      port,
      '/$endpoint${refresh ? '?refresh=1' : ''}',
    );
    if (value is List) return aiRows(value);
    return refreshCost ? null : _cli(endpoint, refresh: refresh);
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
