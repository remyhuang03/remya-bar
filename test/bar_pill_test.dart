import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/clock/bar_clock.dart';
import 'package:remya_bar/features/popups/bar_popup.dart';
import 'package:remya_bar/features/popups/bar_card_surface.dart';
import 'package:remya_bar/widgets/bar_hover_card.dart';
import 'package:remya_bar/widgets/bar_pill.dart';
import 'package:remya_bar/widgets/bar_tooltip.dart';
import 'package:remya_ui/remya_ui.dart';

late BarPopup _popup;

Widget _host(
  Widget child, {
  bool disableAnimations = false,
  RemyaTheme theme = const RemyaTheme(),
}) => BarPopupScope(
  popup: _popup,
  theme: theme,
  child: MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Center(child: SizedBox(width: 204, height: 40, child: child)),
    ),
  ),
);

Finder _surface() => find
    .descendant(
      of: find.byType(BarPill),
      matching: find.byType(AnimatedContainer),
    )
    .first;

void main() {
  setUp(() => _popup = BarPopup.forView(1));
  tearDown(() => _popup.dispose());
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_popup.channel, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_popup.channel, null);
  });

  testWidgets('clock adds the surface insets once to its body size', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _popup.channel,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    await tester.pumpWidget(_host(const BarClock()));
    await tester.tap(find.byType(BarClock));
    await tester.pump();

    final request = calls.where((call) => call.method == 'show').single;
    expect(request.arguments, containsPair('kind', 'datetime'));
    expect(request.arguments, containsPair('size', [896, 784]));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('weather opens only on activation and toggles on another click', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _popup.channel,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    await tester.pumpWidget(
      _host(
        BarTooltip(
          message: 'Taipei · Cloudy',
          showOnFocus: true,
          suppressWhenCardOpen: 'weather',
          child: BarPill(
            card: const BarPillCard(
              kind: 'weather',
              size: Size(420, 588),
              hoverOpens: false,
              openOnTap: true,
            ),
            builder: (_, _) => const Text('12°'),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.text('12°')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      calls.where((call) => call.method == 'show').single.arguments,
      containsPair('kind', 'tooltip'),
    );
    await mouse.moveTo(const Offset(0, 0));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(calls.last.arguments, containsPair('kind', 'tooltip'));
    expect(calls.last.method, 'show');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(calls.last.arguments, containsPair('kind', 'weather'));
    expect(calls.last.method, 'show');
    _popup.openCard.value = 'weather';
    await tester.pump(const Duration(milliseconds: 500));
    expect(calls.last.arguments, containsPair('kind', 'tooltip'));
    expect(calls.last.method, 'hide');
    final beforeClose = calls.length;
    await tester.tap(find.text('12°'));
    await tester.pump();
    expect(
      calls
          .skip(beforeClose)
          .where((call) => call.method == 'hide')
          .single
          .arguments,
      containsPair('kind', 'weather'),
    );
    _popup.openCard.value = null;
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'card state attaches only the matching pill with the card surface color',
    (tester) async {
      const seed = Color(0xFFCA3821);
      const theme = RemyaTheme(contrast: .high);
      await tester.pumpWidget(
        _host(
          BarPill(
            card: const BarPillCard(
              kind: 'media',
              size: Size(420, 505),
              data: {},
              seedColor: seed,
            ),
            background: const ColoredBox(color: Colors.red),
            builder: (_, _) => const Text('Media'),
          ),
          theme: theme,
        ),
      );
      final context = tester.element(find.byType(BarPill));
      final expected = BarCardSurface.colors(
        Theme.of(context),
        seed,
        theme.styleVariant,
        contrastLevel: theme.contrast.level,
      );
      _popup.openCard.value = 'media';
      await tester.pumpAndSettle();
      final surface = tester.widget<AnimatedContainer>(_surface());
      expect(tester.getSize(_surface()).height, 40);
      expect(
        (surface.decoration as BoxDecoration).color,
        expected.surfaceContainer,
      );
      expect(
        (surface.decoration as BoxDecoration).borderRadius,
        const BorderRadius.vertical(top: Radius.circular(20)),
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is ColoredBox && widget.color == Colors.red,
        ),
        findsNothing,
      );
      _popup.openCard.value = 'battery';
      await tester.pumpAndSettle();
      expect(tester.getSize(_surface()).height, 32);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is ColoredBox && widget.color == Colors.red,
        ),
        findsOneWidget,
      );
      _popup.openCard.value = null;
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('hover cards update only changed data while their kind is open', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _popup.channel,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    Widget card(int value, {RemyaTheme theme = const RemyaTheme()}) => _host(
      Material(
        child: BarHoverCard(
          kind: 'battery',
          size: const Size(420, 300),
          openOnTap: true,
          data: {
            'nested': [value],
          },
          child: const Text('Battery'),
        ),
      ),
      theme: theme,
    );
    await tester.pumpWidget(card(1));
    await tester.tap(find.text('Battery'));
    await tester.pump();
    expect(calls.where((call) => call.method == 'show'), hasLength(1));
    await tester.pumpWidget(card(2));
    await tester.pump();
    expect(calls.where((call) => call.method == 'update'), isEmpty);
    _popup.openCard.value = 'battery';
    await tester.pumpWidget(card(2));
    await tester.pump();
    expect(calls.where((call) => call.method == 'update'), hasLength(1));
    await tester.pumpWidget(card(2));
    await tester.pump();
    expect(calls.where((call) => call.method == 'update'), hasLength(1));
    await tester.pumpWidget(
      card(2, theme: const RemyaTheme(styleVariant: .vibrant)),
    );
    await tester.pump();
    expect(calls.where((call) => call.method == 'update'), hasLength(2));
    _popup.openCard.value = null;
    await tester.pumpWidget(card(3));
    await tester.pump();
    expect(calls.where((call) => call.method == 'update'), hasLength(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'hover card follows its anchor while scrolling, also after a card switch',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _popup.channel,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        BarPopupScope(
          popup: _popup,
          theme: const RemyaTheme(),
          child: MaterialApp(
            home: Center(
              child: SizedBox(
                width: 300,
                height: 40,
                child: SingleChildScrollView(
                  controller: controller,
                  scrollDirection: .horizontal,
                  child: SizedBox(
                    width: 600,
                    height: 40,
                    child: Material(
                      type: .transparency,
                      child: Row(
                        children: [
                          const SizedBox(width: 100),
                          BarHoverCard(
                            kind: 'battery',
                            size: const Size(420, 300),
                            openOnTap: true,
                            data: const {'ok': true},
                            child: const SizedBox(
                              width: 80,
                              height: 32,
                              child: Text('Battery'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Battery'));
      await tester.pump();
      // Switching from another card reports it closed before this one opens.
      _popup.openCard.value = 'resources';
      _popup.openCard.value = null;
      _popup.openCard.value = 'battery';
      await tester.pump();
      controller.jumpTo(40);
      await tester.pump();
      final shows = calls.where((call) => call.method == 'show').toList();
      final showAnchor = (shows.single.arguments as Map)['anchor'] as List;
      final updates = calls.where((call) => call.method == 'update').toList();
      expect(updates, hasLength(1));
      final args = updates.single.arguments as Map;
      final anchor = args['anchor'] as List;
      expect(anchor[0], showAnchor[0] - 40);
      controller.jumpTo(120);
      await tester.pump();
      final clipped = (calls.last.arguments as Map)['anchor'] as List;
      expect(clipped[0], showAnchor[0] - 100);
      expect(clipped[2], 60);
      controller.jumpTo(180);
      await tester.pump();
      expect(calls.last.method, 'hide');
      _popup.openCard.value = null;
      await tester.pumpWidget(const SizedBox());
    },
  );
}
