import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/bar_theme.dart';
import 'package:remya_bar/features/hyprland/hyprland_backend.dart';
import 'package:remya_bar/features/popups/bar_popup.dart';
import 'package:remya_bar/features/window/bar_active_window.dart';
import 'package:remya_bar/features/workspaces/bar_workspaces.dart';
import 'package:remya_client/remya_client.dart';
import 'package:remya_ui/remya_ui.dart';

const _window = HyprlandWindow(
  address: '0xa',
  title: 'Report',
  appId: 'editor',
  workspaceId: 3,
  monitorName: 'DP-1',
);

const _slots = [
  HyprlandWorkspaceSlot(
    id: 1,
    name: '1',
    active: false,
    occupied: false,
    urgent: false,
    apps: [],
    windowCount: 0,
  ),
  HyprlandWorkspaceSlot(
    id: 2,
    name: '2',
    active: false,
    occupied: true,
    urgent: false,
    apps: ['other'],
    owner: 'DP-2',
    windowCount: 1,
  ),
  HyprlandWorkspaceSlot(
    id: 3,
    name: 'Writing',
    active: true,
    occupied: true,
    urgent: false,
    apps: ['editor'],
    owner: 'DP-1',
    windowCount: 1,
  ),
  HyprlandWorkspaceSlot(
    id: 4,
    name: '4',
    active: false,
    occupied: false,
    urgent: false,
    apps: [],
    windowCount: 0,
  ),
  HyprlandWorkspaceSlot(
    id: 5,
    name: '5',
    active: false,
    occupied: false,
    urgent: false,
    apps: [],
    windowCount: 0,
  ),
  HyprlandWorkspaceSlot(
    id: 6,
    name: '6',
    active: false,
    occupied: false,
    urgent: false,
    apps: [],
    windowCount: 0,
  ),
  HyprlandWorkspaceSlot(
    id: 7,
    name: '7',
    active: false,
    occupied: false,
    urgent: false,
    apps: [],
    windowCount: 0,
  ),
  HyprlandWorkspaceSlot(
    id: 8,
    name: '8',
    active: false,
    occupied: false,
    urgent: false,
    apps: [],
    windowCount: 0,
  ),
];

