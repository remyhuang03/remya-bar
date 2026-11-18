import 'dart:async';
import 'dart:io';
import 'dart:ui' show FlutterView, Scene, SemanticsUpdate;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/app.dart';
import 'package:remya_bar/bar_view_host.dart';
import 'package:remya_bar/features/popups/bar_popup.dart';
import 'package:remya_bar/features/settings/bar_settings_entry.dart';
import 'package:remya_ui/remya_ui.dart';

class _ExplicitView extends TestFlutterView {
  _ExplicitView(TestFlutterView base, this.viewId)
    : super(
        view: base,
        display: base.display,
        platformDispatcher: base.platformDispatcher,
      );

  @override
  final int viewId;

  @override
  void render(Scene scene, {Size? size}) {}

  @override
  void updateSemantics(SemanticsUpdate update) => update.dispose();
}

class _Dispatcher extends TestPlatformDispatcher {
  _Dispatcher(TestPlatformDispatcher base) : super(platformDispatcher: base);

  final explicitViews = <TestFlutterView>[];

  @override
  Iterable<TestFlutterView> get views => [...super.views, ...explicitViews];

  @override
  FlutterView? view({required int id}) =>
      explicitViews.where((view) => view.viewId == id).firstOrNull ??
      super.view(id: id);
}

class _Binding extends AutomatedTestWidgetsFlutterBinding {
  late final _Dispatcher _dispatcher = _Dispatcher(super.platformDispatcher);

  @override
  _Dispatcher get platformDispatcher => _dispatcher;

  void changeMetrics() => handleMetricsChanged();
}

void main() {
  final binding = _Binding();
  const codec = StandardMethodCodec();

  testWidgets('matches native and Flutter views in either arrival order', (
    tester,
  ) async {
    final preferences = SettingsThemeController(
      () => File('/nonexistent/theme.toml'),
    );
    final popups = {10: BarPopup.forView(10), 11: BarPopup.forView(11)};
    addTearDown(() {
      binding.platformDispatcher.explicitViews.clear();
      for (final popup in popups.values) {
        popup.dispose();
      }
      preferences.dispose();
    });
    final messenger = tester.binding.defaultBinaryMessenger;
    final initialList = Completer<Object?>();
    messenger.setMockMethodCallHandler(barViewsChannel, (call) {
      expect(call.method, 'list');
      return initialList.future;
    });
    messenger.setMockMethodCallHandler(barSettingsChannel, (call) async {
      expect(call.method, 'ready');
      return null;
    });
    Map<String, Object> snapshot(int revision, Map<String, String> views) => {
      'revision': revision,
      'views': views,
    };
    Future<void> send(MethodChannel channel, MethodCall call) async {
      final reply = await messenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(call),
        (_) {},
      );
      codec.decodeEnvelope(reply!);
    }

    Future<void> change(int revision, Map<String, String> views) =>
        send(barViewsChannel, MethodCall('changed', snapshot(revision, views)));
    Finder view(int id) => find.byKey(ValueKey(id));

    binding.platformDispatcher.explicitViews.add(
      _ExplicitView(tester.view, 10),
    );
    await tester.pumpWidget(
      wrapWithView: false,
      BarViewHost(
        preferences: preferences,
        buildBar: (id) =>
            RemyaBarApp(preferences: preferences, popup: popups[id]!),
      ),
    );
    expect(find.byType(View), findsNothing);

    await change(2, {'10': 'bar', '11': 'bar', '${tester.view.viewId}': 'bar'});
    await tester.pump();
    expect(view(10), findsOneWidget);
    expect(view(11), findsNothing);
    expect(view(tester.view.viewId), findsNothing);

    initialList.complete(snapshot(1, {'10': 'popup'}));
    await tester.pump();
    expect(find.byType(RemyaBarApp), findsOneWidget);

    binding.platformDispatcher.explicitViews.add(
      _ExplicitView(tester.view, 11),
    );
    binding.changeMetrics();
    await tester.pump();
    expect(view(11), findsOneWidget);
    const action = MethodCall('action', {
      'action': 'card.state',
      'kind': 'resources',
      'open': true,
    });
    await send(popups[10]!.channel, action);
    expect(popups[10]!.openCard.value, 'resources');
    expect(popups[11]!.openCard.value, isNull);

    await change(3, {'11': 'bar'});
    await tester.pump();
    expect(view(10), findsNothing);
    await send(popups[11]!.channel, action);
    expect(popups[11]!.openCard.value, 'resources');
    expect(view(11), findsOneWidget);

    await tester.pumpWidget(
      const ViewCollection(views: []),
      wrapWithView: false,
    );
  });
}
