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

late BarPopup _popup;

const _window = HyprlandWindow(
  address: '0xa',
  title: 'Report',
  appId: 'editor',
  workspaceAddress: '3',
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
      fullscreen: false,
      name: 'DP-1',
      outputNumber: 1,
      x: 1920,
      y: 0,
      activeWorkspaceAddress: '3',
      currentWindow: _window,
      workspaceSlots: _slots,
    ),
    HyprlandMonitor(
      fullscreen: false,
      name: 'DP-2',
      outputNumber: 2,
      x: 0,
      y: 0,
      activeWorkspaceAddress: '2',
      workspaceSlots: [],
    ),
  ],
  workspaces: [
    HyprlandWorkspace(
      address: '1',
      name: '1',
      monitorName: 'DP-1',
      windowCount: 0,
      windows: [],
    ),
    HyprlandWorkspace(
      address: '2',
      name: '2',
      monitorName: 'DP-2',
      windowCount: 0,
      windows: [],
    ),
    HyprlandWorkspace(
      address: '3',
      name: 'Writing',
      monitorName: 'DP-1',
      windowCount: 1,
      windows: [_window],
    ),
    HyprlandWorkspace(
      address: 'Notes',
      name: 'Notes',
      monitorName: 'DP-2',
      windowCount: 0,
      windows: [],
    ),
  ],
);

