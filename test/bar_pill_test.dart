import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/battery/bar_battery.dart';
import 'package:remya_bar/features/clock/bar_clock.dart';
import 'package:remya_bar/features/popups/bar_popup.dart';
import 'package:remya_bar/features/popups/bar_card_surface.dart';
import 'package:remya_bar/widgets/bar_hover_card.dart';
import 'package:remya_bar/widgets/bar_pill.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

Widget _host(
  Widget child, {
  bool disableAnimations = false,
  RemyaTheme theme = const RemyaTheme(),
}) => BarPopupScope(
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
  setUp(() {
    BarPopup.openCard.value = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BarPopup.channel, (_) async => null);
  });
  tearDown(() {
    BarPopup.openCard.value = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BarPopup.channel, null);
  });

  testWidgets(
    'card state attaches only the matching pill with the card surface color',
    (tester) async {
      const seed = Color(0xFFCA3821);
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
        ),
      );
      final context = tester.element(find.byType(BarPill));
      final expected = BarCardSurface.colors(
        Theme.of(context),
        seed,
        RemyaTheme().styleVariant,
      );
      BarPopup.openCard.value = 'media';
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
      BarPopup.openCard.value = 'battery';
      await tester.pumpAndSettle();
      expect(tester.getSize(_surface()).height, 32);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is ColoredBox && widget.color == Colors.red,
        ),
        findsOneWidget,
      );
      BarPopup.openCard.value = null;
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('hover cards update only changed data while their kind is open', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      BarPopup.channel,
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
    BarPopup.openCard.value = 'battery';
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
    BarPopup.openCard.value = null;
    await tester.pumpWidget(card(3));
    await tester.pump();
    expect(calls.where((call) => call.method == 'update'), hasLength(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pill expands on hover, focus and press and returns to rest', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        BarPill(
          onTap: () => taps++,
          builder: (_, state) => Center(
            child: Text('Pill', style: TextStyle(color: state.foreground)),
          ),
        ),
      ),
    );
    final scheme = Theme.of(tester.element(find.byType(BarPill))).colorScheme;
    expect(tester.getSize(_surface()).height, 32);
    final mouse = await tester.createGesture(kind: .mouse);
    await mouse.addPointer(location: tester.getCenter(_surface()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getSize(_surface()).height, 40);
    await mouse.removePointer();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getSize(_surface()).height, 32);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getSize(_surface()).height, 40);
    final focused = tester.widget<AnimatedContainer>(_surface());
    expect(
      (focused.foregroundDecoration as BoxDecoration).border,
      Border.all(color: scheme.primary, width: 2),
    );
    final touch = await tester.startGesture(tester.getCenter(_surface()));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    final pressed =
        tester.widget<AnimatedContainer>(_surface()).decoration
            as BoxDecoration;
    expect(pressed.color, scheme.primaryContainer);
    expect(pressed.borderRadius, BorderRadius.circular(12));
    await touch.up();
    await tester.pump();
    expect(taps, 1);
  });

  for (final (name, child) in <(String, Widget)>[
    ('battery', const BarBattery(level: 80)),
    ('clock', const BarClock()),
  ]) {
    testWidgets('$name uses the shared hover motion', (tester) async {
      await tester.pumpWidget(_host(child));
      expect(tester.getSize(_surface()).height, 32);
      final mouse = await tester.createGesture(kind: .mouse);
      await mouse.addPointer(location: tester.getCenter(_surface()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getSize(_surface()).height, 40);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('card tap opens immediately through the pill', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      BarPopup.channel,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    await tester.pumpWidget(
      _host(
        BarPill(
          card: const BarPillCard(
            kind: 'datetime',
            size: Size(420, 673),
            data: {},
            openOnTap: true,
          ),
          builder: (_, _) => const Center(child: Text('Clock')),
        ),
      ),
    );
    await tester.tap(find.text('Clock'));
    await tester.pump();
    expect(calls.where((call) => call.method == 'show'), hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('attached and toggled styles work with reduced motion', (
    tester,
  ) async {
    Widget pill({bool attached = false, bool toggled = false}) => _host(
      BarPill(
        attached: attached,
        toggled: toggled,
        builder: (_, state) =>
            Text('Pill', style: TextStyle(color: state.foreground)),
      ),
      disableAnimations: true,
    );
    await tester.pumpWidget(pill(attached: true));
    final scheme = Theme.of(tester.element(find.byType(BarPill))).colorScheme;
    final attached = tester.widget<AnimatedContainer>(_surface());
    expect(attached.duration, Duration.zero);
    expect(tester.getSize(_surface()).height, 40);
    expect(
      (attached.decoration as BoxDecoration).color,
      scheme.surfaceContainer,
    );
    expect(
      (attached.decoration as BoxDecoration).borderRadius,
      const BorderRadius.vertical(top: Radius.circular(20)),
    );
    await tester.pumpWidget(pill(toggled: true));
    expect(tester.getSize(_surface()).height, 32);
    expect(
      (tester.widget<AnimatedContainer>(_surface()).decoration as BoxDecoration)
          .color,
      scheme.primary,
    );
    expect(
      tester.widget<Text>(find.text('Pill')).style!.color,
      scheme.onPrimary,
    );
  });
}