const _snapshot = HyprlandSnapshot(
  monitors: [
    HyprlandMonitor(
      name: 'DP-1',
      outputNumber: 1,
      x: 1920,
      y: 0,
      activeWorkspaceId: 3,
      currentWindow: _window,
      workspaceSlots: _slots,
    ),
    HyprlandMonitor(
      name: 'DP-2',
      outputNumber: 2,
      x: 0,
      y: 0,
      activeWorkspaceId: 2,
      workspaceSlots: [],
    ),
  ],
  workspaces: [
    HyprlandWorkspace(
      id: 1,
      name: '1',
      monitorName: 'DP-1',
      windowCount: 0,
      windows: [],
    ),
    HyprlandWorkspace(
      id: 2,
      name: '2',
      monitorName: 'DP-2',
      windowCount: 0,
      windows: [],
    ),
    HyprlandWorkspace(
      id: 3,
      name: 'Writing',
      monitorName: 'DP-1',
      windowCount: 1,
      windows: [_window],
    ),
    HyprlandWorkspace(
      id: -1337,
      name: 'Notes',
      monitorName: 'DP-2',
      windowCount: 0,
      windows: [],
    ),
  ],
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const icons = MethodChannel('top.remya.bar/icons');
  setUp(
    () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
      icons,
      (_) async => <String, String>{},
    ),
  );
  tearDown(
    () => binding.defaultBinaryMessenger.setMockMethodCallHandler(icons, null),
  );

  test('ambiguous output geometry does not select another monitor', () async {
    final backend = HyprlandBackend(
      outputX: 0,
      outputY: 0,
      readSnapshot: () async => const HyprlandSnapshot(
        monitors: [
          HyprlandMonitor(
            name: 'DP-1',
            outputNumber: 1,
            x: 0,
            y: 0,
            activeWorkspaceId: 1,
            workspaceSlots: [],
          ),
          HyprlandMonitor(
            name: 'DP-2',
            outputNumber: 2,
            x: 0,
            y: 0,
            activeWorkspaceId: 2,
            workspaceSlots: [],
          ),
        ],
        workspaces: [],
      ),
    );
    addTearDown(backend.dispose);
    await backend.refresh();
    expect(backend.output, isNull);
    expect(backend.error, 'Output unavailable');
  });

  test('geometry resolves own output and failed reads preserve its last valid state', () async {
    var fail = false;
    final backend = HyprlandBackend(
      outputX: 1920,
      outputY: 0,
      readSnapshot: () async {
        if (fail) throw StateError('Disconnected');
        return _snapshot;
      },
    );
    addTearDown(backend.dispose);
    await backend.refresh();
    expect(backend.output?.name, 'DP-1');
    expect(backend.workspaces.map((workspace) => workspace.id), [1, 3]);
    expect(backend.currentWindow?.title, 'Report');
    fail = true;
    await backend.refresh();
    expect(backend.error, 'Hyprland unavailable');
    expect(backend.currentWindow, _window);
    backend.updateOutput(x: 0, y: 0);
    expect(backend.output?.name, 'DP-2');
    expect(backend.currentWindow, isNull);
    backend.updateOutput(x: -500, y: 0);
    expect(backend.output, isNull);
    expect(backend.workspaces, isEmpty);
  });

  test(
    'concurrent refreshes coalesce without overlapping snapshot reads',
    () async {
      final firstRead = Completer<HyprlandSnapshot>();
      var reads = 0;
      var concurrent = 0;
      var maximum = 0;
      final backend = HyprlandBackend(
        outputName: 'DP-1',
        readSnapshot: () async {
          reads++;
          concurrent++;
          if (concurrent > maximum) maximum = concurrent;
          final snapshot = reads == 1 ? await firstRead.future : _snapshot;
          concurrent--;
          return snapshot;
        },
      );
      addTearDown(backend.dispose);
      final initial = backend.refresh();
      final pending = [for (var i = 0; i < 20; i++) backend.refresh()];
      firstRead.complete(_snapshot);
      await Future.wait([initial, ...pending]);
      expect(reads, 2);
      expect(maximum, 1);
    },
  );

  testWidgets(
    'eight fixed slots show global occupancy and empty targets remain clickable',
    (tester) async {
      final activations = <(String, int)>[];
      final backend = HyprlandBackend(
        outputName: 'DP-1',
        readSnapshot: () async => _snapshot,
        activateWorkspace: ({required outputName, required workspaceId}) async {
          activations.add((outputName, workspaceId));
        },
      );
      addTearDown(backend.dispose);
      await backend.refresh();
      await tester.pumpWidget(
        MaterialApp(
          theme: barTheme(ThemeData()),
          home: Scaffold(
            body: Align(
              alignment: .topLeft,
              child: SizedBox(
                height: 32,
                child: BarWorkspaces(backend: backend),
              ),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.apps_rounded), findsNWidgets(2));
      expect(tester.getSize(find.byType(BarWorkspaces)), const Size(242, 32));
      expect(
        tester.getSize(find.byKey(const ValueKey('workspace-1'))),
        const Size(26, 26),
      );
      expect(
        tester.getSize(
          find.byKey(const ValueKey('workspace-active-indicator')),
        ),
        const Size(22, 22),
      );
      await tester.tap(find.byKey(const ValueKey('workspace-1')));
      await tester.pump();
      expect(activations, [('DP-1', 1)]);
      await tester.tap(find.byKey(const ValueKey('workspace-4')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('workspace-2')));
      await tester.pump();
      await backend.switchWorkspace(-1337);
      await backend.switchWorkspace(-1);
      await backend.switchWorkspace(42);
      expect(activations, [
        ('DP-1', 1),
        ('DP-1', 4),
        ('DP-1', 2),
        ('DP-1', -1337),
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unavailable workspaces do not fabricate a selected desktop', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BarWorkspaces())),
    );
    expect(find.byType(IconButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'hover shows the workspace tooltip and right click opens the overview',
    (tester) async {
      final calls = <MethodCall>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        BarPopup.channel,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          BarPopup.channel,
          null,
        ),
      );
      final backend = HyprlandBackend(
        outputName: 'DP-1',
        readSnapshot: () async => _snapshot,
      );
      addTearDown(backend.dispose);
      await backend.refresh();
      await tester.pumpWidget(
        BarPopupScope(
          theme: RemyaTheme.fromConfig(const ThemeConfig()),
          child: MaterialApp(
            theme: barTheme(ThemeData()),
            home: Scaffold(
              body: Align(
                alignment: .topLeft,
                child: SizedBox(
                  height: 32,
                  child: BarWorkspaces(backend: backend),
                ),
              ),
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(
        kind: .mouse,
        buttons: kSecondaryMouseButton,
      );
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('workspace-3'))),
      );
      await tester.pump(const Duration(milliseconds: 700));
      await mouse.down(
        tester.getCenter(find.byKey(const ValueKey('workspace-3'))),
      );
      await mouse.up();
      await tester.pump(const Duration(milliseconds: 700));
      await mouse.moveTo(const Offset(400, 100));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(
        calls
            .where((call) => call.method == 'show')
            .map((call) => call.arguments['kind']),
        ['tooltip', workspaceOverviewKind],
      );
      expect(
        calls.first.arguments['data']['message'],
        'Workspace Writing · Display 1 (DP-1)\neditor',
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'icon classes are looked up once and invalid native paths are ignored',
    () async {
      var lookups = 0;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(icons, (
        call,
      ) async {
        expect(call.method, 'lookup');
        expect(call.arguments, containsAll(['other', 'editor']));
        lookups++;
        return {
          'other': '/tmp/other.png',
          'editor': '/tmp/editor.svg',
          'unrequested': '/tmp/unrequested.png',
        };
      });
      final backend = HyprlandBackend(
        outputName: 'DP-1',
        readSnapshot: () async => _snapshot,
      );
      addTearDown(backend.dispose);
      await backend.refresh();
      await Future<void>.delayed(Duration.zero);
      await backend.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(lookups, 1);
      expect(backend.iconPath('other'), '/tmp/other.png');
      expect(backend.iconPath('editor'), isNull);
      expect(backend.iconPath('unrequested'), isNull);
    },
  );

  testWidgets('wheel and back button use the owner output actions', (
    tester,
  ) async {
    final directions = <(String, int)>[];
    final specials = <String>[];
    final backend = HyprlandBackend(
      outputName: 'DP-1',
      readSnapshot: () async => _snapshot,
      scrollWorkspace: ({required outputName, required direction}) async {
        directions.add((outputName, direction));
      },
      toggleSpecialWorkspace: ({required outputName}) async =>
          specials.add(outputName),
    );
    addTearDown(backend.dispose);
    await backend.refresh();
    await tester.pumpWidget(
      MaterialApp(
        theme: barTheme(ThemeData()),
        home: Scaffold(
          body: Align(
            alignment: .topLeft,
            child: SizedBox(height: 32, child: BarWorkspaces(backend: backend)),
          ),
        ),
      ),
    );
    final position = tester.getCenter(find.byType(BarWorkspaces));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: position, scrollDelta: const Offset(0, 20)),
    );
    await tester.pump();
    await tester.sendEventToBinding(
      PointerScrollEvent(position: position, scrollDelta: const Offset(0, -20)),
    );
    await tester.pump();
    await tester.sendEventToBinding(
      PointerDownEvent(
        position: position,
        kind: .mouse,
        buttons: kBackMouseButton,
      ),
    );
    await tester.sendEventToBinding(
      PointerUpEvent(position: position, kind: .mouse),
    );
    await tester.pump();
    expect(directions, [('DP-1', 1), ('DP-1', -1)]);
    expect(specials, ['DP-1']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'active group changes keep slots fixed and animate the indicator',
    (tester) async {
      var snapshot = _snapshot;
      final backend = HyprlandBackend(
        outputName: 'DP-1',
        readSnapshot: () async => snapshot,
      );
      addTearDown(backend.dispose);
      await backend.refresh();
      await tester.pumpWidget(
        MaterialApp(
          theme: barTheme(ThemeData()),
          home: Scaffold(
            body: Align(
              alignment: .topLeft,
              child: SizedBox(
                height: 32,
                child: BarWorkspaces(backend: backend),
              ),
            ),
          ),
        ),
      );
      snapshot = HyprlandSnapshot(
        monitors: [
          HyprlandMonitor(
            name: 'DP-1',
            outputNumber: 1,
            x: 1920,
            y: 0,
            activeWorkspaceId: 14,
            workspaceSlots: [
              for (var id = 9; id <= 16; id++)
                HyprlandWorkspaceSlot(
                  id: id,
                  name: '$id',
                  active: id == 14,
                  occupied: false,
                  urgent: false,
                  apps: [],
                  windowCount: 0,
                ),
            ],
          ),
        ],
        workspaces: [],
      );
      await backend.refresh();
      await tester.pump();
      await tester.pumpAndSettle();
      final pill = tester.getTopLeft(find.byType(BarWorkspaces));
      final indicator = tester.getTopLeft(
        find.byKey(const ValueKey('workspace-active-indicator')),
      );
      expect(indicator.dx - pill.dx, 135);
      expect(find.byKey(const ValueKey('workspace-1')), findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('workspace-14'))),
        const Size(26, 26),
      );
      expect(tester.getSize(find.byType(BarWorkspaces)).width, 214);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'multi-app slots expand, Super reveals IDs, and Special dims slots',
    (tester) async {
      final backend = HyprlandBackend(
        outputName: 'DP-1',
        readSnapshot: () async => HyprlandSnapshot(
          monitors: [
            HyprlandMonitor(
              name: 'DP-1',
              outputNumber: 1,
              x: 1920,
              y: 0,
              activeWorkspaceId: 3,
              specialWorkspaceId: -99,
              specialWorkspaceName: 'special:scratchpad',
              workspaceSlots: [
                ..._slots.take(2),
                const HyprlandWorkspaceSlot(
                  id: 3,
                  name: '3',
                  active: true,
                  occupied: true,
                  windowCount: 4,
                  owner: 'DP-1',
                  apps: ['editor', 'browser', 'terminal', 'mail'],
                  urgent: true,
                ),
                ..._slots.skip(3),
              ],
            ),
            _snapshot.monitors[1],
          ],
          workspaces: _snapshot.workspaces,
        ),
      );
      addTearDown(backend.dispose);
      await backend.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: BarWorkspaces(backend: backend)),
        ),
      );
      expect(find.text('scratchpad'), findsOneWidget);
      expect(tester.getSize(find.byType(BarWorkspaces)), const Size(282, 32));
      expect(find.text('+2'), findsOneWidget);
      // Empty workspaces show their number instead of a dot.
      expect(find.text('8'), findsOneWidget);

      backend.superHeld = true;
      await backend.refresh();
      await tester.pumpAndSettle();
      expect(find.text('scratchpad'), findsNothing);
      expect(find.text('+2'), findsNothing);
      expect(find.text('8'), findsOneWidget);
      expect(tester.getSize(find.byType(BarWorkspaces)), const Size(242, 32));
    },
  );

  testWidgets('active window uses the output snapshot and fits large text', (
    tester,
  ) async {
    final backend = HyprlandBackend(
      outputName: 'DP-1',
      readSnapshot: () async => _snapshot,
    );
    addTearDown(backend.dispose);
    await backend.refresh();
    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: barTheme(ThemeData()),
          home: MediaQuery(
            data: MediaQueryData(textScaler: .linear(scale)),
            child: Scaffold(
              body: Align(
                alignment: .topLeft,
                child: SizedBox(
                  width: 200,
                  height: 40,
                  child: BarActiveWindow(backend: backend),
                ),
              ),
            ),
          ),
        ),
      );
      if (scale == 1) expect(find.text('editor'), findsOneWidget);
      expect(find.text('Report'), findsOneWidget);
      expect(find.text('UI preview'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
