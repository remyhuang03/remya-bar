import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/app.dart';
import 'package:remya_bar/features/popups/bar_popup.dart';
import 'package:remya_bar/features/resources/bar_resources.dart';
import 'package:remya_bar/features/resources/resource_style.dart';
import 'package:remya_bar/features/system/system_backend.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

const _snapshot = SystemSnapshot(
  batteries: [],
  cpuPercent: 91,
  memoryUsedBytes: 8200000000,
  memoryTotalBytes: 32000000000,
  gpus: [GpuSnapshot(id: 'gpu0', name: 'GPU', utilizationPercent: 0)],
  networkOverview: NetworkOverview(uploadBytesPerSecond: 86000),
);

void main() {
  test('rates round to two significant figures and keep zero distinct from missing', () {
    expect(resourceRate(2400000, compact: true), '2.4M');
    expect(resourceRate(86400, compact: true), '86K');
    expect(resourceRate(999900, compact: true), '1.0M');
    expect(resourceRate(9960), '10 KB/s');
    expect(resourceRate(0), '0 B/s');
    expect(resourceRate(.1), '<1 B/s');
    expect(resourceRate(null), '—');
    expect(resourceCritical(90), isFalse);
    expect(resourceCritical(90.1), isTrue);
  });

  testWidgets('pill shows memory percentage and opens the live card on hover', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(BarPopup.channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(BarPopup.channel, null),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: BarPopupScope(
          theme: RemyaTheme(),
          child: Center(
            child: BarResources(snapshot: _snapshot, cardSnapshot: _snapshot),
          ),
        ),
      ),
    );
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('26%'), findsOneWidget);
    expect(tester.widget<Text>(find.text('26%')).style!.fontFeatures, isNull);
    expect(find.text('86K'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('91%')).style!.color,
      Theme.of(tester.element(find.text('91%'))).colorScheme.error,
    );
    expect(calls, isEmpty);
    final mouse = await tester.createGesture(kind: .mouse);
    await mouse.addPointer(location: tester.getCenter(find.text('91%')));
    await tester.pump();
    expect(find.text('CPU'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 299));
    expect(calls.where((call) => call.method == 'show'), isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    final show = calls.firstWhere((call) => call.method == 'show');
    expect(show.arguments['kind'], 'resources');
    expect(show.arguments['data']['download'], isNull);
    expect(show.arguments['data']['upload'], 86000);
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
    await tester.pump();
    expect(calls.lastWhere((call) => call.method == 'leave').arguments, {
      'kind': 'resources',
    });
  });

  testWidgets(
    'pill waits three seconds while the card gets the latest sample',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 40);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final system = SystemBackend()..resourceSnapshot = _snapshot;
      final preferences = SettingsThemeController(
        () => File('/nonexistent/theme.toml'),
      );
      Widget app() => RemyaBarApp(preferences: preferences, system: system);
      BarResources pill() => tester.widget(find.byType(BarResources));
      await tester.pumpWidget(app());
      system.resourceSnapshot = const SystemSnapshot(
        cpuPercent: 42,
        gpus: [],
        batteries: [],
      );
      await tester.pumpWidget(app());
      await tester.pump(const Duration(seconds: 2));
      expect(pill().snapshot?.cpuPercent, 91);
      expect(pill().cardSnapshot?.cpuPercent, 42);
      await tester.pump(const Duration(seconds: 1));
      expect(pill().snapshot?.cpuPercent, 42);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
