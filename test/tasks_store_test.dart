import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remya_bar/features/tasks/tasks_store.dart';
import 'package:remya_client/remya_client.dart';

typedef _Json = Map<String, dynamic>;

class _Google extends SettingsClient {
  String subject = 'alice';
  bool offline = false;
  bool ambiguousCreate = false;
  bool expired = false;
  bool multipleLists = false;
  bool _listing = false;
  int creations = 0;
  final calls = <(String, String, _Json)>[];
  final data = <String, Map<String, _Json>>{
    for (final account in ['alice', 'bob'])
      account: {
        'one': {
          'id': 'one',
          'position': '100',
          'title': '$account task',
          'status': 'needsAction',
          'etag': '1',
        },
        'two': {
          'id': 'two',
          'title': '$account completed',
          'status': 'completed',
          'hidden': true,
        },
      },
  };

  @override
  Stream<SettingsChange> get changes => const Stream.empty();

  @override
  Stream<bool> get serviceAvailableChanges => const Stream.empty();

  @override
  Future<_Json> call(String method, [List<String> arguments = const []]) async {
    if (method == 'Get' && arguments.single == googleAccountTopic) {
      return {
        'configured': true,
        'pending': false,
        'accountId': subject,
        'email': '$subject@example.com',
        'calendar': false,
        'tasks': true,
        'error': null,
      };
    }
    expect(method, 'GoogleTasks');
    final request = jsonDecode(arguments.single) as _Json;
    final accountId = request['accountId'] as String;
    final operation = request['operation'] as String;
    final args = request['args'] as _Json;
    expect(accountId, subject);
    calls.add((subject, operation, args));
    if (offline) {
      throw const GoogleTasksException('offline', 'Offline');
    }
    if (expired) {
      throw const GoogleTasksException('auth', 'Reconnect');
    }
    final tasks = data[subject]!;
    const list = {'id': 'shared-id', 'title': 'My Tasks'};
    switch (operation) {
      case 'lists.list':
        return {
          'items': [
            list,
            if (multipleLists) const {'id': 'other', 'title': 'Other'},
          ],
        };
      case 'lists.get':
        return list;
      case 'tasks.list':
        if (_listing) {
          throw const GoogleTasksException(
            'retry',
            'Request already in progress',
          );
        }
        _listing = true;
        await Future<void>.delayed(Duration.zero);
        _listing = false;
        if (args['listId'] == 'other') return {'items': []};
        final token = args['pageToken'];
        if (token == 'tail') {
          return {
            'items': [tasks['two']],
          };
        }
        if (args.containsKey('updatedMin')) return {'items': []};
        return {
          'items': [
            for (final task in tasks.values)
              if (task['id'] != 'two') task,
          ],
          'nextPageToken': 'tail',
        };
      case 'tasks.get':
        return tasks[args['taskId']] ??
            (throw const GoogleTasksException('missing', 'Task missing'));
      case 'tasks.patch':
        final id = args['taskId'] as String;
        final task = tasks[id]!;
        final updated = <String, dynamic>{
          ...task,
          ...(args['body'] as _Json),
          'etag': '${int.parse((task['etag'] ?? '1') as String) + 1}',
        };
        tasks[id] = updated;
        return updated;
      case 'tasks.insert':
        final id = 'created-${creations++}';
        final created = {'id': id, ...(args['body'] as _Json)};
        tasks[id] = created;
        if (ambiguousCreate) {
          throw const GoogleTasksException('ambiguous', 'May be saved');
        }
        return created;
      default:
        fail('Unexpected operation $operation');
    }
  }
}

