import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remya_bar/features/system/system_backend.dart';
import 'package:remya_bar/src/rust/system_bridge/frb_generated.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

MediaPlayerSnapshot _player(String status) => .new(
  busName: 'org.mpris.MediaPlayer2.test',
  identity: 'Test',
  title: 'Track',
  artist: 'Artist',
  album: 'Album',
  artUrl: '',
  playbackStatus: status,
  canControl: true,
  canGoNext: true,
  canGoPrevious: true,
  canPlay: true,
  canPause: true,
  positionSeconds: 12,
  lengthSeconds: 100,
  seekToken: ':1.2/track',
);

Map<String, dynamic> _sound(double percent) => {
  'available': true,
  'system': {
    'default_output': 'speaker',
    'devices': [
      {
        'name': 'speaker',
        'description': 'Speakers',
        'direction': 'output',
        'preferences': {
          'channels': [(percent * 65536 / 100).round()],
          'muted': false,
        },
      },
    ],
  },
};

class _Settings extends SettingsClient {
  final updates = StreamController<SettingsChange>();
  final writes = <({double percent, Completer<Map<String, dynamic>> result})>[];
  Completer<Map<String, dynamic>>? read;
  int reads = 0;

  @override
  Stream<SettingsChange> get changes => updates.stream;

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    if (method == 'Get' && arguments.single == 'sound') {
      reads++;
      return read?.future ?? Future.value(_sound(20));
    }
    if (method == 'Set' && arguments.first == soundOutputVolumeSettingId) {
      final request = jsonDecode(arguments[1]) as Map;
      expect(request['name'], 'speaker');
      final result = Completer<Map<String, dynamic>>();
      writes.add((
        percent: (request['percent'] as num).toDouble(),
        result: result,
      ));
      return result.future;
    }
    if (method == 'Get' && arguments.single == barClockSecondsSettingId) {
      return {'value': true};
    }
    if (method == 'Get' && arguments.single == barLayoutSettingId) {
      return {'value': BarLayout.defaults.toJson()};
    }
    return {};
  }

  @override
  Future<void> close() async {
    await updates.close();
    await super.close();
  }
}

class _MediaApi implements SystemRustLibApi {
  var updates = StreamController<List<MediaPlayerSnapshot>>();
  Completer<void>? action;
  int subscriptions = 0;

  @override
  Stream<List<MediaPlayerSnapshot>> crateApiSubscribeMedia() {
    subscriptions++;
    return updates.stream;
  }

  @override
  Future<void> crateApiMediaAction({
    required String busName,
    required String action,
  }) => this.action?.future ?? Future.value();

  @override
  Future<SystemSnapshot> crateApiHardwareSnapshot() async =>
      const SystemSnapshot(batteries: [], gpus: []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late _MediaApi api;
  late _Settings settings;
  late SystemBackend backend;

  setUp(() async {
    api = _MediaApi();
    SystemRustLib.initMock(api: api);
    settings = _Settings();
    backend = SystemBackend(settings: settings)..start();
    api.updates.add([_player('Paused')]);
    await _flush();
    backend.mediaOutput = {'name': 'speaker', 'percent': 20.0};
  });

  tearDown(() async {
    backend.dispose();
    await api.updates.close();
    SystemRustLib.dispose();
  });

  test('playback overrides stale snapshots, then drops on match', () async {
    api.action = Completer<void>();
    final action = backend.mediaAction(_player('Paused').busName, 'playPause');
    expect(backend.players.single, _player('Playing'));
    api.updates.add([_player('Paused')]);
    await _flush();
    expect(backend.players.single.playbackStatus, 'Playing');
    api.updates.add([_player('Playing')]);
    await _flush();
    api.updates.add([_player('Paused')]);
    await _flush();
    expect(backend.players.single.playbackStatus, 'Paused');
    api.action!.complete();
    await action;
  });

  test('playback expires without another snapshot', () async {
    await backend.mediaAction(_player('Paused').busName, 'playPause');
    expect(backend.players.single.playbackStatus, 'Playing');
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    expect(backend.players.single.playbackStatus, 'Paused');
  });

  test('failed playback restores the most recent real snapshot', () async {
    api.action = Completer<void>();
    final action = backend.mediaAction(_player('Paused').busName, 'playPause');
    final failure = expectLater(action, throwsStateError);
    api.action!.completeError(StateError('failed'));
    await failure;
    expect(backend.players.single, _player('Paused'));
  });

  test('stream errors notify once, recovery clears the error', () async {
    var notifications = 0;
    backend.addListener(() => notifications++);
    api.updates.addError(StateError('disconnected'));
    await _flush();
    api.updates.addError(StateError('still disconnected'));
    await _flush();
    expect(backend.mediaError, 'Media status unavailable');
    expect(notifications, 1);
    api.updates.add([_player('Paused')]);
    await _flush();
    expect(backend.mediaError, isNull);
    expect(notifications, 2);
    api.updates.add([_player('Paused')]);
    await _flush();
    expect(notifications, 2);
  });

  test('an ended stream resubscribes', () async {
    final old = api.updates;
    api.updates = StreamController<List<MediaPlayerSnapshot>>();
    await old.close();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(api.subscriptions, 2);
    expect(api.updates.hasListener, isTrue);
  });

  test(
    'volume writes coalesce to the latest value without stale readback',
    () async {
      final first = backend.setMediaVolume('speaker', 30);
      await backend.setMediaVolume('speaker', 50);
      await backend.setMediaVolume('speaker', 80);
      expect(settings.writes.map((write) => write.percent), [30]);
      expect(backend.mediaOutput['percent'], 80);
      settings.writes.first.result.complete(_sound(30));
      await first;
      expect(settings.writes.map((write) => write.percent), [30, 80]);
      expect(backend.mediaOutput['percent'], 80);
      settings.writes.last.result.complete(_sound(79));
      await _flush();
      expect(backend.mediaOutput['percent'], closeTo(79, 0.002));
    },
  );

  test('volume failures propagate and force sound reconciliation', () async {
    final first = backend.setMediaVolume('speaker', 30);
    final failure = expectLater(first, throwsStateError);
    settings.writes.single.result.completeError(StateError('failed'));
    await failure;
    expect(settings.reads, 1);
    expect(backend.mediaOutput['percent'], closeTo(20, 0.002));
  });

  test(
    'a queued write still runs after failure and reconciles its own error',
    () async {
      final first = backend.setMediaVolume('speaker', 30);
      final failure = expectLater(first, throwsStateError);
      await backend.setMediaVolume('speaker', 90);
      settings.writes.first.result.completeError(StateError('first failed'));
      await failure;
      expect(settings.writes.map((write) => write.percent), [30, 90]);
      expect(backend.mediaOutput['percent'], 90);
      settings.writes.last.result.completeError(StateError('queued failed'));
      await _flush();
      expect(settings.reads, 1);
      expect(backend.mediaOutput['percent'], closeTo(20, 0.002));
    },
  );

  test(
    'a read started before a volume edit cannot replace its optimistic value',
    () async {
      settings.read = Completer<Map<String, dynamic>>();
      settings.updates.add((topic: 'sound', value: {}));
      await _flush();
      final write = backend.setMediaVolume('speaker', 75);
      settings.read!.complete(_sound(10));
      await _flush();
      expect(backend.mediaOutput['percent'], 75);
      settings.writes.single.result.complete(_sound(75));
      await write;
    },
  );
}
