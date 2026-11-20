import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/tasks/tasks_block.dart';
import 'package:remya_bar/features/tasks/tasks_preferences.dart';
import 'package:remya_bar/features/tasks/tasks_store.dart';
import 'package:remya_client/remya_client.dart';

class _Tasks extends TasksStore {
  _Tasks({this.state = .ready, this.count = 12, this.extra = const []});

  final int count;
  final List<GoogleTask> extra;

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
          ...extra,
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
  bool? fullRefresh;
  ({String listId, String title})? added;

  @override
  Future<void> refresh({bool full = false}) async => fullRefresh = full;

  @override
  Future<GoogleTask> addTask(
    String listId,
    String title, {
    String? parent,
    String? previous,
    DateTime? scheduled,
  }) async {
    added = (listId: listId, title: title);
    return GoogleTask(id: 'new', listId: listId, title: title);
  }

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
  VoidCallback? onSettings,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 663));
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
            onSettings: onSettings ?? () {},
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
    final listButtonFinder = find.widgetWithText(FilledButton, 'All lists');
    expect(tester.getSize(listButtonFinder).width, lessThan(280));
    final titleRect = tester.getRect(find.text('Tasks'));
    final listButtonRect = tester.getRect(listButtonFinder);
    expect(listButtonRect.left, greaterThan(titleRect.right));
    expect(listButtonRect.center.dy, closeTo(titleRect.center.dy, 2));

    expect(find.text('Task 3'), findsOneWidget);
    expect(find.text('Task 4'), findsNothing);
    final filters = find.byWidgetPredicate(
      (widget) => widget is SegmentedButton,
    );
    expect(tester.getSize(filters), const Size(372, 40));
    expect(find.text('Completed'), findsNothing);
    final viewAll = tester.getCenter(find.text('View all'));
    final add = tester.getCenter(find.byType(FloatingActionButton));
    expect(add.dx, greaterThan(viewAll.dx));
    expect(find.text('Manage lists'), findsNothing);
    final syncStatus = find.text('Waiting to sync');
    final theme = Theme.of(tester.element(syncStatus));
    expect(
      tester.widget<Text>(syncStatus).style,
      theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    await tester.tap(find.text('View all'));
    await tester.pumpAndSettle();
    final dialog = find.byType(Dialog);
    expect(tester.getSize(dialog), const Size(420, 663));
    final block = find.descendant(
      of: dialog,
      matching: find.byType(TasksBlock),
    );
    expect(tester.getSize(block).width, 372);
    expect(find.widgetWithText(TextField, 'Search tasks'), findsNothing);
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

  testWidgets('only the full Today view shows progress for matching parents', (
    tester,
  ) async {
    final today = DateUtils.dateOnly(DateTime.now());
    await _mount(
      tester,
      _Tasks(
        count: 3,
        extra: [
          GoogleTask(
            id: 'done',
            listId: 'work',
            title: 'Done today',
            scheduled: today,
            completed: true,
          ),
          GoogleTask(
            id: 'child',
            listId: 'work',
            title: 'Done subtask',
            parent: 'test-1',
            scheduled: today,
            completed: true,
          ),
          GoogleTask(
            id: 'tomorrow',
            listId: 'work',
            title: 'Tomorrow',
            scheduled: DateUtils.addDaysToDate(today, 1),
          ),
        ],
      ),
      textScale: 2,
    );

    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.ensureVisible(find.text('View all'));
    await tester.tap(find.text('View all'));
    await tester.pumpAndSettle();

    expect(find.text('left for today'), findsOneWidget);
    expect(find.text('1 of 4 done'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Upcoming').last);
    await tester.tap(find.text('Upcoming').last);
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  for (final total in [0, 1]) {
    testWidgets('Today progress visibility with $total completed tasks', (
      tester,
    ) async {
      await _mount(
        tester,
        _Tasks(
          count: 0,
          extra: [
            if (total > 0)
              GoogleTask(
                id: 'done',
                listId: 'work',
                title: 'Done today',
                scheduled: DateUtils.dateOnly(DateTime.now()),
                completed: true,
              ),
          ],
        ),
      );
      await tester.tap(find.text('View all'));
      await tester.pumpAndSettle();

      final indicator = find.byType(LinearProgressIndicator);
      if (total == 0) {
        expect(find.text('left for today'), findsNothing);
        expect(find.text('0 of 0 done'), findsNothing);
        expect(find.text('No tasks for today'), findsWidgets);
        expect(indicator, findsNothing);
      } else {
        expect(find.text('left for today'), findsOneWidget);
        expect(find.text('1 of 1 done'), findsOneWidget);
        expect(tester.widget<LinearProgressIndicator>(indicator).value, 1);
        expect(find.text('100%'), findsOneWidget);
      }
    });
  }

  testWidgets('N opens Add task from a task control and leaves search alone', (
    tester,
  ) async {
    await _mount(tester, _Tasks(count: 1));
    await tester.ensureVisible(find.text('View all'));
    await tester.tap(find.text('View all'));
    await tester.pumpAndSettle();

    final quick = find.widgetWithText(TextField, 'Add a task to Work');
    final search = find.widgetWithText(TextField, 'Search tasks');
    expect(quick, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNWidgets(2));
    expect(tester.testTextInput.isVisible, isTrue);
    expect(quick, findsOneWidget);
    await tester.tap(find.byTooltip('Close').last);
    await tester.pumpAndSettle();

    expect(search, findsNothing);
    await tester.tap(find.byTooltip('Search tasks'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(search).focusNode?.hasFocus, isTrue);
    await tester.ensureVisible(search);
    await tester.tap(search);
    await tester.enterText(search, 'notes');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    expect(quick, findsNothing);
    expect(find.text('notes'), findsOneWidget);
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

  testWidgets('list selector menu and direct header actions', (tester) async {
    var settingsOpened = false;
    final store = _Tasks(
      count: 1,
      extra: [
        GoogleTask(
          id: 'home-1',
          listId: 'home',
          title: 'Home task',
          scheduled: DateUtils.dateOnly(DateTime.now()),
        ),
      ],
    );
    await _mount(tester, store, onSettings: () => settingsOpened = true);

    await tester.tap(find.widgetWithText(FilledButton, 'All lists'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(MenuItemButton), findsNWidgets(4));
    final manage = find.widgetWithText(MenuItemButton, 'Manage lists');
    expect(tester.widget<MenuItemButton>(manage).leadingIcon, isNotNull);
    await tester.tap(find.widgetWithText(MenuItemButton, 'Home'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Home'), findsOneWidget);
    expect(find.text('Home task'), findsOneWidget);
    expect(find.text('Task 1'), findsNothing);

    final sync = find.byTooltip('Sync now');
    final settings = find.byTooltip('Task settings');
    expect(tester.getCenter(sync).dx, lessThan(tester.getCenter(settings).dx));
    await tester.tap(sync);
    await tester.pumpAndSettle();
    expect(store.fullRefresh, isTrue);
    await tester.tap(settings);
    await tester.pumpAndSettle();
    expect(settingsOpened, isTrue);
    expect(find.byType(MenuItemButton), findsNothing);

    await tester.tap(find.byTooltip('Task menu for Home task'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(MenuItemButton, 'Open in Google Tasks'),
      findsOneWidget,
    );
  });

  testWidgets('Completed toggles the rows below it without a count', (
    tester,
  ) async {
    await _mount(
      tester,
      _Tasks(
        count: 1,
        extra: [
          GoogleTask(
            id: 'done',
            listId: 'work',
            title: 'Done today',
            scheduled: DateUtils.dateOnly(DateTime.now()),
            completed: true,
          ),
        ],
      ),
    );
    final completed = find.text('Completed');
    final row = find.text('Done today');
    expect(find.textContaining('Completed ·'), findsNothing);
    expect(row, findsNothing);

    await tester.tap(completed);
    await tester.pumpAndSettle();
    final button = tester.getRect(find.widgetWithText(TextButton, 'Completed'));
    expect(
      button.top - tester.getBottomLeft(find.text('Task 1')).dy,
      greaterThanOrEqualTo(12),
    );
    expect(tester.getTopLeft(row).dy - button.bottom, greaterThanOrEqualTo(12));

    await tester.tap(completed);
    await tester.pumpAndSettle();
    expect(row, findsNothing);
  });

  testWidgets('Completed stays hidden until archived tasks are shown', (
    tester,
  ) async {
    await _mount(
      tester,
      _Tasks(
        count: 0,
        extra: [
          GoogleTask(
            id: 'archived',
            listId: 'work',
            title: 'Archived today',
            scheduled: DateUtils.dateOnly(DateTime.now()),
            completed: true,
            hidden: true,
          ),
        ],
      ),
    );
    expect(find.text('No tasks for today'), findsOneWidget);
    expect(find.text('Completed'), findsNothing);

    await tester.tap(find.text('View all'));
    await tester.pumpAndSettle();
    expect(find.text('Completed'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'All lists').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(MenuItemButton, 'Show archived tasks'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Archived today'), findsOneWidget);
  });

  testWidgets('Add task FAB saves to the default list', (tester) async {
    final store = _Tasks(count: 1);
    await _mount(tester, store);
    final fab = find.byType(FloatingActionButton);
    expect(tester.widget<FloatingActionButton>(fab).child, isA<Icon>());
    expect(find.text('Add task'), findsNothing);
    await tester.tap(fab);
    await tester.pumpAndSettle();
    final title = find.widgetWithText(TextField, 'Add a task to Work');
    expect(title, findsOneWidget);
    await tester.enterText(title, '  New task  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(store.added, (listId: 'work', title: 'New task'));
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Task added'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
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
