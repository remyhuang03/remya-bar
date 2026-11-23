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

const _eventWindow = Duration(milliseconds: 80);

/// Owns the compositor subscription, refresh queue and icon paths for all views.
class HyprlandStore extends ChangeNotifier {
  HyprlandStore({
    this.readSnapshot = hyprlandSnapshot,
    this.watch = subscribeHyprland,
  });

  final Future<HyprlandSnapshot> Function({required int slotCount})
  readSnapshot;
  final Stream<HyprlandUpdate> Function() watch;
  late final _icons = BarIconCache<String>(
    lookup: lookupBarIconPaths,
    onChanged: notifyListeners,
  );
  StreamSubscription<HyprlandUpdate>? _subscription;
  Timer? _reconcile;
  Timer? _eventRefresh;
  Future<void>? _refreshing;
  bool _pendingRefresh = false;
  bool _disposed = false;
  bool _started = false;
  bool _connected = false;
  bool _superHeld = false;
  String? _error;
  int _workspaceCount = 8;
  int? _snapshotWorkspaceCount;
  HyprlandSnapshot? _snapshot;
  String? _focusedOutput;
  Future<String?>? _focusRequest;
  int _focusRevision = 0;
  int _connectionRevision = 0;
  int snapshotReads = 0;
  int snapshotRevision = 0;
  DateTime? capturedAt;
  final _layoutChanges = ValueNotifier<int>(0);

  ValueListenable<int> get layoutChanges => _layoutChanges;

  void start() {
    _started = true;
    _startWatching();
  }

  void _attach(VoidCallback listener) {
    addListener(listener);
    _startWatching();
  }

  void _detach(VoidCallback listener) {
    removeListener(listener);
    if (_disposed || hasListeners || _subscription == null) return;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _reconcile?.cancel();
    _reconcile = null;
    _snapshot = null;
    _snapshotWorkspaceCount = null;
    _disconnect();
  }

  void _startWatching() {
    if (!_started || _disposed || !hasListeners || _subscription != null) {
      return;
    }
    _subscription = watch().listen(
      _onUpdate,
      onError: (Object error, StackTrace stack) {
        debugPrint('Hyprland IPC: $error');
        _disconnect();
      },
      onDone: _disconnect,
    );
    _reconcile = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(refresh()),
    );
    unawaited(refresh());
  }

  void _onUpdate(HyprlandUpdate update) {
    switch (update.kind) {
      case 'modifier' when update.name == 'super':
        _setSuperHeld(update.data == 'true');
      case 'disconnected':
        _disconnect();
      case 'connected' || 'resync':
        _connectionRevision++;
        _focusRevision++;
        _focusedOutput = null;
        _scheduleRefresh();
      case 'event':
        if (update.name == 'focusedmon') {
          _focusRevision++;
          final name = update.data.split(',').firstOrNull;
          if (name != null && name.isNotEmpty && _focusedOutput != name) {
            _focusedOutput = name;
            notifyListeners();
          }
        }
        if (update.name == 'activelayout') {
          _layoutChanges.value++;
        }
        if (_affectsWorkspaces(update.name)) _scheduleRefresh();
    }
  }

  void _disconnect() {
    if (_disposed) return;
    _connectionRevision++;
    _focusRevision++;
    _focusedOutput = null;
    _eventRefresh?.cancel();
    _eventRefresh = null;
    _pendingRefresh = false;
    _connected = false;
    _superHeld = false;
    _error = 'Hyprland unavailable';
    notifyListeners();
  }

  void _setSuperHeld(bool held) {
    if (_superHeld == held) return;
    _superHeld = held;
    notifyListeners();
  }

  void _scheduleRefresh() {
    if (_refreshing != null) {
      _pendingRefresh = true;
      return;
    }
    _eventRefresh ??= Timer(_eventWindow, () {
      _eventRefresh = null;
      unawaited(refresh());
    });
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

  Future<String?> focusedOutput() async {
    if (_focusedOutput case final name?) return name;
    return _focusRequest ??= _readFocusedOutput().whenComplete(
      () => _focusRequest = null,
    );
  }

  Future<String?> _readFocusedOutput() async {
    final revision = _focusRevision;
    final workspace = jsonDecode(
      await hyprlandRequest(command: 'j/activeworkspace'),
    );
    if (revision == _focusRevision && workspace is Map) {
      final name = workspace['monitor'];
      if (!_disposed && name is String && name != _focusedOutput) {
        _focusRevision++;
        _focusedOutput = name;
        notifyListeners();
      }
    }
    return _focusedOutput;
  }

  Future<void> setWorkspaceCount(int count) {
    if (_disposed || count < 1 || count > 10) return Future.value();
    if (count == _workspaceCount) {
      if (_refreshing case final refresh?) return refresh;
      if (count == _snapshotWorkspaceCount && _error == null) {
        return Future.value();
      }
    }
    _workspaceCount = count;
    return refresh();
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    _eventRefresh?.cancel();
    _eventRefresh = null;
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
        final revision = _connectionRevision;
        final focusRevision = _focusRevision;
        try {
          snapshotReads++;
          final snapshot = await readSnapshot(slotCount: count);
          if (_disposed) return;
          if (count == _workspaceCount && revision == _connectionRevision) {
            _snapshot = snapshot;
            _snapshotWorkspaceCount = count;
            if (focusRevision == _focusRevision &&
                snapshot.focusedOutput != null &&
                snapshot.focusedOutput != _focusedOutput) {
              _focusRevision++;
              _focusedOutput = snapshot.focusedOutput;
            }
            snapshotRevision++;
            capturedAt = DateTime.now();
            _connected = true;
            _error = null;
            _icons.resolve({
              for (final monitor in snapshot.monitors)
                for (final slot in monitor.workspaceSlots)
                  for (final app in slot.apps)
                    if (app.isNotEmpty) app,
            });
            notifyListeners();
          }
        } catch (failure) {
          if (_disposed) return;
          if (count == _workspaceCount && revision == _connectionRevision) {
            _error = 'Hyprland unavailable';
            debugPrint('Hyprland workspace refresh: $failure');
            notifyListeners();
          }
        }
        if (_pendingRefresh) await Future<void>.delayed(_eventWindow);
      }
    } finally {
      _refreshing = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _reconcile?.cancel();
    _eventRefresh?.cancel();
    unawaited(_subscription?.cancel());
    _icons.dispose();
    _layoutChanges.dispose();
    super.dispose();
  }
}

