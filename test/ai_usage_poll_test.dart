import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter_test/flutter_test.dart';
import 'package:remya_bar/features/ai_usage/ai_usage_backend.dart';
import 'package:remya_bar/features/ai_usage/ai_usage_poll.dart';
import 'package:remya_client/settings_contract.dart';

class _Settings extends SettingsClient {
  @override
  Stream<SettingsChange> get changes => const Stream.empty();

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async => throw StateError('Core unavailable');
}

void main() {
  test('manual refresh waits for its own poll and coalesces callers', () async {
    final ordinary = Completer<bool>();
    final forced = Completer<bool>();
    final forceStarted = Completer<void>();
    final calls = <bool>[];
    final poll = AiUsagePoll((force) {
      calls.add(force);
      if (force) forceStarted.complete();
      return force ? forced.future : ordinary.future;
    });

    final pending = poll.read(false);
    final first = poll.read(true);
    final second = poll.read(true);
    var completed = false;
    unawaited(first.then((_) => completed = true));

    expect(calls, [false]);
    ordinary.complete(true);
    await pending;
    await forceStarted.future;
    expect(calls, [false, true]);
    expect(completed, isFalse);
    forced.complete(true);
    await Future.wait([first, second]);
    expect(completed, isTrue);
    expect(calls, [false, true]);
  });

  test('failed attempts back off briefly until a successful refresh', () async {
    var now = DateTime.utc(2026, 1, 1);
    var calls = 0;
    final poll = AiUsagePoll((_) async {
      switch (++calls) {
        case 1:
          throw StateError('Bridge temporarily unavailable');
        case 2:
          return false;
        default:
          return true;
      }
    }, now: () => now);

    await poll.read(false);
    now = now.add(const Duration(seconds: 4));
    await poll.read(false);
    expect(calls, 1);
    now = now.add(const Duration(seconds: 1));
    await poll.read(false);
    expect(calls, 2);
    now = now.add(const Duration(seconds: 9));
    await poll.read(false);
    expect(calls, 2);
    now = now.add(const Duration(seconds: 1));
    await poll.read(false);
    expect(calls, 3);
    now = now.add(const Duration(minutes: 4, seconds: 59));
    await poll.read(false);
    expect(calls, 3);
    now = now.add(const Duration(seconds: 1));
    await poll.read(false);
    expect(calls, 4);
  });

  test('an invalidation during a poll leaves the next read eligible', () async {
    final first = Completer<bool>();
    var calls = 0;
    final poll = AiUsagePoll((_) async => ++calls == 1 ? first.future : true);
    final pending = poll.read(false);
    poll.invalidate();
    first.complete(true);
    await pending;
    await poll.read(false);
    expect(calls, 2);
  });

  test('a late ordinary response cannot revert a manual refresh', () async {
    const name = 'top.remya.bar/ai-usage';
    final inbox = ReceivePort();
    expect(
      IsolateNameServer.registerPortWithName(inbox.sendPort, name),
      isTrue,
    );
    final messages = StreamIterator<dynamic>(inbox);
    addTearDown(() async {
      IsolateNameServer.removePortNameMapping(name);
      await messages.cancel();
      inbox.close();
    });
    final settings = _Settings();
    addTearDown(settings.close);
    final backend = AiUsageBackend(settings: settings)..start();
    addTearDown(backend.dispose);

    expect(await messages.moveNext(), isTrue);
    final [SendPort ordinary, bool conventional] = messages.current as List;
    expect(conventional, isFalse);
    final refresh = backend.refresh();
    expect(await messages.moveNext(), isTrue);
    final [SendPort forced, bool manual] = messages.current as List;
    expect(manual, isTrue);
    forced.send({'version': 2});
    await refresh;

    ordinary.send({'version': 1});
    await pumpEventQueue();
    expect(backend.data['version'], 2);
    expect(backend.tick, 1);
  });
}
