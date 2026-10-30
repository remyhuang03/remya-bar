import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/popups/popup_app.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

void main() {
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
