part of 'tasks_store.dart';

typedef _Json = Map<String, dynamic>;
typedef _TaskKey = (String, String);

enum _EditPhase { queued, sending, conflict, failed, ambiguous }

class _TaskEdit {
  _TaskEdit(
    this.id,
    this.op,
    this.args,
    this.base, {
    this.phase = .queued,
    this.message,
    this.remote,
    this.conflicting = const [],
  });

  factory _TaskEdit.fromJson(_Json json) {
    final phase = _EditPhase.values.byName(json['phase'] as String);
    final operation = json['op'] as String;
    return _TaskEdit(
      json['id'] as String,
      operation,
      Map<String, dynamic>.from(json['args'] as Map),
      Map<String, dynamic>.from(json['base'] as Map),
      phase: phase,
      message: json['message'] as String?,
      remote: json['remote'] as _Json?,
      conflicting: (json['conflicting'] as List).cast<String>(),
    ).afterInterruption();
  }

  final String id;
  final String op;
  final _Json args;
  final _Json base;
  final _EditPhase phase;
  final String? message;
  final _Json? remote;
  final List<String> conflicting;

  String? get listId => args['listId'] as String?;
  String? get taskId => args['taskId'] as String?;
  _TaskKey? get taskKey => op.startsWith('tasks.') && op != 'tasks.clear'
      ? (listId!, taskId ?? id)
      : null;
  _Json get body => (args['body'] as _Json?) ?? const {};
  String get title =>
      (body['title'] ?? base['title'] ?? 'Tasks change') as String;
  bool get inserts => op.endsWith('.insert');
  bool get bulk => op == 'lists.delete' || op == 'tasks.clear';
  Iterable<String> get affectedLists sync* {
    if ((listId ?? (op == 'lists.insert' ? id : null))
        case final String value) {
      yield value;
    }
    if (args['destinationTasklist'] case final String value) yield value;
  }

  _TaskEdit change(
    _EditPhase updated, {
    String? message,
    _Json? remote,
    List<String> conflicting = const [],
    _Json? args,
    _Json? base,
  }) => _TaskEdit(
    id,
    op,
    args ?? this.args,
    base ?? this.base,
    phase: updated,
    message: message,
    remote: remote,
    conflicting: conflicting,
  );

  _TaskEdit afterInterruption() {
    if (phase != .sending) return this;
    return _requiresExplicitRetry(op)
        ? change(.ambiguous, message: _uncertainMessage)
        : change(.queued);
  }

  _Json toJson() => {
    'id': id,
    'op': op,
    'args': args,
    'base': base,
    'phase': phase.name,
    'message': message,
    'remote': remote,
    'conflicting': conflicting,
  };
}

const _uncertainMessage =
    'Google may have saved this change. Check Google Tasks before trying again.';

bool _requiresExplicitRetry(String operation) =>
    operation.endsWith('.insert') ||
    operation == 'tasks.move' ||
    operation == 'tasks.clear';

class _TaskDraft {
  const _TaskDraft(this.base, this.body);

  factory _TaskDraft.fromJson(_Json json) =>
      _TaskDraft(json['base'] as _Json, json['body'] as _Json);

  final _Json base;
  final _Json body;

  _TaskKey get key => (base['listId'] as String, base['id'] as String);
  _Json toJson() => {'base': base, 'body': body};
}

class _TaskCache {
  const _TaskCache({
    this.lists = const {},
    this.tasks = const {},
    this.lastSync,
    this.checkpoint,
    this.lastFull,
    this.defaultListId,
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
    defaultListId: json['defaultListId'] as String?,
  );

  final Map<String, _Json> lists;
  final Map<_TaskKey, _Json> tasks;
  final DateTime? lastSync;
  final DateTime? checkpoint;
  final DateTime? lastFull;
  final String? defaultListId;

  _Json toJson() => {
    'lists': lists.values.toList(growable: false),
    'tasks': tasks.values.toList(growable: false),
    'lastSync': lastSync?.toIso8601String(),
    'checkpoint': checkpoint?.toIso8601String(),
    'lastFull': lastFull?.toIso8601String(),
    'defaultListId': defaultListId,
  };
}

class _TaskAccount {
  _TaskAccount(this.id, Directory? root)
    : directory = root == null
          ? null
          : Directory('${root.path}/${base64Url.encode(utf8.encode(id))}');

  final String id;
  final Directory? directory;
  var cache = const _TaskCache();
  var edits = <_TaskEdit>[];
  var drafts = <_TaskKey, _TaskDraft>{};
  bool queueReadable = true;
  bool loaded = false;
  bool fullRequired = false;