/// Projects shared desktop state into an output's workspace, window and bar.
class HyprlandBackend extends ChangeNotifier {
  HyprlandBackend({
    this.outputName,
    int? outputX,
    int? outputY,
    HyprlandStore? store,
    Future<HyprlandSnapshot> Function({required int slotCount}) readSnapshot =
        hyprlandSnapshot,
    this.activateWorkspace = hyprlandSwitchWorkspace,
    this.scrollWorkspace = hyprlandScrollWorkspace,
    this.toggleSpecialWorkspace = hyprlandToggleSpecial,
  }) : _position = (outputX, outputY),
       _store = store ?? HyprlandStore(readSnapshot: readSnapshot),
       _ownsStore = store == null {
    _store._attach(_project);
    _project();
  }

  final String? outputName;
  final HyprlandStore _store;
  final bool _ownsStore;
  final Future<void> Function({
    required String outputName,
    required String workspaceAddress,
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
  (int?, int?) _position;
  bool _disposed = false;
  bool connected = false;
  bool get isFocused => _isFocused;
  bool _isFocused = false;
  bool get superHeld => _superHeld;
  @visibleForTesting
  set superHeld(bool held) => _store._setSuperHeld(held);
  bool _superHeld = false;
  String? error;
  HyprlandMonitor? output;
  String? get activeWorkspaceName => _activeWorkspaceName;
  String? _activeWorkspaceName;
  List<(String, int)> _outputLabels = const [];
  Map<String, String?> _visibleIcons = const {};

  List<HyprlandMonitor> get monitors => _store._snapshot?.monitors ?? [];
  List<HyprlandWorkspace> get workspaces => [
    for (final workspace in allWorkspaces)
      if (workspace.monitorName == output?.name) workspace,
  ];
  List<HyprlandWorkspace> get allWorkspaces =>
      _store._snapshot?.workspaces ?? [];
  List<HyprlandWorkspaceSlot> get workspaceSlots =>
      output?.workspaceSlots ?? [];
  HyprlandWindow? get currentWindow => output?.currentWindow;

  String? iconPath(String appId) => _store._icons[appId];

  void _project() {
    final matches = monitors.where(
      (monitor) => outputName != null
          ? monitor.name == outputName
          : monitor.x == _position.$1 && monitor.y == _position.$2,
    );
    final next = matches.length == 1 ? matches.single : null;
    final nextFocused = next != null && next.name == _store._focusedOutput;
    final nextError =
        _store._error ??
        (_store._snapshot != null && next == null
            ? 'Output unavailable'
            : null);
    final nextName =
        next != null && !next.workspaceSlots.any((slot) => slot.active)
        ? allWorkspaces
              .where(
                (workspace) => workspace.address == next.activeWorkspaceAddress,
              )
              .firstOrNull
              ?.name
        : null;
    final nextLabels = [
      for (final monitor in monitors) (monitor.name, monitor.outputNumber),
    ];
    final nextIcons = {
      for (final slot in next?.workspaceSlots ?? <HyprlandWorkspaceSlot>[])
        for (final app in slot.apps) app: iconPath(app),
    };
    final changed =
        !_sameOutput(output, next) ||
        connected != _store._connected ||
        _isFocused != nextFocused ||
        superHeld != _store._superHeld ||
        error != nextError ||
        _activeWorkspaceName != nextName ||
        !listEquals(_outputLabels, nextLabels) ||
        !mapEquals(_visibleIcons, nextIcons);
    output = next;
    connected = _store._connected;
    _isFocused = nextFocused;
    _superHeld = _store._superHeld;
    error = nextError;
    _activeWorkspaceName = nextName;
    _outputLabels = nextLabels;
    _visibleIcons = nextIcons;
    if (changed) notifyListeners();
  }

  Future<String?> focusedOutput() => _store.focusedOutput();
  ValueListenable<int> get layoutChanges => _store.layoutChanges;
  Future<void> setWorkspaceCount(int count) => _store.setWorkspaceCount(count);
  Future<void> refresh() => _store.refresh();
  void start() => _store.start();

  void updateOutput({required int x, required int y}) {
    if (_disposed || outputName != null || _position == (x, y)) return;
    _position = (x, y);
    _project();
    _store._scheduleRefresh();
  }

  static Future<void> initialize() => HyprlandRustLib.init(
    externalLibrary: ExternalLibrary.open(
      '${File(Platform.resolvedExecutable).parent.path}/lib/libremya_bar_hyprland.so',
    ),
  );

  Future<bool> switchWorkspace(String address) async {
    if (!(allWorkspaces.any((workspace) => workspace.address == address) ||
        workspaceSlots.any(
          (slot) => slot.id > 0 && slot.id.toString() == address,
        ))) {
      return false;
    }
    return _workspaceAction(
      (name, count) => activateWorkspace(
        outputName: name,
        workspaceAddress: address,
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
    final count = _store._snapshotWorkspaceCount;
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

  Future<String> request(String command) => hyprlandRequest(command: command);

  @override
  void dispose() {
    _disposed = true;
    _store._detach(_project);
    if (_ownsStore) _store.dispose();
    super.dispose();
  }
}

bool _sameOutput(HyprlandMonitor? first, HyprlandMonitor? second) {
  if (identical(first, second)) return true;
  if (first == null || second == null) return false;
  Object metadata(HyprlandMonitor monitor) => (
    monitor.name,
    monitor.outputNumber,
    monitor.activeWorkspaceAddress,
    monitor.specialWorkspaceAddress,
    monitor.specialWorkspaceName,
    monitor.currentWindow,
    monitor.fullscreen,
  );
  if (metadata(first) != metadata(second)) return false;
  final a = first.workspaceSlots;
  final b = second.workspaceSlots;
  Object slotFields(HyprlandWorkspaceSlot slot) => (
    slot.id,
    slot.name,
    slot.active,
    slot.occupied,
    slot.windowCount,
    slot.owner,
    slot.urgent,
  );
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (slotFields(a[i]) != slotFields(b[i]) ||
        !listEquals(a[i].apps, b[i].apps)) {
      return false;
    }
  }
  return true;
}
