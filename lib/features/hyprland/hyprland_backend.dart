import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import '../../src/rust/hyprland_bridge/api.dart';
import '../../src/rust/hyprland_bridge/frb_generated.dart';
import '../../widgets/bar_icon_cache.dart';

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
  }) : _position = (outputX, outputY);

  final String? outputName;
  final Future<HyprlandSnapshot> Function({required int slotCount})
  readSnapshot;
  final Future<void> Function({
    required String outputName,
    required int workspaceId,
    required int slotCount,
  })
  activateWorkspace;
  final Future<void> Function({
    required String outputName,
    required int direction,
    required int slotCount,
  })
  scrollWorkspace;
  final Future<void> Function({
    required String outputName,
    required int slotCount,
  })
  toggleSpecialWorkspace;
  int _workspaceCount = 8;
  int? _snapshotWorkspaceCount;
  late final _icons = BarIconCache<String>(
    lookup: lookupBarIconPaths,
    onChanged: notifyListeners,
  );
  (int?, int?) _position;
  StreamSubscription<HyprlandUpdate>? _subscription;
  Timer? _reconcile;
  Timer? _eventRefresh;
  Future<void>? _refreshing;
  bool _pendingRefresh = false;
  bool _disposed = false;
  HyprlandSnapshot? _snapshot;
  String? _focusedOutput;
  Future<String?>? _focusRequest;
  int _focusRevision = 0;
  String? error;
  HyprlandUpdate? latest;
  bool connected = false;
  bool superHeld = false;

  List<HyprlandMonitor> get monitors => _snapshot?.monitors ?? [];

  Future<String?> focusedOutput() async {
    if (_focusedOutput case final name?) return name;
    return _focusRequest ??= _readFocusedOutput().whenComplete(
      () => _focusRequest = null,
    );
  }

  Future<String?> _readFocusedOutput() async {
    final revision = _focusRevision;
    final workspace = jsonDecode(await request('j/activeworkspace'));
    if (revision == _focusRevision && workspace is Map) {
      final name = workspace['monitor'];
      if (name is String) _focusedOutput = name;
    }
    return _focusedOutput;
  }

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
  String? iconPath(String appId) => _icons[appId];

  HyprlandWindow? get currentWindow => output?.currentWindow;

  /// Updates the workspace count for reads and actions on this output.
  Future<void> setWorkspaceCount(int count) {
    if (_disposed || count < 1 || count > 10) return Future.value();
    if (count == _workspaceCount) {
      if (_refreshing case final refresh?) return refresh;
      if (count == _snapshotWorkspaceCount && error == null) {
        return Future.value();
      }
    }
    _workspaceCount = count;
    return refresh();
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
        if (update.kind == 'event' && update.name == 'focusedmon') {
          _focusRevision++;
          _focusedOutput = update.data.split(',').firstOrNull;
        } else if (const {
          'connected',
          'disconnected',
          'resync',
        }.contains(update.kind)) {
          _focusRevision++;
          _focusedOutput = null;
        }
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
        _focusRevision++;
        _focusedOutput = null;
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
    if (_refreshing case final active?) return active;
    final completion = Completer<void>();
    _refreshing = completion.future;
    completion.complete(_refreshLoop());
    return completion.future;
  }

  Future<void> _refreshLoop() async {
    try {
      while (_pendingRefresh && !_disposed) {
        _pendingRefresh = false;
        final count = _workspaceCount;
        try {
          final snapshot = await readSnapshot(slotCount: count);
          if (_disposed) return;
          if (count != _workspaceCount) continue;
          _snapshot = snapshot;
          _snapshotWorkspaceCount = count;
          connected = true;
          error = output == null ? 'Output unavailable' : null;
        } catch (failure) {
          if (_disposed) return;
          if (count != _workspaceCount) continue;
          error = 'Hyprland unavailable';
          debugPrint('Hyprland workspace refresh: $failure');
        }
        notifyListeners();
        _resolveIcons();
        if (_pendingRefresh) {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        }
      }
    } finally {
      _refreshing = null;
    }
  }

  Future<bool> switchWorkspace(int id) async {
    if (id == 0 ||
        !(allWorkspaces.any((workspace) => workspace.id == id) ||
            workspaceSlots.any((slot) => slot.id == id))) {
      return false;
    }
    return _workspaceAction(
      (name, count) => activateWorkspace(
        outputName: name,
        workspaceId: id,
        slotCount: count,
      ),
    );
  }

  Future<void> scroll(int direction) async {
    if (direction != -1 && direction != 1) return;
    await _workspaceAction(
      (name, count) => scrollWorkspace(
        outputName: name,
        direction: direction,
        slotCount: count,
      ),
    );
  }

  Future<void> toggleSpecial() async {
    await _workspaceAction(
      (name, count) =>
          toggleSpecialWorkspace(outputName: name, slotCount: count),
    );
  }

  Future<bool> _workspaceAction(
    Future<void> Function(String output, int slotCount) action,
  ) async {
    final monitor = output;
    final count = _snapshotWorkspaceCount;
    if (_disposed ||
        !connected ||
        error != null ||
        monitor == null ||
        count == null) {
      return false;
    }
    try {
      await action(monitor.name, count);
      await refresh();
      return true;
    } catch (failure) {
      debugPrint('Hyprland workspace switch: $failure');
      return false;
    }
  }

  void _resolveIcons() {
    _icons.resolve({
      for (final monitor in _snapshot?.monitors ?? <HyprlandMonitor>[])
        for (final slot in monitor.workspaceSlots)
          for (final app in slot.apps)
            if (app.isNotEmpty) app,
    });
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
    _icons.dispose();
    super.dispose();
  }
}
