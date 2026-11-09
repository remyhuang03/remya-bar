import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/keyboard/keyboard_panel.dart';
import 'package:remya_bar/features/popups/bar_popup.dart';

void main() {
  testWidgets('hover paints its final color on the first frame', (
    tester,
  ) async {
    await tester.pumpWidget(_keyboard());
    final key = find.text('a');
    final colors = Theme.of(tester.element(key)).colorScheme;
    Color? background() {
      final box = tester
          .widgetList<DecoratedBox>(
            find.ancestor(of: key, matching: find.byType(DecoratedBox)),
          )
          .singleWhere((box) {
            final decoration = box.decoration;
            return decoration is BoxDecoration &&
                decoration.borderRadius == BorderRadius.circular(18);
          });
      return (box.decoration as BoxDecoration).color;
    }

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(key));
    await tester.pump();
    expect(
      background(),
      Color.alphaBlend(
        colors.onSurface.withValues(alpha: .08),
        colors.surfaceContainerHighest,
      ),
    );
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(background(), colors.surfaceContainerHighest);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('modifier latch, lock and Fn survive key repeat correctly', (
    tester,
  ) async {
    final strokes = <List<Object?>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      BarPopup.channel,
      (call) async {
        if (call.arguments['action'] == 'keyboard.press') {
          strokes.add(List<Object?>.from(call.arguments['value'] as List));
        }
        return null;
      },
    );
    await tester.pumpWidget(_keyboard());
    Future<void> tap(String label, {bool first = false}) async {
      final finder = find.text(label);
      await tester.tap(first ? finder.first : finder);
      await tester.pump();
    }

    await tap('Shift', first: true);
    await tap('A');
    await tap('a');
    await tap('Ctrl');
    await tap('Ctrl');
    await tap('a');
    await tap('a');
    await tap('Ctrl');
    await tap('Fn');
    final hold = await tester.startGesture(
      tester.getCenter(find.text('Delete')),
    );
    await tester.pump(const Duration(milliseconds: 435));
    await hold.up();
    await tester.pump();
    expect(strokes, [
      [30, 1, 0],
      [30, 0, 0],
      [30, 2, 0],
      [30, 2, 0],
      [111, 0, 0],
      [111, 0, 0],
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Widget _keyboard() {
  final labels = List.generate(
    4,
    (layer) => List<String>.filled(128, '')..[30] = layer.isOdd ? 'A' : 'a',
  );
  return MaterialApp(
    home: KeyboardPanel(
      channel: BarPopup.channel,
      data: {
        'device': {
          'config': {'group': 0, 'layout': 'us'},
        },
        'layout': {
          'layouts': ['English (US)'],
          'labels': labels,
        },
      },
    ),
  );
}
