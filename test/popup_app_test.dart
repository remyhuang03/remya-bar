import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/settings/remya_settings_installed.dart';
import 'package:remya_bar/features/osd/osd_slider.dart';
import 'package:remya_bar/features/popups/popup_app.dart';
import 'package:remya_bar/features/popups/bar_card_surface.dart';
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

  testWidgets('calendar browses months, folds to a week and opens settings', (
    tester,
  ) async {
    final calls = await _popup(tester, const Size(500, 944));
    final now = DateTime.now();
    final next = DateTime(now.year, now.month + 1);
    const labels = DefaultMaterialLocalizations();
    final month = labels.formatMonthYear(now);
    final nextMonth = labels.formatMonthYear(next);
    await _content(tester, 'datetime', const {});
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text(month), findsOneWidget);
    expect(find.text('Today'), findsNothing);

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

    await tester.tap(find.byTooltip('Calendar settings'));
    await tester.pumpAndSettle();
    expect(calls.lastWhere((call) => call.method == 'action').arguments, {
      'action': 'calendar.settings',
    });
    await tester.tap(find.textContaining(RegExp(r'^UTC[+-]')));
    await tester.pumpAndSettle();
    expect(calls.lastWhere((call) => call.method == 'action').arguments, {
      'action': 'datetime.settings',
    });
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
