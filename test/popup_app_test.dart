import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/popups/popup_app.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

const _channel = MethodChannel('top.remya.bar/popup');

Future<void> _content(
  WidgetTester tester,
  String kind,
  Map<String, Object?> data,
) async {
  final reply = await tester.binding.defaultBinaryMessenger
      .handlePlatformMessage(
        _channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('content', {
            'kind': kind,
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
  await tester.pumpAndSettle();
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
  await tester.pumpWidget(const BarPopupApp());
  await tester.pump();
  return calls;
}

void main() {
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
    await tester.pumpWidget(const BarPopupApp());
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
