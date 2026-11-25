import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/clock/calendar_agenda.dart';
import 'package:remya_bar/features/clock/calendar_clock_hero.dart';
import 'package:remya_bar/features/clock/calendar_grid.dart';
import 'package:remya_bar/features/clock/datetime_card.dart';
import 'package:remya_bar/features/settings/remya_settings_installed.dart';
import 'package:remya_bar/features/osd/osd_slider.dart';
import 'package:remya_bar/features/popups/popup_app.dart';
import 'package:remya_bar/features/popups/bar_card_surface.dart';
import 'package:remya_bar/features/tasks/tasks_block.dart';
import 'package:remya_client/remya_client.dart';
import 'package:remya_ui/remya_ui.dart';

const _channel = MethodChannel('top.remya.bar/popup');

Future<void> _content(
  WidgetTester tester,
  String kind,
  Map<String, Object?> data, {
  bool opening = false,
  bool settle = true,
}) async {
  final reply = await tester.binding.defaultBinaryMessenger
      .handlePlatformMessage(
        _channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('content', {
            'kind': kind,
            'opening': opening,
            'theme': const ThemeConfig().toMap(),
            'data': data,
          }),
        ),
        (ByteData? _) {},
      );
  expect(
    () => const StandardMethodCodec().decodeEnvelope(reply!),
    returnsNormally,
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<List<MethodCall>> _popup(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
    call,
  ) async {
    calls.add(call);
    return null;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      null,
    ),
  );
  await tester.pumpWidget(const BarPopupApp(channel: _channel));
  await tester.pump();
  return calls;
}

