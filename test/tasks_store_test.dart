import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remya_bar/features/tasks/tasks_preferences.dart';
import 'package:remya_bar/features/tasks/tasks_store.dart';
import 'package:remya_client/remya_client.dart';

typedef _Json = Map<String, dynamic>;

class _Google extends SettingsClient {
  String subject = 'alice';
  String? failRequest;
  String? failPatch;
  bool multipleLists = false;
  bool _listing = false;
  Completer<void>? patchStarted;
  Completer<void>? releasePatch;
  final calls = <(String, String, _Json)>[];
  final data = <String, Map<String, _Json>>{
    for (final account in ['alice', 'bob'])
      account: {
        'one': {
          'id': 'one',
          'position': '100',
          'title': '$account task',
          'due': '2026-11-25T00:00:00Z',
          'status': 'needsAction',
        },
        'two': {
          'id': 'two',
          'title': '$account completed',
          'status': 'completed',
          'hidden': true,
        },
        'three': {
          'id': 'three',
          'title': '$account second task',
          'due': '2026-11-26T00:00:00Z',
          'status': 'needsAction',
        },
      },
  };

  Iterable<_Json> get patches => calls
      .where((call) => call.$2 == 'tasks.patch')
      .map((call) => call.$3['body'] as _Json);

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
    if (failRequest case final error?) {
      throw GoogleTasksException(error, error);
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
      case 'tasks.list':
        expect(_listing, isFalse);
        _listing = true;
        await Future<void>.delayed(Duration.zero);
        _listing = false;
        if (args['listId'] == 'other') return {'items': []};
        if (args['pageToken'] == 'tail') {
          return {
            'items': [?tasks['two']],
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
        if (failPatch case final error?) {
          throw GoogleTasksException(error, error);
        }
        if (releasePatch case final gate?) {
          patchStarted!.complete();
          releasePatch = null;
          await gate.future;
        }
        final id = args['taskId'] as String;
        return tasks[id] = {...tasks[id]!, ...args['body'] as _Json};
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
    store.start();
    return store;
  }

  void close(TasksStore store) {
    stores.remove(store);
    store.dispose();
  }

  GoogleTask row(TasksStore store, [String id = 'one']) =>
      store.findTask('shared-id', id)!;

  test('keeps a Google calendar date across UTC offsets', () {
    expect(
      googleScheduledDate('2026-11-20T01:00:00+10:00'),
      DateTime(2026, 11, 20),
    );
    expect(googleScheduledDate('2026-02-30T00:00:00Z'), isNull);
  });

  test('refreshes a cached account automatically on startup', () async {
    final initial = open();
    await initial.refresh();
    close(initial);
    google.calls.clear();

    final reopened = open();
    await reopened.refresh();
    expect(
      google.calls.singleWhere((call) => call.$2 == 'tasks.list').$3,
      containsPair('updatedMin', isA<String>()),
    );
  });

  test('paginates full snapshots sequentially and preserves rows missing from a delta', () async {
    google.multipleLists = true;
    final store = open();
    await store.refresh();
    expect(store.state, TasksSyncState.ready);
    expect(store.lists, hasLength(2));
    expect(store.tasks, hasLength(3));
    expect(row(store, 'two').hidden, isTrue);
    final pages = google.calls.where((call) => call.$2 == 'tasks.list');
    expect(pages.map((page) => page.$3['listId']), [
      'shared-id',
      'shared-id',
      'other',
    ]);
    expect(pages.elementAt(1).$3['pageToken'], 'tail');
    expect(pages.first.$3, {
      'listId': 'shared-id',
      'showAssigned': true,
      'showDeleted': true,
      'showHidden': true,
      'showCompleted': true,
    });
    await store.refresh();
    expect(pages.last.$3['updatedMin'], isA<String>());
    expect(store.tasks, hasLength(3));
  });

  test(
    'completes optimistically and serializes undo across an in-flight patch',
    () async {
      final store = open();
      await store.refresh();
      final release = google.releasePatch = Completer<void>();
      final started = google.patchStarted = Completer<void>();

      await store.setCompleted(row(store), true);
      expect(row(store).completed, isTrue);
      expect(row(store).pending, isTrue);
      expect(row(store).completionUndoable, isTrue);
      await started.future;
      await store.undoCompletion();
      expect(row(store).completed, isFalse);
      expect(store.undoTask, isNull);

      release.complete();
      await store.refresh();
      expect(google.patches, [
        {'status': 'completed'},
        {'status': 'needsAction'},
      ]);
      expect(row(store).completed, isFalse);
      expect(store.pendingCount, 0);
    },
  );

  test(
    'rolls back a rejected write and keeps the status change for retry',
    () async {
      final store = open();
      await store.refresh();
      google.failPatch = 'denied';
      await store.setCompleted(row(store), true);
      await store.refresh();
      expect(row(store).completed, isFalse);
      expect(row(store).pending, isFalse);
      expect(row(store).syncError, isTrue);
      expect(store.state, TasksSyncState.error);
      expect(store.pendingCount, 1);

      google.failPatch = null;
      await store.retry();
      expect(row(store).completed, isTrue);
      expect(row(store).syncError, isFalse);
      expect(store.state, TasksSyncState.ready);
    },
  );

  test('restores the offline queue and switches accounts without a cross-account write', () async {
    final store = open();
    await store.refresh();
    final aliceTask = row(store);
    google.failRequest = 'offline';
    await store.setCompleted(aliceTask, true);
    await store.refresh();
    expect(store.state, TasksSyncState.offline);
    expect(row(store).completed, isFalse);
    expect(row(store).syncError, isTrue);
    close(store);

    google.subject = 'bob';
    google.failRequest = null;
    final reopened = open();
    await reopened.refresh();
    expect(reopened.pendingCount, 0);
    expect(row(reopened).title, 'bob task');
    await expectLater(
      reopened.setCompleted(aliceTask, true),
      throwsA(isA<TasksEditException>()),
    );
    expect(google.patches, isEmpty);

    google.subject = 'alice';
    await reopened.refresh();
    expect(reopened.pendingCount, 0);
    expect(row(reopened).completed, isTrue);
    expect(google.patches, [
      {'status': 'completed'},
    ]);
  });

  test('keeps a remote completion and retires the local operation', () async {
    final store = open();
    await store.refresh();
    google.data['alice']!['one']!['status'] = 'completed';
    await store.setCompleted(row(store), true);
    await store.refresh();
    expect(row(store).completed, isTrue);
    expect(store.pendingCount, 0);
    expect(store.undoTask, isNull);
    expect(google.patches, isEmpty);
  });

  test('does not write a removed or assigned task', () async {
    google.data['alice']!['three']!['assignmentInfo'] = {
      'surfaceType': 'DOCUMENT',
    };
    final store = open();
    await store.refresh();
    await expectLater(
      store.setCompleted(row(store, 'three'), true),
      throwsA(isA<TasksEditException>()),
    );
    google.data['alice']!.remove('one');
    await store.setCompleted(row(store), true);
    await store.refresh();
    expect(store.findTask('shared-id', 'one'), isNull);
    expect(store.pendingCount, 0);
    expect(google.patches, isEmpty);
  });

  test(
    'stores Working on per account, enforces the cap, and prunes hidden lists',
    () async {
      google.data['alice']!['one']!.remove('due');
      final store = open();
      await store.refresh();
      expect(row(store).scheduled, isNull);
      store.setPreferences(const TasksPreferences(workingOnLimit: 1));
      await store.toggleWorkingOn(row(store));
      expect(store.workingOnIds, {'one'});
      await expectLater(
        store.toggleWorkingOn(row(store, 'three')),
        throwsA(isA<TasksEditException>()),
      );
      close(store);

      final reopened = open();
      await reopened.refresh();
      expect(reopened.workingOnIds, {'one'});
      await reopened.toggleWorkingOn(row(reopened, 'three'));
      expect(reopened.workingOnIds, {'one', 'three'});
      google.subject = 'bob';
      await reopened.refresh();
      expect(reopened.workingOnIds, isEmpty);
      reopened.setPreferences(const TasksPreferences(workingOnLimit: 1));
      google.subject = 'alice';
      await reopened.refresh();
      expect(reopened.workingOnIds, {'one'});

      reopened.setPreferences(
        const TasksPreferences(
          visibleLists: ['other'],
          visibleListsAccount: 'bob',
        ),
      );
      expect(reopened.workingOnIds, {'one'});
      reopened.setPreferences(
        const TasksPreferences(
          visibleLists: ['other'],
          visibleListsAccount: 'alice',
        ),
      );
      expect(reopened.workingOnIds, isEmpty);
      expect(google.patches, isEmpty);
    },
  );

  test(
    'retains a merely hidden bookmark and prunes explicit remote deletions',
    () async {
      final store = open();
      await store.refresh();
      await store.toggleWorkingOn(row(store));
      google.data['alice']!['one']!['hidden'] = true;
      await store.refresh(full: true);
      expect(store.workingOnIds, {'one'});
      google.data['alice']!['one']!['deleted'] = true;
      await store.refresh(full: true);
      expect(store.workingOnIds, isEmpty);
    },
  );
}