void main() {
  setUp(() => _popup = BarPopup.forView(1));
  tearDown(() => _popup.dispose());
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

  test(
    'shared Hyprland events refresh once and notify only the changed output',
    () async {
      final events = StreamController<HyprlandUpdate>(sync: true);
      final secondRead = Completer<void>();
      final changed = Completer<HyprlandSnapshot>();
      var subscriptions = 0;
      var reads = 0;
      final store = HyprlandStore(
        watch: () {
          subscriptions++;
          return events.stream;
        },
        readSnapshot: ({required slotCount}) async {
          if (++reads == 1) return _snapshot;
          secondRead.complete();
          return changed.future;
        },
      );
      final first = HyprlandBackend(outputName: 'DP-1', store: store);
      final second = HyprlandBackend(outputName: 'DP-2', store: store);
      addTearDown(() async {
        first.dispose();
        expect(events.hasListener, isTrue);
        second.dispose();
        expect(events.hasListener, isFalse);
        store.dispose();
        await events.close();
      });
      first.start();
      second.start();
      await store.setWorkspaceCount(8);
      expect(subscriptions, 1);
      expect(reads, 1);
      expect(first.output?.name, 'DP-1');
      expect(second.output?.name, 'DP-2');

      var firstChanges = 0;
      var secondChanges = 0;
      first.addListener(() => firstChanges++);
      second.addListener(() => secondChanges++);
      for (var i = 0; i < 20; i++) {
        events.add(
          const HyprlandUpdate(kind: 'event', name: 'fullscreen', data: '1'),
        );
      }
      await secondRead.future;
      changed.complete(
        HyprlandSnapshot(
          monitors: [
            for (final output in _snapshot.monitors)
              HyprlandMonitor(
                fullscreen: output.name == 'DP-2',
                name: output.name,
                outputNumber: output.outputNumber,
                x: output.x,
                y: output.y,
                activeWorkspaceAddress: output.activeWorkspaceAddress,
                specialWorkspaceAddress: output.specialWorkspaceAddress,
                specialWorkspaceName: output.specialWorkspaceName,
                currentWindow: output.currentWindow,
                workspaceSlots: [
                  for (final slot in output.workspaceSlots)
                    HyprlandWorkspaceSlot(
                      id: slot.id,
                      name: slot.name,
                      active: slot.active,
                      occupied: slot.occupied,
                      windowCount: slot.windowCount,
                      owner: slot.owner,
                      urgent: slot.urgent,
                      apps: [...slot.apps],
                    ),
                ],
              ),
          ],
          workspaces: _snapshot.workspaces,
        ),
      );
      await store.setWorkspaceCount(8);
      expect(reads, 2);
      expect(firstChanges, 0);
      expect(secondChanges, 1);
      expect(second.output?.fullscreen, isTrue);
      expect(store.snapshotReads, 2);
      expect(store.snapshotRevision, 2);
      expect(store.capturedAt, isNotNull);

      events.add(
        const HyprlandUpdate(kind: 'event', name: 'focusedmon', data: 'DP-2,2'),
      );
      expect(first.isFocused, isFalse);
      expect(second.isFocused, isTrue);
      expect(firstChanges, 0);
      expect(secondChanges, 2);
    },
  );

  test(
    'a snapshot from a disconnected Hyprland generation is discarded',
    () async {
      final events = StreamController<HyprlandUpdate>(sync: true);
      final completion = Completer<HyprlandSnapshot>();
      final store = HyprlandStore(
        watch: () => events.stream,
        readSnapshot: ({required slotCount}) => completion.future,
      )..start();
      final output = HyprlandBackend(outputName: 'DP-1', store: store);
      addTearDown(() async {
        output.dispose();
        store.dispose();
        await events.close();
      });

      events.add(
        const HyprlandUpdate(kind: 'disconnected', name: '', data: ''),
      );
      completion.complete(_snapshot);
      await store.setWorkspaceCount(8);
      expect(output.connected, isFalse);
      expect(output.output, isNull);
      expect(output.error, 'Hyprland unavailable');
    },
  );

  test('workspace count retries after a failed snapshot', () async {
    final counts = <int>[];
    final backend = HyprlandBackend(
      outputName: 'DP-1',
      readSnapshot: ({required slotCount}) async {
        counts.add(slotCount);
        if (counts.length == 1) throw StateError('Compositor unavailable');
        return _snapshot;
      },
    );
    addTearDown(backend.dispose);
    await backend.setWorkspaceCount(10);
    expect(backend.error, 'Hyprland unavailable');
    await backend.setWorkspaceCount(10);
    expect(backend.error, isNull);
    await backend.setWorkspaceCount(10);
    expect(counts, [10, 10]);
  });

  test('workspace snapshots publish only the latest count', () async {
    final counts = <int>[];
    final first = Completer<HyprlandSnapshot>();
    final entered = Completer<void>();
    final backend = HyprlandBackend(
      outputName: 'DP-1',
      readSnapshot: ({required slotCount}) async {
        counts.add(slotCount);
        if (counts.length == 1) {
          entered.complete();
          return first.future;
        }
        return _snapshot;
      },
    );
    addTearDown(backend.dispose);
    var changes = 0;
    backend.addListener(() => changes++);
    final eight = backend.setWorkspaceCount(8);
    await entered.future;
    final ten = backend.setWorkspaceCount(10);
    final six = backend.setWorkspaceCount(6);
    first.complete(_snapshot);
    await Future.wait([eight, ten, six]);
    expect(counts, [8, 6]);
    expect(changes, 1);
  });

  test('disposing drops a pending workspace snapshot', () async {
    final pending = Completer<HyprlandSnapshot>();
    final entered = Completer<void>();
    final backend = HyprlandBackend(
      outputName: 'DP-1',
      readSnapshot: ({required slotCount}) {
        entered.complete();
        return pending.future;
      },
    );
    final reading = backend.setWorkspaceCount(10);
    await entered.future;
    backend.dispose();
    pending.complete(_snapshot);
    await reading;
    expect(backend.connected, isFalse);
    expect(backend.output, isNull);
  });

  test('ambiguous output geometry does not select another monitor', () async {
    final backend = HyprlandBackend(
      outputX: 0,
      outputY: 0,
      readSnapshot: ({required slotCount}) async => const HyprlandSnapshot(
        monitors: [
          HyprlandMonitor(
            fullscreen: false,
            name: 'DP-1',
            outputNumber: 1,
            x: 0,
            y: 0,
            activeWorkspaceAddress: '1',
            workspaceSlots: [],
          ),
          HyprlandMonitor(
            fullscreen: false,
            name: 'DP-2',
            outputNumber: 2,
            x: 0,
            y: 0,
            activeWorkspaceAddress: '2',
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
      readSnapshot: ({required slotCount}) async {
        if (fail) throw StateError('Disconnected');
        return _snapshot;
      },
    );
    addTearDown(backend.dispose);
    await backend.refresh();
    expect(backend.output?.name, 'DP-1');
    expect(backend.workspaces.map((workspace) => workspace.address), [
      '1',
      '3',
    ]);
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
        readSnapshot: ({required slotCount}) async {
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
      final activations = <(String, String)>[];
      final backend = HyprlandBackend(
        outputName: 'DP-1',
        readSnapshot: ({required slotCount}) async => _snapshot,
        activateWorkspace:
            ({
              required outputName,
              required workspaceAddress,
              required slotCount,
            }) async {
              activations.add((outputName, workspaceAddress));
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
      expect(activations, [('DP-1', '1')]);
      await tester.tap(find.byKey(const ValueKey('workspace-4')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('workspace-2')));
      await tester.pump();
      await backend.switchWorkspace('Notes');
      await backend.switchWorkspace('missing');
      await backend.switchWorkspace('42');
      expect(activations, [
        ('DP-1', '1'),
        ('DP-1', '4'),
        ('DP-1', '2'),
        ('DP-1', 'Notes'),
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
      binding.defaultBinaryMessenger.setMockMethodCallHandler(_popup.channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _popup.channel,
          null,
        ),
      );
      final backend = HyprlandBackend(
        outputName: 'DP-1',
        readSnapshot: ({required slotCount}) async => _snapshot,
      );
      addTearDown(backend.dispose);
      await backend.refresh();
      await tester.pumpWidget(
        BarPopupScope(
          popup: _popup,
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
      final overview = calls.firstWhere(
        (call) => call.arguments['kind'] == workspaceOverviewKind,
      );
      final rows = overview.arguments['data']['workspaces'] as List;
      expect(rows.singleWhere((row) => row['address'] == 'Notes'), {
        'address': 'Notes',
        'name': 'Notes',
        'owner': 'DP-2',
        'count': 0,
        'active': false,
      });
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
        readSnapshot: ({required slotCount}) async => _snapshot,
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
      readSnapshot: ({required slotCount}) async => _snapshot,
      scrollWorkspace:
          ({
            required outputName,
            required direction,
            required slotCount,
          }) async {
            directions.add((outputName, direction));
          },
      toggleSpecialWorkspace: ({
        required outputName,
        required slotCount,
      }) async => specials.add(outputName),
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
        readSnapshot: ({required slotCount}) async => snapshot,
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
            fullscreen: false,
            name: 'DP-1',
            outputNumber: 1,
            x: 1920,
            y: 0,
            activeWorkspaceAddress: '14',
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
        readSnapshot: ({required slotCount}) async => HyprlandSnapshot(
          monitors: [
            HyprlandMonitor(
              fullscreen: false,
              name: 'DP-1',
              outputNumber: 1,
              x: 1920,
              y: 0,
              activeWorkspaceAddress: '3',
              specialWorkspaceAddress: 'special:scratchpad',
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
      readSnapshot: ({required slotCount}) async => _snapshot,
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