  Future<void> read() async {
    if (directory case final Directory folder) {
      final queueFile = File('${folder.path}/edits.json');
      try {
        if (await queueFile.exists()) {
          final raw = jsonDecode(await queueFile.readAsString()) as _Json;
          edits = (raw['edits'] as List)
              .cast<_Json>()
              .map(_TaskEdit.fromJson)
              .toList();
          drafts = {
            for (final draft in (raw['drafts'] as List).cast<_Json>().map(
              _TaskDraft.fromJson,
            ))
              draft.key: draft,
          };
        }
      } on Object {
        queueReadable = false;
      }
      final cacheFile = File('${folder.path}/cache.json');
      if (await cacheFile.exists()) {
        try {
          cache = await Isolate.run(() => _readTaskCache(cacheFile.path));
        } on Object {
          // The next complete pull can reconstruct the confirmed snapshot.
          fullRequired = true;
        }
      }
    }
    loaded = true;
  }

  void saveEdits(List<_TaskEdit> next, Map<_TaskKey, _TaskDraft> drafts) {
    if (!queueReadable) {
      throw const TasksEditException(
        'Saved Tasks changes could not be loaded.',
      );
    }
    try {
      final target = _stateFile('edits.json');
      if (target != null) {
        _atomicTaskWrite(target.path, {
          'edits': next.map((edit) => edit.toJson()).toList(),
          'drafts': drafts.values.map((draft) => draft.toJson()).toList(),
        });
      }
    } on FileSystemException {
      throw const TasksEditException(
        'Could not save the change on this device.',
      );
    }
    edits = next;
    this.drafts = drafts;
  }

  Future<void> saveCache(_TaskCache next) async {
    final target = _stateFile('cache.json');
    if (target != null) {
      final path = target.path;
      await Isolate.run(() => _atomicTaskWrite(path, next.toJson()));
    }
    cache = next;
  }

  File? _stateFile(String name) {
    final folder = directory;
    if (folder == null) return null;
    if (!folder.existsSync()) {
      folder.createSync(recursive: true);
      final result = Process.runSync('chmod', ['700', folder.path]);
      if (result.exitCode != 0) {
        throw const FileSystemException('Could not protect Tasks state');
      }
    }
    if ((folder.statSync().mode & 0x3f) != 0) {
      throw const FileSystemException('Tasks state directory is not private');
    }
    return File('${folder.path}/$name');
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
          uri.hasAuthority &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? raw as String
      : null;
}

GoogleTask _model(
  _Json raw, {
  String? accountId,
  bool pending = false,
  String? error,
}) {
  final assignment = raw['assignmentInfo'] as _Json?;
  final links = (raw['links'] as List?)?.whereType<_Json>();
  return GoogleTask(
    id: _id(raw),
    listId: raw['listId'] as String,
    title: (raw['title'] as String?) ?? '',
    notes: (raw['notes'] as String?) ?? '',
    position: (raw['position'] as String?) ?? '',
    etag: raw['etag'] as String?,
    parent: raw['parent'] as String?,
    sourceLink:
        _webUrl(assignment?['linkToTask']) ??
        links
            ?.map((link) => _webUrl(link['link']))
            .whereType<String>()
            .firstOrNull,
    sourceKind: assignment?['surfaceType'] as String?,
    webViewLink: _webUrl(raw['webViewLink']),
    scheduled: googleScheduledDate(raw['due']),
    completed: raw['status'] == 'completed',
    hidden: raw['hidden'] == true,
    deleted: raw['deleted'] == true,
    assigned: assignment != null,
    pending: pending,
    error: error,
    accountId: accountId,
  );
}

_Json _baseline(GoogleTask task) => {
  'id': task.id,
  'listId': task.listId,
  'title': task.title,
  'notes': task.notes,
  'due': task.scheduled == null
      ? null
      : googleScheduledDatePayload(task.scheduled!),
  'status': task.completed ? 'completed' : 'needsAction',
  'etag': task.etag,
  'parent': task.parent,
  'position': task.position,
};

_Json _listBaseline(TaskList list) => {
  'id': list.id,
  'title': list.title,
  'etag': list.etag,
};

Object? _field(_Json raw, String name) => switch (name) {
  'title' || 'notes' => raw[name] ?? '',
  'due' => googleScheduledDate(raw[name]),
  'status' => raw[name] ?? 'needsAction',
  _ => raw[name],
};
