part of 'tasks_store.dart';

typedef _Json = Map<String, dynamic>;
typedef _TaskKey = (String, String);

enum _StatusPhase { queued, sending, waiting, failed }

class _StatusChange {
  const _StatusChange(
    this.key,
    this.base,
    this.completed, [
    this.phase = .queued,
  ]);

  factory _StatusChange.fromJson(_Json record) {
    final list = record['listId'] as String;
    final task = record['taskId'] as String;
    if (list.isEmpty || task.isEmpty) {
      throw const FormatException('Invalid saved Google Task ID');
    }
    final phase = _StatusPhase.values.byName(record['phase'] as String);
    return _StatusChange(
      (list, task),
      record['base'] as bool,
      record['completed'] as bool,
      phase == .sending ? .waiting : phase,
    );
  }

  final _TaskKey key;
  final bool base;
  final bool completed;
  final _StatusPhase phase;

  bool get failed => phase == .waiting || phase == .failed;
  _StatusChange withPhase(_StatusPhase phase) =>
      _StatusChange(key, base, completed, phase);

  _Json get target => {'listId': key.$1, 'taskId': key.$2};

  _Json toJson() => {
    ...target,
    'base': base,
    'completed': completed,
    'phase': phase.name,
  };
}

String _status(bool completed) => completed ? 'completed' : 'needsAction';
bool? _completed(Object? status) => switch (status) {
  'completed' => true,
  'needsAction' => false,
  _ => null,
};

class _TaskCache {
  const _TaskCache({
    this.lists = const {},
    this.tasks = const {},
    this.lastSync,
    this.checkpoint,
    this.lastFull,
  });

  factory _TaskCache.fromJson(_Json json) => _TaskCache(
    lists: {
      for (final entry in (json['lists'] as List).cast<_Json>())
        _id(entry): entry,
    },
    tasks: {
      for (final entry in (json['tasks'] as List).cast<_Json>())
        (entry['listId'] as String, _id(entry)): entry,
    },
    lastSync: _timestamp(json['lastSync']),
    checkpoint: _timestamp(json['checkpoint']),
    lastFull: _timestamp(json['lastFull']),
  );

  final Map<String, _Json> lists;
  final Map<_TaskKey, _Json> tasks;
  final DateTime? lastSync;
  final DateTime? checkpoint;
  final DateTime? lastFull;

  _Json toJson() => {
    'lists': lists.values.toList(growable: false),
    'tasks': tasks.values.toList(growable: false),
    'lastSync': lastSync?.toIso8601String(),
    'checkpoint': checkpoint?.toIso8601String(),
    'lastFull': lastFull?.toIso8601String(),
  };
}

class _TaskAccount {
  _TaskAccount(this.id, Directory root)
    : directory = Directory(
        '${root.path}/${base64Url.encode(utf8.encode(id))}',
      );

  final String id;
  final Directory directory;
  var cache = const _TaskCache();
  var changes = <_StatusChange>[];
  var workingOn = <String>{};
  bool queueReadable = true;
  bool workingOnReadable = true;

  Future<void> read() async {
    final queue = File('${directory.path}/status-queue.json');
    try {
      if (await queue.exists()) {
        final data = jsonDecode(await queue.readAsString()) as _Json;
        changes = (data['changes'] as List)
            .cast<_Json>()
            .map(_StatusChange.fromJson)
            .toList();
      }
    } on Object {
      changes = [];
      queueReadable = false;
    }

    final focus = File('${directory.path}/working-on.json');
    try {
      if (await focus.exists()) {
        final data = jsonDecode(await focus.readAsString()) as _Json;
        final ids = (data['ids'] as List).cast<String>().toSet();
        if (ids.length > 3 || ids.any((id) => id.isEmpty)) {
          throw const FormatException('Invalid Working on IDs');
        }
        workingOn = ids;
      }
    } on Object {
      workingOnReadable = false;
    }

    final snapshot = File('${directory.path}/cache.json');
    if (await snapshot.exists()) {
      try {
        cache = await Isolate.run(() => _readTaskCache(snapshot.path));
      } on Object {
        // A complete pull reconstructs the confirmed snapshot.
      }
    }
  }

