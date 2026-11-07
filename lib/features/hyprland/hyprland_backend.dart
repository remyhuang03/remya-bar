import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import '../../src/rust/hyprland_bridge/api.dart';
import '../../src/rust/hyprland_bridge/frb_generated.dart';

export '../../src/rust/hyprland_bridge/api.dart'
    show
        HyprlandUpdate,
        HyprlandSnapshot,
        HyprlandMonitor,
        HyprlandWorkspace,
        HyprlandWorkspaceSlot,
        HyprlandWindow;

class HyprlandBackend extends ChangeNotifier {
  HyprlandBackend({
    this.outputName,
    int? outputX,
    int? outputY,
    this.readSnapshot = hyprlandSnapshot,
    this.activateWorkspace = hyprlandSwitchWorkspace,
    this.scrollWorkspace = hyprlandScrollWorkspace,
    this.toggleSpecialWorkspace = hyprlandToggleSpecial,
    this.setSlotCount = hyprlandSetWorkspaceCount,
  }) : _position = (outputX, outputY);

  final String? outputName;
  final Future<HyprlandSnapshot> Function() readSnapshot;
  final Future<void> Function({
    required String outputName,
    required int workspaceId,
  })
  activateWorkspace;
  final Future<void> Function({
    required String outputName,
    required int direction,
  })
  scrollWorkspace;
  final Future<void> Function({required String outputName})
  toggleSpecialWorkspace;
  final Future<void> Function({required int count}) setSlotCount;
  int _workspaceCount = 8;
  final _iconPaths = <String, String>{};
  final _requestedIcons = <String>{};
  (int?, int?) _position;
  StreamSubscription<HyprlandUpdate>? _subscription;
  Timer? _reconcile;
  Timer? _eventRefresh;
  Future<void>? _refreshing;
  bool _pendingRefresh = false;
  bool _disposed = false;
  HyprlandSnapshot? _snapshot;
  String? error;
  HyprlandUpdate? latest;
  bool connected = false;
  bool superHeld = false;

  List<HyprlandMonitor> get monitors => _snapshot?.monitors ?? [];

  HyprlandMonitor? get output {
    final matches = (_snapshot?.monitors ?? <HyprlandMonitor>[]).where(
      (monitor) => outputName != null
          ? monitor.name == outputName
          : monitor.x == _position.$1 && monitor.y == _position.$2,
    );
    return matches.length == 1 ? matches.single : null;
  }

  List<HyprlandWorkspace> get workspaces => [
    for (final workspace in _snapshot?.workspaces ?? <HyprlandWorkspace>[])
      if (workspace.monitorName == output?.name) workspace,
  ];

  List<HyprlandWorkspace> get allWorkspaces => _snapshot?.workspaces ?? [];
  List<HyprlandWorkspaceSlot> get workspaceSlots =>
      output?.workspaceSlots ?? [];
  String? iconPath(String appId) => _iconPaths[appId];

  HyprlandWindow? get currentWindow => output?.currentWindow;

  /// Applies the Settings workspace count, shared by every output in Rust.
  Future<void> setWorkspaceCount(int count) async {
    if (_disposed || count == _workspaceCount) return;
    _workspaceCount = count;
    try {
      await setSlotCount(count: count);
      await refresh();
    } catch (error) {
      debugPrint('Hyprland workspace count: $error');
    }
  }

  void updateOutput({required int x, required int y}) {
    if (_disposed || _position == (x, y)) return;
    _position = (x, y);
    notifyListeners();
    unawaited(refresh());
  }

  static Future<void> initialize() => HyprlandRustLib.init(
    externalLibrary: ExternalLibrary.open(
      '${File(Platform.resolvedExecutable).parent.path}/lib/libremya_bar_hyprland.so',
    ),
  );

