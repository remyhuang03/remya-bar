import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/tasks/tasks_block.dart';
import 'package:remya_bar/features/tasks/tasks_preferences.dart';
import 'package:remya_bar/features/tasks/tasks_store.dart';
import 'package:remya_client/remya_client.dart';

class _Tasks extends TasksStore {
  _Tasks({this.state = .ready, this.count = 12});

  final int count;

  @override
  final TasksSyncState state;

  @override
  GoogleAccountStatus get account => const GoogleAccountStatus(
    configured: true,
    pending: false,
    email: 'example@example.com',
    accountId: 'test-account',
    calendar: false,
    tasks: true,
    error: null,
  );

  @override
  String get defaultListId => 'work';

  @override
  List<TaskList> get lists => state == .loading
      ? []
      : const [
          TaskList(id: 'work', title: 'Work'),
          TaskList(id: 'home', title: 'Home'),
        ];

  @override
  List<GoogleTask> get tasks => state == .loading
      ? []
      : [
          for (var i = 1; i <= count; i++)
            GoogleTask(
              id: 'test-$i',
              listId: 'work',
              title: 'Task $i',
              position: i.toString().padLeft(3, '0'),
              scheduled: DateUtils.dateOnly(DateTime.now()),
            ),
        ];

  @override
  GoogleTask? findTask(String listId, String taskId) => tasks
      .where((task) => task.id == taskId && task.listId == listId)
      .firstOrNull;

  Map<String, Object?>? changes;
  Map<String, Object?>? draft;
  GoogleTask? originalDraft;

  @override
  Future<void> editTask(
    GoogleTask base,
    Map<String, Object?> changes, {
    bool clearDraft = false,
  }) async {
    this.changes = changes;
    if (clearDraft) draft = null;
  }

  @override
  void saveDraft(GoogleTask base, Map<String, Object?> changes) {
    draft = changes;
    originalDraft = base;
  }

  @override
  Map<String, Object?>? draftFor(GoogleTask base) => draft;

  @override
  GoogleTask? draftBaseFor(GoogleTask base) => originalDraft;
}

Future<void> _mount(
  WidgetTester tester,
  _Tasks store, {
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(store.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: .linear(textScale)),
        child: child!,
      ),
      home: Material(
        child: SingleChildScrollView(
          padding: const .all(24),
          child: TasksBlock(
            store: store,
            preferences: const TasksPreferences(),
            onSettings: () {},
            onSetDefaultList: (_) async {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('372px Tasks preview counts all rows; full view scrolls', (
    tester,
  ) async {
    await _mount(tester, _Tasks());
    expect(tester.getSize(find.byType(TasksBlock)).width, 372);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Task 3'), findsOneWidget);
    expect(find.text('Task 4'), findsNothing);

    await tester.tap(find.text('View all'));
    await tester.pumpAndSettle();
    final rows = find.byType(ListView).last;
    final scroller = find.descendant(
      of: rows,
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Task 12'),
      140,
      scrollable: scroller,
    );
    expect(find.text('Task 12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor resumes a draft and submits only edited fields', (
    tester,
  ) async {
    final store = _Tasks(count: 1);
    await _mount(tester, store);

    await tester.tap(find.text('Task 1'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Notes'),
      'Draft notes',
    );
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(store.draft, {'notes': 'Draft notes'});

    await tester.tap(find.text('Task 1'));
    await tester.pumpAndSettle();
    expect(find.text('Draft notes'), findsOneWidget);
    await tester.tap(find.text('Today').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tomorrow'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextField, 'Notes'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(store.changes, {
      'notes': 'Draft notes',
      'scheduled': DateUtils.addDaysToDate(DateTime.now(), 1),
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('the task list fits its host with enlarged text', (tester) async {
    await _mount(tester, _Tasks(), textScale: 2);
    expect(find.text('Today'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first-load skeleton fits the 372px host', (tester) async {
    await _mount(tester, _Tasks(state: .loading));
    expect(find.text('Getting your tasks'), findsOneWidget);
    expect(find.text('No tasks for today'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
