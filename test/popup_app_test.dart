import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/popups/popup_app.dart';
import 'package:remya_bar/features/popups/bar_card_surface.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

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

  testWidgets('datetime uses the snapshot offset and keeps the browsed month', (
    tester,
  ) async {
    final calls = await _popup(tester, const Size(500, 737));
    final utc = DateTime.utc(2021, 1, 1, 4, 30, 8);
    Map<String, Object?> data(DateTime time) => {
      'unixMillis': time.millisecondsSinceEpoch,
      'utcOffsetSeconds': -5 * Duration.secondsPerHour,
    };

    await _content(tester, 'datetime', data(utc));
    expect(find.text('December 2020'), findsOneWidget);
    expect(find.text('Thursday'), findsOneWidget);
    expect(find.text('December 31, 2020'), findsOneWidget);
    expect(find.text('UTC-05:00'), findsOneWidget);
    expect(find.text('53'), findsOneWidget);
    expect(find.text('366'), findsOneWidget);
    expect(find.text('04:30'), findsOneWidget);
    expect(find.text('23:30 :08', findRichText: true), findsOneWidget);

    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('January 2021'), findsOneWidget);
    await _content(
      tester,
      'datetime',
      data(utc.add(const Duration(seconds: 1))),
    );
    expect(find.text('January 2021'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('December 2020'), findsOneWidget);

    await tester.tap(find.byTooltip('Date and time settings'));
    await tester.pumpAndSettle();
    expect(calls.lastWhere((call) => call.method == 'action').arguments, {
      'action': 'datetime.settings',
    });
    expect(tester.takeException(), isNull);
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
                'theme': ThemeConfig(
                  styleVariant: 'vibrant',
                  mode: mode,
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
        ThemeConfig(styleVariant: 'vibrant', mode: mode),
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