  void start() {
    if (_subscription != null || _disposed) return;
    _subscription = subscribeHyprland().listen(
      (update) {
        if (update.kind == 'heartbeat') return;
        if (update.kind == 'modifier' && update.name == 'super') {
          final held = update.data == 'true';
          if (held != superHeld) {
            superHeld = held;
            notifyListeners();
          }
          return;
        }
        latest = update;
        if (update.kind == 'connected') connected = true;
        if (update.kind == 'disconnected') connected = false;
        if (update.kind != 'event') {
          debugPrint('Hyprland IPC: ${update.kind}');
        }
        if (update.kind == 'connected' ||
            update.kind == 'resync' ||
            update.kind == 'event' && _affectsWorkspaces(update.name)) {
          _eventRefresh ??= Timer(const Duration(milliseconds: 80), () {
            _eventRefresh = null;
            unawaited(refresh());
          });
        }
        if (update.kind == 'disconnected') {
          superHeld = false;
          error = 'Hyprland unavailable';
          notifyListeners();
        }
      },
      onError: (Object error, StackTrace stack) {
        connected = false;
        this.error = 'Hyprland unavailable';
        debugPrint('Hyprland IPC: $error');
        notifyListeners();
      },
    );
    _reconcile = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(refresh()),
    );
    unawaited(refresh());
  }

  bool _affectsWorkspaces(String name) => const [
    'workspace',
    'createworkspace',
    'destroyworkspace',
    'moveworkspace',
    'renameworkspace',
    'focusedmon',
    'activewindow',
    'urgent',
    'openwindow',
    'closewindow',
    'movewindow',
    'windowtitle',
    'fullscreen',
    'monitoradded',
    'monitorremoved',
    'activespecial',
    'changefloatingmode',
    'changegroupactive',
    'pin',
    'configreloaded',
  ].any(name.startsWith);

  Future<void> refresh() {
    if (_disposed) return Future.value();
    _pendingRefresh = true;
    return _refreshing ??= _refreshLoop().whenComplete(
      () => _refreshing = null,
    );
  }

  Future<void> _refreshLoop() async {
    while (_pendingRefresh && !_disposed) {
      _pendingRefresh = false;
      try {
        final snapshot = await readSnapshot();
        if (_disposed) return;
        _snapshot = snapshot;
        connected = true;
        error = output == null ? 'Output unavailable' : null;
      } catch (failure) {
        if (_disposed) return;
        error = 'Hyprland unavailable';
        debugPrint('Hyprland workspace refresh: $failure');
      }
      notifyListeners();
      unawaited(_resolveIcons());
      if (_pendingRefresh) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    }
  }

  Future<bool> switchWorkspace(int id) async {
    if (id == 0 ||
        !(allWorkspaces.any((workspace) => workspace.id == id) ||
            workspaceSlots.any((slot) => slot.id == id))) {
      return false;
    }
    return _workspaceAction(
      (name) => activateWorkspace(outputName: name, workspaceId: id),
    );
  }

  Future<void> scroll(int direction) async {
    if (direction != -1 && direction != 1) return;
    await _workspaceAction(
      (name) => scrollWorkspace(outputName: name, direction: direction),
    );
  }

  Future<void> toggleSpecial() async {
    await _workspaceAction((name) => toggleSpecialWorkspace(outputName: name));
  }

  Future<bool> _workspaceAction(
    Future<void> Function(String output) action,
  ) async {
    final monitor = output;
    if (_disposed || !connected || error != null || monitor == null) {
      return false;
    }
    try {
      await action(monitor.name);
      await refresh();
      return true;
    } catch (failure) {
      debugPrint('Hyprland workspace switch: $failure');
      return false;
    }
  }

  Future<void> _resolveIcons() async {
    if (_disposed) return;
    final classes = <String>{
      for (final monitor in _snapshot?.monitors ?? <HyprlandMonitor>[])
        for (final slot in monitor.workspaceSlots)
          for (final app in slot.apps)
            if (app.isNotEmpty) app,
    }.difference(_requestedIcons);
    if (classes.isEmpty) return;
    _requestedIcons.addAll(classes);
    try {
      final paths = await const MethodChannel('top.remya.bar/icons')
          .invokeMapMethod<String, String>('lookup', classes.toList());
      if (_disposed || paths == null) return;
      for (final entry in paths.entries) {
        if (classes.contains(entry.key) &&
            entry.value.startsWith('/') &&
            entry.value.toLowerCase().endsWith('.png')) {
          _iconPaths[entry.key] = entry.value;
        }
      }
      notifyListeners();
    } catch (failure) {
      debugPrint('Workspace icons unavailable: $failure');
    }
  }

  Future<bool> isOutputFullscreen(int x, int y) =>
      hyprlandOutputFullscreen(x: x, y: y);

  Future<String> request(String command) => hyprlandRequest(command: command);

  @override
  void dispose() {
    _disposed = true;
    _reconcile?.cancel();
    _eventRefresh?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
