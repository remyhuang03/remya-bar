import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remya_bar/widgets/bar_icon_cache.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'merges pending lookups and retries exceptions and partial maps',
    () async {
      var now = DateTime(2026);
      final first = Completer<Map<String, String>>();
      final requests = <List<String>>[];
      final cache = BarIconCache<String>(
        now: () => now,
        lookup: (keys) async {
          requests.add(keys);
          return switch (requests.length) {
            1 => first.future,
            2 => {'a': '/first/a.png'},
            _ => {'b': '/second/b.png'},
          };
        },
        onChanged: () {},
      );
      addTearDown(cache.dispose);

      cache.resolve({'a', 'b'});
      cache.resolve({'a', 'b'});
      expect(requests, [
        ['a', 'b'],
      ]);
      first.completeError(PlatformException(code: 'unavailable'));
      await Future<void>.delayed(Duration.zero);
      cache.resolve({'a', 'b'});
      expect(requests, hasLength(1));
      now = now.add(const Duration(seconds: 15));
      cache.resolve({'a', 'b'});
      await Future<void>.delayed(Duration.zero);
      expect(cache['a'], '/first/a.png');
      expect(cache['b'], isNull);
      now = now.add(const Duration(seconds: 15));
      cache.resolve({'a', 'b'});
      await Future<void>.delayed(Duration.zero);
      expect(requests, [
        ['a', 'b'],
        ['a', 'b'],
        ['b'],
      ]);
      expect(cache['b'], '/second/b.png');
    },
  );

  test('theme changes discard already running native results', () async {
    final oldTheme = Completer<Map<String, String>>();
    var requests = 0;
    final seen = <String?>[];
    late final BarIconCache<String> cache;
    cache = BarIconCache<String>(
      lookup: (_) async =>
          ++requests == 1 ? oldTheme.future : {'editor': '/new/editor.png'},
      onChanged: () => seen.add(cache['editor']),
    );
    addTearDown(cache.dispose);
    cache.resolve({'editor'});

    await binding.defaultBinaryMessenger.handlePlatformMessage(
      barIconChannel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('themeChanged'),
      ),
      (_) {},
    );
    oldTheme.complete({'editor': '/old/editor.png'});
    await Future<void>.delayed(Duration.zero);
    expect(requests, 2);
    expect(seen, ['/new/editor.png']);
  });

  test('large batches retain only the byte and entry budget', () async {
    final keys = {for (var index = 0; index < 10000; index++) 'icon-$index'};
    for (final (maxEntries, maxBytes, retained) in [(4, 6, 2), (3, 1024, 3)]) {
      final sizes = <int>[];
      final cache = BarIconCache<Uint8List>(
        maxEntries: maxEntries,
        maxBytes: maxBytes,
        size: (bytes) => bytes.lengthInBytes,
        lookup: (keys) async {
          sizes.add(keys.length);
          return {for (final key in keys) key: Uint8List(3)};
        },
        onChanged: () {},
      );
      addTearDown(cache.dispose);
      cache.resolve(keys);
      await Future<void>.delayed(Duration.zero);
      expect(sizes.every((size) => size <= 256), isTrue);
      expect(sizes.fold<int>(0, (total, size) => total + size), keys.length);
      expect(
        keys.where((key) => cache[key] != null),
        keys.skip(keys.length - retained),
      );
    }
  });

  testWidgets('a file icon retries and refreshes without new notifications', (
    tester,
  ) async {
    var now = DateTime(2026);
    var requests = 0;
    final cache = BarIconCache<Uint8List>(
      now: () => now,
      retryOnIdle: true,
      refreshAfter: (_) => const Duration(seconds: 30),
      lookup: (_) async => ++requests == 1
          ? {}
          : {
              '/tmp/icon.png': Uint8List.fromList([requests]),
            },
      onChanged: () {},
    );
    cache.resolve({'/tmp/icon.png'});
    await tester.pump();
    expect(cache['/tmp/icon.png'], isNull);
    now = now.add(const Duration(seconds: 15));
    await tester.pump(const Duration(seconds: 15));
    expect(cache['/tmp/icon.png'], [2]);
    now = now.add(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
    expect(cache['/tmp/icon.png'], [3]);
    cache.dispose();
  });
}
