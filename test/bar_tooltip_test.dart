import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/widgets/bar_tooltip.dart';
import 'package:remya_bar/features/popups/bar_popup.dart';
import 'package:remya_client/remya_client.dart';
import 'package:remya_ui/remya_ui.dart';

void main() {
  testWidgets('hover opens a Flutter popup and closes it on exit or disposal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(300, 40);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <MethodCall>[];
    const channel = MethodChannel('top.remya.bar/popup');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    const sharedTheme = RemyaTheme(styleVariant: .expressive);
    Widget app(String message) => BarPopupScope(
      theme: sharedTheme,
      child: MaterialApp(
        theme: sharedTheme.theme(.light),
        home: Align(
          alignment: .topRight,
          child: SizedBox(
            width: 40,
            height: 40,
            child: BarTooltip(message: message, child: const Text('settings')),
          ),
        ),
      ),
    );
    await tester.pumpWidget(app('Settings'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 20));
    await mouse.moveTo(const Offset(280, 20));
    await tester.pump(const Duration(milliseconds: 500));
    expect(calls.last.method, 'show');
    final request = calls.last.arguments as Map;
    expect(request['kind'], 'tooltip');
    expect(request['anchor'], [260, 0, 40, 40]);
    expect(request['data'], {'message': 'Settings', 'scale': 1.0});
    expect((request['size'] as List)[1] as int, greaterThan(16));
    expect(
      request['theme'],
      const ThemeConfig(styleVariant: 'expressive').toMap(),
    );
    expect(
      tester.getSemantics(find.byType(BarTooltip)).getSemanticsData().tooltip,
      'Settings',
    );
    expect(find.byType(Tooltip), findsNothing);
    await tester.pumpWidget(app('Unavailable'));
    await tester.pump();
    expect(
      ((calls.last.arguments as Map)['data'] as Map)['message'],
      'Unavailable',
    );
    await mouse.moveTo(const Offset(1, 20));
    await tester.pump();
    expect(calls.last.method, 'hide');
    await mouse.moveTo(const Offset(280, 20));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
    expect(calls.last.method, 'hide');
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });
}
