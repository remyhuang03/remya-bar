import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/tasks/tasks_block.dart';
import 'package:remya_bar/features/tasks/tasks_preferences.dart';
import 'package:remya_bar/features/tasks/tasks_store.dart';
import 'package:remya_client/remya_client.dart';

final _today = DateTime(2026, 11, 23);

GoogleTask _task(
  String title, {
  int? days = 0,
  String list = 'work',
  bool completed = false,
  bool assigned = false,
  bool undoable = false,
}) => GoogleTask(
  id: title,
  listId: list,
  title: title,
  scheduled: days == null
      ? null
      : DateTime(_today.year, _today.month, _today.day + days),
  completed: completed,
  assigned: assigned,
  completionUndoable: undoable,
  webViewLink: 'https://calendar.google.com/calendar/r/tasks',
  sourceLink: assigned ? 'https://docs.google.com/document/d/example' : null,
);

class _Tasks extends TasksStore {
  _Tasks(this.tasks, {this.state = .ready, this.pendingCount = 0});

  @override
  final List<GoogleTask> tasks;

  @override
  final TasksSyncState state;

  @override
  final int pendingCount;

  @override
  GoogleAccountStatus get account => const GoogleAccountStatus(
    configured: true,
    pending: false,
    email: 'test@example.com',
    accountId: 'subject',
    calendar: true,
    tasks: true,
    error: null,
  );

  @override
  final workingOnIds = <String>{};

  final openCards = <Object>{};
  (String, bool)? completion;
  var refreshes = 0;
  var undid = false;

  @override
  GoogleTask? get undoTask =>
      undid ? null : tasks.where((task) => task.completionUndoable).firstOrNull;

  @override
  void setCardOpen(Object owner, bool open) {
    if (open) {
      openCards.add(owner);
    } else {
      openCards.remove(owner);
    }
  }

  @override
  Future<void> toggleWorkingOn(GoogleTask task) async {
    if (!workingOnIds.remove(task.id)) workingOnIds.add(task.id);
    notifyListeners();
  }

  @override
  Future<void> setCompleted(GoogleTask task, bool completed) async {
    completion = (task.title, completed);
  }

  @override
  Future<void> undoCompletion() async {
    undid = true;
    notifyListeners();
  }

