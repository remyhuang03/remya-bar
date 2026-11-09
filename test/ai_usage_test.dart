import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/ai_usage/ai_usage_backend.dart';
import 'package:remya_bar/features/ai_usage/ai_usage_data.dart';
import 'package:remya_bar/features/ai_usage/bar_ai_quota.dart';
import 'package:remya_bar/features/popups/bar_detail_card.dart';
import 'package:remya_bar/features/popups/bar_popup.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

const _codex = {'id': 'codex', 'name': 'Codex'};

Map<String, Object?> _usage(DateTime now, {num used = 86}) => {
  'source': 'oauth',
  'usage': {
    'updatedAt': now.toIso8601String(),
    'identity': {'loginMethod': 'Plus', 'accountEmail': 'fixture@example.test'},
    'primary': {
      'usedPercent': used,
      'windowMinutes': 300,
      'resetsAt': now.add(const Duration(minutes: 41)).toIso8601String(),
    },
    'secondary': {'usedPercent': 41, 'windowMinutes': 10080},
    'tertiary': {'usedPercent': 5, 'windowMinutes': 10080},
  },
  'rateWindowLabels': {'tertiary': 'Code review'},
  'pace': {
    'primary': {
      'expectedUsedPercent': 68,
      'willLastToReset': false,
      'etaSeconds': 1680,
    },
  },
  'status': {'indicator': 'minor', 'description': 'Partial outage'},
  'credits': {'remaining': 112.4},
};

void main() {
  final now = DateTime.utc(2026, 11, 9, 9);

  test(
    'projects quota fields and never substitutes missing or stale readings',
    () {
      final data = aiProviderData(_codex, _usage(now));
      final provider = AiQuotaProvider(data, now, 20);
      final tightest = provider.tightest!;
      expect(tightest.percent, '14%');
      expect(tightest.low, isTrue);
      expect(tightest.cadence, '5H');
      expect(tightest.resetLabel, 'Resets in 41m');
      expect(tightest.expectedLeft, 32);
      expect(tightest.paceLabel, 'Empty in ~28m');
      expect(provider.window('tertiary')?.name, 'Code review');
      expect(data['credits'], 112.4);
      expect(data['plan'], 'Plus');
      expect(data['incident'], 'Partial outage');
      expect(data.toString(), isNot(contains('fixture@example.test')));
      final stale = AiQuotaProvider(
        data,
        now.add(const Duration(minutes: 11)),
        20,
      );
      expect(stale.tightest, isNull);
      expect(stale.error, 'Usage data is out of date.');
      final invalid = AiQuotaProvider(
        aiProviderData(_codex, _usage(now, used: -1)),
        now,
        20,
      );
      expect(invalid.window('primary'), isNull);
      expect(invalid.tightest?.percent, '59%');
      final failed = AiQuotaProvider(
        aiProviderData(_codex, {
          'error': {'message': 'Sign in required'},
        }),
        now,
        20,
      );
      expect(failed.tightest, isNull);
      expect(failed.tooltip, contains('Sign in required'));
    },
  );

  test('alerts once per threshold and reset cycle across transient errors', () {
    final alerts = AiQuotaAlerts();
    List<(String, String, int)> sample(num used, {DateTime? cycle}) =>
        alerts.update([
          AiQuotaProvider(
            aiProviderData(_codex, _usage(cycle ?? now, used: used)),
            now,
            20,
          ),
        ]);

    expect(sample(70), isEmpty);
    expect(sample(80), [('Codex', 'Session', 20)]);
    expect(
      alerts.update([
        AiQuotaProvider(
          aiProviderData(_codex, {
            'error': {'message': 'Timed out'},
          }),
          now,
          20,
        ),
      ]),
      isEmpty,
    );
    expect(sample(75), isEmpty);
    expect(sample(85), isEmpty);
    expect(sample(100), [('Codex', 'Session', 0)]);
    final nextCycle = now.add(const Duration(minutes: 42));
    expect(sample(60, cycle: nextCycle), isEmpty);
    expect(sample(100, cycle: nextCycle), [
      ('Codex', 'Session', 20),
      ('Codex', 'Session', 0),
    ]);
  });

  testWidgets('pill hover shows quota details and click opens the card', (
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
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        BarPopup.channel,
        null,
      ),
    );
    final backend = _AiUsageBackend()
      ..data = {
        'providers': [aiProviderData(_codex, _usage(DateTime.now()))],
      };
    addTearDown(backend.dispose);
    await tester.pumpWidget(
      BarPopupScope(
        theme: const RemyaTheme(),
        child: MaterialApp(
          home: Center(
            child: SizedBox(height: 40, child: BarAiQuota(backend: backend)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pill = find.byType(BarAiQuota);
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: tester.getCenter(pill));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 550));
    expect(
      calls
          .where((call) => call.method == 'show')
          .map((call) => call.arguments['kind']),
      ['tooltip'],
    );
    await tester.tap(pill, buttons: kSecondaryMouseButton);
    expect(backend.refreshes, 1);
    await tester.tap(pill);
    expect(
      calls.lastWhere((call) => call.method == 'show').arguments['kind'],
      aiUsageKind,
    );
    await pointer.removePointer();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'detail card renders window, incident, failure and refresh actions',
    (tester) async {
      final actions = <Map<String, Object?>>[];
      final now = DateTime.now();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 500,
                child: BarDetailCard(
                  kind: aiUsageKind,
                  data: {
                    'providers': [
                      aiProviderData(_codex, _usage(now)),
                      aiProviderData(
                        {'id': 'claude', 'name': 'Claude'},
                        {
                          'error': {'message': 'Sign in required'},
                        },
                      ),
                    ],
                    'cost': [
                      {
                        'id': 'codex',
                        'total': 16.2,
                        'tokens': 1200000,
                        'daily': {now.toIso8601String().substring(0, 10): 3.42},
                      },
                    ],
                  },
                  onAction: actions.add,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('AI Usage'), findsOneWidget);
      expect(find.text('Partial outage'), findsOneWidget);
      expect(find.text('Empty in ~28m'), findsOneWidget);
      expect(find.text('Sign in required'), findsOneWidget);
      expect(
        find.text('Code review  weekly', findRichText: true),
        findsOneWidget,
      );
      expect(find.text(r'$3.42 today', findRichText: true), findsOneWidget);
      await tester.tap(find.byTooltip('Refresh'));
      await tester.tap(find.text('Retry'));
      expect(actions, [
        {'action': 'ai-usage.refresh'},
        {'action': 'ai-usage.refresh'},
      ]);
      expect(tester.takeException(), isNull);
    },
  );
}

class _AiUsageBackend extends AiUsageBackend {
  int refreshes = 0;

  @override
  Future<void> refresh() async => refreshes++;
}