void main() {
  late _Google google;
  late Directory directory;
  final stores = <TasksStore>[];

  setUp(() {
    google = _Google();
    directory = Directory.systemTemp.createTempSync('remya-tasks-test-');
  });

  tearDown(() async {
    for (final store in stores) {
      store.dispose();
    }
    stores.clear();
    await google.close();
    await directory.delete(recursive: true);
  });

  TasksStore open() {
    final store = TasksStore(client: google, stateDirectory: directory);
    stores.add(store);
    store.setAutomatic(false);
    store.start();
    return store;
  }

  void close(TasksStore store) {
    stores.remove(store);
    store.dispose();
  }

  test('keeps a Google calendar date across UTC offsets', () {
    expect(
      googleScheduledDate('2026-11-20T01:00:00+10:00'),
      DateTime(2026, 11, 20),
    );
    expect(googleScheduledDate('2026-02-30T00:00:00Z'), isNull);
    expect(
      googleScheduledDatePayload(DateTime(2026, 11, 20)),
      '2026-11-20T00:00:00.000Z',
    );
  });

  test(
    'paginates the complete snapshot and preserves results absent from a delta',
    () async {
      final store = open();
      await store.refresh();
      expect(store.state, TasksSyncState.ready);
      expect(store.defaultListId, 'shared-id');
      expect(store.tasks.map((task) => task.id), containsAll(['one', 'two']));
      expect(
        store.tasks.singleWhere((task) => task.id == 'two').hidden,
        isTrue,
      );
      final pages = google.calls.where((call) => call.$2 == 'tasks.list');
      expect(pages.last.$3['pageToken'], 'tail');
      expect(pages.first.$3, containsPair('showAssigned', true));
      expect(pages.first.$3, containsPair('showDeleted', true));
      expect(pages.first.$3, containsPair('showHidden', true));
      expect(pages.first.$3, containsPair('showCompleted', true));

      await store.refresh();
      expect(pages.last.$3['updatedMin'], isA<String>());
      expect(store.tasks, hasLength(2));
      // Both hosts can share a store without reading on widget attach.
      final count = google.calls.length;
      store.start();
      expect(google.calls, hasLength(count));
    },
  );

  test('syncs multiple lists without overlapping Core requests', () async {
    google.multipleLists = true;
    final store = open();
    await store.refresh(full: true);
    expect(store.state, TasksSyncState.ready);
    expect(store.lists, hasLength(2));
    final pages = google.calls.where((call) => call.$2 == 'tasks.list');
    expect(pages.map((page) => page.$3['listId']), [
      'shared-id',
      'shared-id',
      'other',
    ]);
  });

  test(
    'three-way merge touches only changed fields and resolves conflicts safely',
    () async {
      final store = open();
      await store.refresh();
      final before = store.findTask('shared-id', 'one')!;
      final remote = google.data['alice']!;
      remote['one']!['notes'] = 'Edited remotely';
      await store.editTask(before, {'title': 'New title'});
      await store.refresh();
      final sent = google.calls.lastWhere((call) => call.$2 == 'tasks.patch');
      expect(sent.$3['body'], {'title': 'New title'});
      expect(store.findTask('shared-id', 'one')?.notes, 'Edited remotely');

      final base = store.findTask('shared-id', 'one')!;
      remote['one']!['title'] = 'Google title';
      await store.editTask(base, {'title': 'Mine', 'notes': 'My notes'});
      await store.refresh();
      expect(store.conflicts.single.fields.single.name, 'title');
      expect(store.conflicts.single.fields.single.google, 'Google title');
      await store.resolveConflict(store.conflicts.single, keepMine: false);
      await store.refresh();
      expect(remote['one']?['title'], 'Google title');
      expect(remote['one']?['notes'], 'My notes');

      final task = store.findTask('shared-id', 'one')!;
      remote['one']!['title'] = 'Second Google title';
      await store.editTask(task, {'title': 'My second title'});
      await store.refresh();
      await store.resolveConflict(store.conflicts.single, keepMine: true);
      await store.refresh();
      expect(remote['one']?['title'], 'My second title');
      expect(store.pendingCount, 0);
    },
  );

  test('retains offline edits and editor bases across restart and isolates accounts', () async {
    final store = open();
    await store.refresh();
    final task = store.findTask('shared-id', 'one')!;
    google.offline = true;
    store.saveDraft(task, {
      'title': 'Draft',
      'scheduled': DateTime(2026, 11, 20),
    });
    await store.editTask(task, {'completed': true});
    await store.refresh();
    expect(store.state, TasksSyncState.offline);
    expect(store.findTask('shared-id', 'one')?.completed, isTrue);
    close(store);

    final reopened = open();
    await reopened.refresh();
    expect(reopened.pendingCount, 1);
    expect(reopened.draftCount, 1);
    expect(reopened.findTask('shared-id', 'one')?.pending, isTrue);
    google.offline = false;
    google.subject = 'bob';
    await reopened.refresh();
    expect(reopened.pendingCount, 0);
    expect(reopened.findTask('shared-id', 'one')?.title, 'bob task');
    await expectLater(
      reopened.editTask(task, {'title': 'Wrong account'}),
      throwsA(isA<TasksEditException>()),
    );
    expect(google.data['bob']!['one']?['status'], 'needsAction');

    google.subject = 'alice';
    await reopened.refresh();
    expect(reopened.pendingCount, 0);
    expect(google.data['alice']!['one']?['status'], 'completed');
    final before = reopened.findTask('shared-id', 'one')!;
    reopened.saveDraft(before, {'title': 'Later draft'});
    google.data['alice']!['one']!['title'] = 'Remote then draft';
    await reopened.refresh(full: true);
    final after = reopened.findTask('shared-id', 'one')!;
    expect(reopened.draftFor(after), {'title': 'Later draft'});
    expect(reopened.draftBaseFor(after)?.title, 'alice task');
    await reopened.editTask(after, {'title': 'Submit draft'}, clearDraft: true);
    expect(reopened.draftCount, 0);
    await reopened.refresh();
  });

  test(
    're-fetches a timed-out create without reissuing it after restart',
    () async {
      final store = open();
      await store.refresh();
      google.ambiguousCreate = true;
      final optimistic = await store.addTask('shared-id', 'Unsure task');
      expect(optimistic.pending, isTrue);
      await store.refresh();
      expect(google.creations, 1);
      expect(store.issues.single.ambiguous, isTrue);
      expect(store.issues.single.title, 'Unsure task');
      close(store);

      final reopened = open();
      await reopened.refresh(full: true);
      await reopened.retry();
      expect(google.creations, 1);
      expect(reopened.issues.single.ambiguous, isTrue);
      expect(reopened.findTask('shared-id', 'created-0')?.title, 'Unsure task');
    },
  );
  test('pauses replay on expired authorization until a reconnect', () async {
    final store = open();
    await store.refresh();
    google.expired = true;
    final one = store.findTask('shared-id', 'one')!;
    await store.editTask(one, {'title': 'After reconnect'});
    await store.refresh();
    expect(store.state, TasksSyncState.authRequired);
    final calls = google.calls.length;
    await store.addTask('shared-id', 'Another offline change');
    await Future<void>.delayed(Duration.zero);
    expect(google.calls, hasLength(calls));
    expect(store.pendingCount, 2);

    google.expired = false;
    await store.refresh();
    expect(store.state, TasksSyncState.ready);
    expect(store.pendingCount, 0);
    expect(google.data['alice']!['one']?['title'], 'After reconnect');
  });

  test('does not recreate an edited task that Google deleted', () async {
    final store = open();
    await store.refresh();
    final one = store.findTask('shared-id', 'one')!;
    google.data['alice']!.remove('one');
    await store.editTask(one, {'title': 'Mine'});
    await store.refresh();
    expect(store.conflicts.single.canKeepMine, isFalse);
    expect(store.findTask('shared-id', 'one'), isNull);
    await store.resolveConflict(store.conflicts.single, keepMine: false);
    await store.refresh();
    expect(store.pendingCount, 0);
    expect(google.creations, 0);
  });
}