  @override
  Future<void> retry() async {
    refreshes++;
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Tasks store, {
  TasksPreferences preferences = const TasksPreferences(),
  bool scrollable = true,
  double textScale = 1,
  VoidCallback? onSettings,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 560));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(store.dispose);
  final block = TasksBlock(
    store: store,
    preferences: preferences,
    onSettings: onSettings ?? () {},
    now: _today,
    scrollable: scrollable,
  );
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: .linear(textScale)),
        child: child!,
      ),
      home: Material(
        child: Padding(
          padding: const .all(24),
          child: scrollable ? block : SingleChildScrollView(child: block),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _row(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(InkWell)).first;

void main() {
  testWidgets('initial shortcuts work before a header button takes focus', (
    tester,
  ) async {
    final store = _Tasks([]);
    await _mount(tester, store);
    FocusNode headerFocus(String tooltip) => tester
        .widget<IconButton>(
          find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == tooltip,
          ),
        )
        .focusNode!;
    final add = headerFocus('New task');
    final menu = headerFocus('Tasks menu');

    expect(add.hasFocus, isFalse);
    expect(menu.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    expect(store.refreshes, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(add.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(menu.hasPrimaryFocus, isTrue);
  });

  testWidgets('groups only visible dated tasks and moves a bookmarked row', (
    tester,
  ) async {
    final store = _Tasks([
      _task('Focus now'),
      _task('Due today'),
      _task('Due Tuesday', days: 1),
      _task('Due Friday', days: 4),
      _task('Too far', days: 8),
      _task('Without due date', days: null),
      _task('Overdue', days: -1),
      _task('Already done', completed: true),
      _task('Hidden list', list: 'home'),
    ])..workingOnIds.add('Focus now');
    await _mount(
      tester,
      store,
      preferences: const TasksPreferences(
        visibleLists: ['work'],
        visibleListsAccount: 'subject',
      ),
    );

    expect(store.openCards, hasLength(1));
    expect(tester.getSize(find.byType(TasksBlock)).width, 372);
    expect(find.text('Focus now'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Focus now')).dy,
      lessThan(tester.getTopLeft(find.text('Today')).dy),
    );
    expect(find.text('Tue'), findsOneWidget);
    expect(find.text('Fri 27'), findsOneWidget);
    for (final title in [
      'Too far',
      'Without due date',
      'Overdue',
      'Already done',
      'Hidden list',
      'Last synced',
    ]) {
      expect(find.text(title), findsNothing);
    }

    final focus = tester.widget<InkWell>(_row('Due today')).focusNode!;
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pumpAndSettle();
    expect(find.text('Due today'), findsOneWidget);
    expect(find.text('Today'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Due today')).dy,
      lessThan(tester.getTopLeft(find.text('Upcoming')).dy),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    expect(store.openCards, isEmpty);
  });

  testWidgets('centers No tasks when no incomplete dated tasks match', (
    tester,
  ) async {
    await _mount(tester, _Tasks([_task('No date', days: null)]));
    final empty = find.text('No tasks');

    expect(empty, findsOneWidget);
    expect(find.text('Working on'), findsNothing);
    expect(find.text('Today'), findsNothing);
    expect(find.text('Upcoming'), findsNothing);
    expect(
      tester.getCenter(empty),
      tester.getCenter(
        find.ancestor(of: empty, matching: find.byType(Center)).first,
      ),
    );
  });

  testWidgets('scrolls the list beneath a fixed title and header menu', (
    tester,
  ) async {
    var settingsOpened = false;
    await _mount(
      tester,
      _Tasks([for (var i = 1; i <= 30; i++) _task('Task $i')]),
      onSettings: () => settingsOpened = true,
    );
    final title = tester.getTopLeft(find.text('Tasks'));
    await tester.scrollUntilVisible(find.text('Task 30'), 120);
    expect(tester.getTopLeft(find.text('Tasks')), title);
    expect(find.text('Task 30'), findsOneWidget);

    await tester.tap(find.byTooltip('Tasks menu'));
    await tester.pumpAndSettle();
    final open = tester.getTopLeft(find.text('Open in Google Tasks')).dy;
    final refresh = tester.getTopLeft(find.text('Refresh')).dy;
    final settings = tester.getTopLeft(find.text('Settings')).dy;
    expect(open, lessThan(refresh));
    expect(refresh, lessThan(settings));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(settingsOpened, isTrue);
  });

  testWidgets('assigned row stays read-only and exposes its source menu', (
    tester,
  ) async {
    final store = _Tasks([
      _task('Assigned task', assigned: true),
      _task('Regular task'),
    ]);
    await _mount(tester, store, textScale: 2, scrollable: false);

    final assigned = tester.widget<Checkbox>(
      find.descendant(
        of: _row('Assigned task'),
        matching: find.byType(Checkbox),
      ),
    );
    expect(assigned.onChanged, isNull);

    final click = await tester.startGesture(
      tester.getCenter(find.text('Assigned task')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await click.up();
    await tester.pumpAndSettle();
    final open = tester.getTopLeft(find.text('Open in Google Tasks')).dy;
    final source = tester.getTopLeft(find.text('Open source')).dy;
    expect(open, lessThan(source));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    final focus = tester.widget<InkWell>(_row('Regular task')).focusNode!;
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    expect(store.completion, ('Regular task', true));
    expect(store.refreshes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline banner and undo expose their independent actions', (
    tester,
  ) async {
    final store = _Tasks(
      [_task('Just completed', completed: true, undoable: true)],
      state: .offline,
      pendingCount: 1,
    );
    await _mount(tester, store);
    expect(find.text('Offline · 1 change waiting to sync'), findsOneWidget);
    expect(find.text('Task completed'), findsOneWidget);
    expect(find.text('Just completed'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(store.refreshes, 1);
    expect(store.undid, isTrue);
    expect(find.text('Task completed'), findsNothing);
  });
}