  void saveChanges(List<_StatusChange> next) {
    if (!queueReadable) {
      throw const TasksEditException(
        'Saved Tasks changes could not be loaded.',
      );
    }
    try {
      _atomicTaskWrite(_statePath('status-queue.json'), {
        'changes': next.map((change) => change.toJson()).toList(),
      });
    } on FileSystemException {
      throw const TasksEditException(
        'Could not save the change on this device.',
      );
    }
    changes = next;
  }

  void saveWorkingOn(Set<String> next) {
    if (!workingOnReadable) {
      throw const TasksEditException(
        'Saved Working on tasks could not be loaded.',
      );
    }
    try {
      _atomicTaskWrite(_statePath('working-on.json'), {'ids': next.toList()});
    } on FileSystemException {
      throw const TasksEditException(
        'Could not save Working on tasks on this device.',
      );
    }
    workingOn = next;
  }

  Future<void> saveCache(_TaskCache next) async {
    final path = _statePath('cache.json');
    await Isolate.run(() => _atomicTaskWrite(path, next.toJson()));
    cache = next;
  }

  String _statePath(String name) {
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
      final result = Process.runSync('chmod', ['700', directory.path]);
      if (result.exitCode != 0) {
        throw const FileSystemException('Could not protect Tasks state');
      }
    }
    if ((directory.statSync().mode & 0x3f) != 0) {
      throw const FileSystemException('Tasks state directory is not private');
    }
    return '${directory.path}/$name';
  }
}

_TaskCache _readTaskCache(String path) =>
    _TaskCache.fromJson(jsonDecode(File(path).readAsStringSync()) as _Json);

void _atomicTaskWrite(String path, _Json data) {
  final file = File('$path.new');
  try {
    file.writeAsStringSync(jsonEncode(data), flush: true);
    file.renameSync(path);
  } finally {
    if (file.existsSync()) file.deleteSync();
  }
}

Directory _taskStateRoot() {
  final env = Platform.environment;
  if (env['XDG_STATE_HOME'] case final String state
      when state.startsWith('/')) {
    return Directory('$state/remya/bar/tasks');
  }
  if (env['HOME'] case final String home when home.startsWith('/')) {
    return Directory('$home/.local/state/remya/bar/tasks');
  }
  throw const FileSystemException(
    'An absolute XDG_STATE_HOME or HOME is required.',
  );
}

String _id(_Json raw) {
  final id = raw['id'];
  if (id is! String || id.isEmpty) {
    throw const FormatException('Missing Google Tasks resource ID');
  }
  return id;
}

DateTime? _timestamp(Object? raw) =>
    raw is String ? DateTime.tryParse(raw) : null;

String? _webUrl(Object? raw) {
  final uri = raw is String ? Uri.tryParse(raw) : null;
  return uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? raw as String
      : null;
}

GoogleTask _model(
  _Json raw, {
  required String accountId,
  bool? completed,
  bool pending = false,
  bool syncError = false,
  bool completionUndoable = false,
}) {
  final assignment = raw['assignmentInfo'] as _Json?;
  final links = (raw['links'] as List?)?.whereType<_Json>();
  return GoogleTask(
    id: _id(raw),
    listId: raw['listId'] as String,
    title: (raw['title'] as String?) ?? '',
    position: (raw['position'] as String?) ?? '',
    sourceLink:
        _webUrl(assignment?['linkToTask']) ??
        links
            ?.map((link) => _webUrl(link['link']))
            .whereType<String>()
            .firstOrNull,
    webViewLink: _webUrl(raw['webViewLink']),
    scheduled: googleScheduledDate(raw['due']),
    completed: completed ?? raw['status'] == 'completed',
    hidden: raw['hidden'] == true,
    deleted: raw['deleted'] == true,
    assigned: assignment != null,
    pending: pending,
    syncError: syncError,
    completionUndoable: completionUndoable,
    accountId: accountId,
  );
}