void main() {
  debugRemyaSettingsInstalled = true;
  testWidgets('OSD popup text has no fallback underline', (tester) async {
    await _popup(tester, osdSize);
    for (final (value, tag) in [
      (75, 'Software brightness'),
      (100, 'Dimming off'),
    ]) {
      await _content(tester, osdKind, {'type': 'gamma', 'value': value});
      for (final label in ['$value%', tag]) {
        final text = tester.widget<RichText>(
          find.descendant(
            of: find.text(label),
            matching: find.byType(RichText),
          ),
        );
        expect(text.text.style?.decoration, anyOf(isNull, TextDecoration.none));
      }
    }
  });

  testWidgets('panel growth resizes the window once, then fits it', (
    tester,
  ) async {
    final calls = await _popup(tester, const Size(420, 900));
    List<int> heights() => [
      for (final call in calls)
        if (call.method == 'resize') call.arguments['height'] as int,
    ];
    await _content(tester, 'notifications', {'dnd': false}, opening: true);
    final initial = heights();
    expect(initial, hasLength(1));

    await _content(tester, 'notifications', {
      'dnd': true,
      'quietReason': 'manual',
    }, settle: false);
    await tester.pump();
    expect(heights().skip(1), [16777216]);

    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    final fitted = heights().skip(1).toList();
    expect(fitted, hasLength(2));
    expect(fitted.last, greaterThan(initial.single));
  });

  testWidgets('notification popup clears hidden content and can reopen', (
    tester,
  ) async {
    await _popup(tester, const Size(420, 600));
    await _content(tester, 'notifications', {'dnd': false}, opening: true);
    expect(find.text('No notifications'), findsOneWidget);

    final reply = await tester.binding.defaultBinaryMessenger
        .handlePlatformMessage(
          _channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('closed'),
          ),
          (_) {},
        );
    const StandardMethodCodec().decodeEnvelope(reply!);
    await tester.pumpAndSettle();
    expect(find.text('No notifications'), findsNothing);

    await _content(tester, 'notifications', {'dnd': false}, opening: true);
    expect(find.text('No notifications'), findsOneWidget);
  });

  double progress(WidgetTester tester) => tester
      .widget<BarCardSurface>(find.byType(BarCardSurface))
      .emergence
      .value;
  const card = {
    'pill': [180, 140],
  };

  Future<void> dismiss(WidgetTester tester) async {
    final reply = await tester.binding.defaultBinaryMessenger
        .handlePlatformMessage(
          _channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('dismiss'),
          ),
          (_) {},
        );
    const StandardMethodCodec().decodeEnvelope(reply!);
    await tester.pump();
  }

  testWidgets(
    'card updates do not replay emergence or change measured height',
    (tester) async {
      final calls = await _popup(tester, const Size(500, 737));
      await _content(tester, 'battery', card, opening: true, settle: false);
      await tester.pump(const Duration(milliseconds: 80));
      final before = progress(tester);
      expect(before, inExclusiveRange(0, 1));
      final height = calls
          .lastWhere((call) => call.method == 'resize')
          .arguments['height'];
      await _content(tester, 'battery', card, settle: false);
      expect(progress(tester), closeTo(before, .001));
      await tester.pumpAndSettle();
      expect(progress(tester), 1);
      expect(
        calls.lastWhere((call) => call.method == 'resize').arguments['height'],
        height,
      );
      await _content(tester, 'battery', card);
      expect(progress(tester), 1);
    },
  );

  testWidgets('dismiss retracts then acknowledges hidden', (tester) async {
    final calls = await _popup(tester, const Size(500, 737));
    await _content(tester, 'battery', card, opening: true);
    await dismiss(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(progress(tester), inExclusiveRange(0, 1));
    expect(calls.where((call) => call.method == 'hidden'), isEmpty);
    await tester.pumpAndSettle();
    expect(progress(tester), 0);
    expect(calls.where((call) => call.method == 'hidden'), hasLength(1));
    await _content(tester, 'battery', card, settle: false);
    await tester.pump(const Duration(milliseconds: 60));
    expect(progress(tester), greaterThan(0));
    await tester.pumpAndSettle();
    expect(progress(tester), 1);
  });

  testWidgets('enter during dismiss resumes from the current shape', (
    tester,
  ) async {
    final calls = await _popup(tester, const Size(500, 737));
    await _content(tester, 'battery', card, opening: true);
    await dismiss(tester);
    await tester.pump(const Duration(milliseconds: 100));
    final before = progress(tester);
    expect(before, inExclusiveRange(0, 1));
    await _content(tester, 'battery', card, settle: false);
    expect(progress(tester), closeTo(before, .001));
    await tester.pump(const Duration(milliseconds: 60));
    expect(progress(tester), greaterThan(before));
    await tester.pumpAndSettle();
    expect(progress(tester), 1);
    expect(calls.where((call) => call.method == 'hidden'), isEmpty);
  });

  testWidgets(
    'narrow clock starts in week view and opens both settings pages',
    (tester) async {
      final calls = await _popup(tester, const Size(500, 784));
      final now = DateTime.now();
      final next = DateTime(now.year, now.month + 1);
      const labels = DefaultMaterialLocalizations();
      final month = labels.formatMonthYear(now);
      final nextMonth = labels.formatMonthYear(next);
      await _content(tester, 'datetime', const {});
      expect(find.text('Calendar'), findsOneWidget);
      expect(find.text('Tasks'), findsOneWidget);
      expect(tester.getSize(find.byType(DatetimeCard)), const Size(420, 720));
      expect(find.text(month), findsOneWidget);
      expect(find.text('Today'), findsNothing);
      expect(find.byTooltip('Next week'), findsOneWidget);
      expect(find.byType(Scrollable), findsOneWidget);

      await tester.tap(find.text(month));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text(nextMonth), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      await _content(tester, 'datetime', const {});
      expect(find.text(nextMonth), findsOneWidget);

      await tester.tap(find.text(nextMonth));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Next week'), findsOneWidget);
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(find.text(month), findsOneWidget);
      expect(find.text('Today'), findsNothing);

      await tester.tap(find.byTooltip('Calendar menu'));
      await tester.pumpAndSettle();
      final google = find.text('Open in Google Calendar');
      final refresh = find.text('Refresh');
      final settings = find.text('Settings');
      expect(
        tester.getTopLeft(google).dy,
        lessThan(tester.getTopLeft(refresh).dy),
      );
      expect(
        tester.getTopLeft(refresh).dy,
        lessThan(tester.getTopLeft(settings).dy),
      );
      await tester.tap(settings);
      await tester.pumpAndSettle();
      expect(calls.lastWhere((call) => call.method == 'action').arguments, {
        'action': 'calendar.settings',
      });
      await tester.tap(find.byTooltip('Tasks menu'));
      await tester.pumpAndSettle();
      expect(find.text('Open in Google Tasks'), findsOneWidget);
      await tester.tap(settings);
      await tester.pumpAndSettle();
      expect(calls.lastWhere((call) => call.method == 'action').arguments, {
        'action': 'tasks.settings',
      });
      await tester.tap(find.textContaining(RegExp(r'^UTC[+-]')));
      await tester.pumpAndSettle();
      expect(calls.lastWhere((call) => call.method == 'action').arguments, {
        'action': 'datetime.settings',
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('wide clock keeps the Tasks size when the month expands', (
    tester,
  ) async {
    final calls = await _popup(tester, const Size(848, 600));
    await _content(tester, 'datetime', const {});
    final card = find.byType(DatetimeCard);
    final hero = find.byType(CalendarClockHero);
    final grid = find.byType(CalendarGrid);
    final tasks = find.byType(TasksBlock);
    final agenda = find.byType(CalendarAgenda);
    expect(tester.getSize(card), const Size(816, 536));
    expect(tester.getSize(hero).width, 372);
    expect(tester.getSize(grid).width, 372);
    expect(tester.getTopLeft(grid).dx - tester.getTopLeft(hero).dx, 396);
    final gridSize = tester.getSize(grid);
    final tasksSize = tester.getSize(tasks);
    final agendaSize = tester.getSize(agenda);
    await tester.tap(
      find.text(
        const DefaultMaterialLocalizations().formatMonthYear(DateTime.now()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(card), const Size(816, 536));
    expect(tester.getSize(tasks), tasksSize);
    expect(tester.getSize(grid).height, gridSize.height + 180);
    expect(tester.getSize(agenda).height, agendaSize.height - 180);
    expect(calls.where((call) => call.method == 'resize'), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('narrow clock leaves its hero fixed at 200% text scale', (
    tester,
  ) async {
    await _popup(tester, const Size(500, 462));
    await _content(tester, 'datetime', const {'scale': 2});
    final card = find.byType(DatetimeCard);
    final hero = find.byType(CalendarClockHero);
    final tasks = find.byType(TasksBlock);
    final scroll = find.byType(CalendarAgenda);
    expect(tester.getSize(card), const Size(420, 398));
    final heroPosition = tester.getTopLeft(hero);
    final tasksPosition = tester.getTopLeft(tasks);
    await tester.drag(scroll, const Offset(0, -140));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(hero), heroPosition);
    expect(tester.getTopLeft(tasks).dy, lessThan(tasksPosition.dy));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('popup text and container use the owning Flutter theme', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(344, 160);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const channel = MethodChannel('top.remya.bar/popup');
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(const BarPopupApp(channel: _channel));
    await tester.pump();
    expect(calls, ['ready']);
    const message =
        'A longer settings message that wraps inside a Flutter popup.';
    for (final mode in ['light', 'dark']) {
      final reply = await tester.binding.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('content', {
                'kind': 'tooltip',
                'seed': 0x328074,
                'theme': ThemeConfig(
                  styleVariant: 'vibrant',
                  mode: mode,
                  contrast: .high,
                ).toMap(),
                'data': {'message': message, 'scale': 1.5},
              }),
            ),
            (ByteData? _) {},
          );
      expect(
        () => const StandardMethodCodec().decodeEnvelope(reply!),
        returnsNormally,
      );
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      final context = tester.element(find.text(message));
      final theme = RemyaTheme.fromConfig(
        ThemeConfig(
          styleVariant: 'vibrant',
          mode: mode,
          contrast: .high,
          seedColor: '#328074',
        ),
      );
      final expected = theme.theme(mode == 'dark' ? .dark : .light);
      final material = tester.widget<Material>(find.byType(Material).first);
      expect(material.color, expected.colorScheme.surfaceContainerHigh);
      expect(Theme.of(context).colorScheme, expected.colorScheme);
      expect(
        tester.widget<Text>(find.text(message)).style?.color,
        expected.colorScheme.onSurface,
      );
      expect(tester.takeException(), isNull);
    }
  });
}
