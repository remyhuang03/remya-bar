import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_bar/features/ai_usage/ai_quota_ring.dart';
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
  'resetCredits': {'available': 2},
};

Future<void> _pumpRings(WidgetTester tester, List<AiQuotaProvider> providers) =>
    tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            for (final (index, provider) in providers.indexed)
              AiQuotaRing(provider, showUsed: false, index: index),
          ],
        ),
      ),
    );

void main() {
  final now = DateTime.utc(2026, 11, 9, 9);

  setUpAll(loadAiIdentity);

  test('derives a linear pace when CodexBar omits it', () {
    final row = {..._usage(now)}..remove('pace');
    final window = AiQuotaProvider(
      aiProviderData(_codex, row),
      now,
      20,
    ).window('primary')!;
    // 41 of 300 minutes remain, so a linear pace leaves about 13.7%.
    expect(window.expectedLeft, closeTo(41 / 300 * 100, .01));
    // CodexBar's own pace wins when present.
    expect(
      AiQuotaProvider(
        aiProviderData(_codex, _usage(now)),
        now,
        20,
      ).window('primary')!.expectedLeft,
      32,
    );
  });

  test('reads the Settings threshold', () {
    final ai = {
      'bar': {'pinned': [], 'lowPercent': 35},
    };
    expect(aiLowPercent(ai['bar']), 35);
    expect(aiLowPercent({'lowPercent': 400}), 100);
    expect(aiLowPercent(null), 20);
    final data = {
      'threshold': aiLowPercent(ai['bar']),
      'providers': [aiProviderData(_codex, _usage(now, used: 70))],
    };
    expect(aiVisibleProviders(data, now).single.tightest!.low, isTrue);
    expect(
      aiVisibleProviders({
        ...data,
        'threshold': 20.0,
      }, now).single.tightest!.low,
      isFalse,
    );
  });

  test('pill follows the pinned order and caps at three providers', () {
    List<Object?> pill(List<String> pinned) => aiPillProviders({
      'pinned': pinned,
      'providers': [
        for (final id in ['a', 'b', 'c', 'd'])
          aiProviderData({'id': id, 'name': id}, _usage(now)),
        aiProviderData({'id': 'empty', 'name': 'Empty'}, {'usage': {}}),
      ],
    }, now).map((provider) => provider.id).toList();

    expect(pill(const []), ['a', 'b', 'c']);
    expect(pill(const ['d', 'empty', 'b']), ['d', 'b']);
    expect(pill(const ['c', 'a', 'd', 'b']), ['c', 'a', 'd']);
  });

  testWidgets('ring arcs use the provider accent unless the quota is low', (
    tester,
  ) async {
    AiQuotaProvider provider(String id, num used) => AiQuotaProvider(
      aiProviderData({'id': id, 'name': id}, _usage(now, used: used)),
      now,
      20,
    );
    await _pumpRings(tester, [provider('claude', 30), provider('codex', 90)]);
    await tester.pumpAndSettle();
    final scheme = Theme.of(tester.element(find.byType(Row))).colorScheme;
    final rings = find.byType(AiQuotaRing);
    final accent = aiProviderAccent('claude', scheme);
    expect(accent, isNot(scheme.error));
    // Each arc paints its track first, then the active sweep.
    final track = scheme.onSurface.withValues(alpha: .16);
    expect(
      rings.first,
      paints
        ..arc(color: track)
        ..arc(color: accent),
    );
    expect(
      rings.last,
      paints
        ..arc(color: track)
        ..arc(color: scheme.error),
    );
  });

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

  test('discovers local providers by default and honors saved switches', () {
    const configured = [
      {'id': 'codex', 'name': 'Codex', 'enabled': true},
      {'id': 'claude', 'name': 'Claude', 'enabled': false},
      {'id': 'gemini', 'name': 'Gemini', 'enabled': false},
    ];
    final usage = [
      {'provider': 'codex', ..._usage(now)},
      {
        'provider': 'claude',
        'error': {'message': 'First account failed'},
      },
      {'provider': 'claude', ..._usage(now)},
      {
        'provider': 'gemini',
        'error': {'message': 'Sign in required'},
      },
      {'provider': 'other', ..._usage(now)},
      {
        'provider': 'vertexai',
        'usage': {'primary': null, 'secondary': null},
      },
      {
        'provider': 'tertiary-only',
        'usage': {
          'tertiary': {'usedPercent': 30},
        },
      },
    ];
    List<Object?> ids(bool automatic) => aiProviderSamples(
      configured,
      usage,
      previous: const [],
      automatic: automatic,
    ).map((row) => row['id']).toList();

    expect(ids(true), ['codex', 'claude', 'other', 'tertiary-only']);
    expect(ids(false), ['codex']);
  });

  testWidgets(
    'pill renders every provider and opens the card on hover or click',
    (tester) async {
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
          'providers': [
            for (final id in ['codex', 'claude', 'antigravity', 'other'])
              aiProviderData({'id': id, 'name': id}, _usage(DateTime.now())),
            aiProviderData({'id': 'pi', 'name': 'Pi'}, {'usage': {}}),
          ],
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
      expect(find.byType(AiQuotaRing), findsNWidgets(3));
      expect(find.text('OT'), findsNothing);
      final images = tester.widgetList<SvgPicture>(find.byType(SvgPicture));
      final claude = images.singleWhere(
        (image) =>
            (image.bytesLoader as SvgAssetLoader).assetName ==
            aiProviderIcon('claude'),
      );
      // Color logos keep their own colors; mono ones follow currentColor.
      expect(claude.colorFilter, isNull);
      final pill = find.byType(BarAiQuota);
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: tester.getCenter(pill));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 550));
      expect(
        calls
            .where((call) => call.method == 'show')
            .map((call) => call.arguments['kind']),
        [aiUsageKind],
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
    },
  );

  testWidgets(
    'detail card hides empty providers and balances and aligns pace',
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
                    'updatedAt': now
                        .subtract(const Duration(minutes: 3))
                        .toIso8601String(),
                    'providers': [
                      aiProviderData(_codex, {
                        ..._usage(now),
                        'credits': {'remaining': 0},
                      }),
                      aiProviderData(
                        {'id': 'vertexai', 'name': 'Vertex AI'},
                        {
                          'usage': {'primary': null},
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
      expect(find.text('Updated 3 min ago'), findsOneWidget);
      expect(find.text('Partial outage'), findsOneWidget);
      expect(find.text('Empty in ~28m'), findsOneWidget);
      expect(find.text('Vertex AI'), findsNothing);
      expect(find.text('Credits'), findsNothing);
      expect(find.text('Banked resets'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      final pace = find.text('Empty in ~28m');
      expect(tester.widget<Text>(pace).textAlign, TextAlign.end);
      expect(
        tester.getTopRight(pace).dx,
        closeTo(tester.getTopRight(find.text('2')).dx, 1),
      );

      expect(
        find.text('Code review  weekly', findRichText: true),
        findsOneWidget,
      );
      expect(find.text(r'$3.42 today', findRichText: true), findsOneWidget);
      final spendCaption = find.text('Local estimate · API rates');
      final spendLeft = tester.getTopLeft(find.text('Spend')).dx;
      final viewWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(tester.widget<Text>(spendCaption).textAlign, TextAlign.end);
      expect(
        tester.getTopRight(spendCaption).dx,
        closeTo(viewWidth - spendLeft, 1),
      );
      await tester.tap(find.byTooltip('Refresh'));
      expect(actions, [
        {'action': 'ai-usage.refresh'},
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'supports showUsed, 5h-inner ring order, AGY label, and % style',
    (tester) async {
      final now = DateTime.now();
      final backend = _AiUsageBackend()
        ..data = {
          'showUsed': true,
          'ringOrder': '5h-inner',
          'providers': [
            aiProviderData({
              'id': 'antigravity',
              'name': 'Antigravity',
            }, _usage(now, used: 70)),
          ],
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
      expect(find.text('70%', findRichText: true), findsOneWidget);
      BarPopup.openCard.value = aiUsageKind;
      addTearDown(() => BarPopup.openCard.value = null);
      await tester.pumpAndSettle();
      expect(find.textContaining('AGY'), findsOneWidget);
      expect(find.textContaining('ANTIGRAVITY'), findsNothing);
      expect(find.textContaining('70%', findRichText: true), findsOneWidget);
      final ring = tester.widget<AiQuotaRing>(find.byType(AiQuotaRing));
      expect(ring.showUsed, isTrue);
      expect(ring.ringOrder, '5h-inner');
      final (:outer, :inner) = ring.resolveWindows();
      expect(outer?.slot, 'secondary');
      expect(inner?.slot, 'primary');
      expect(inner?.percentValue(showUsed: true), 70);
      expect(inner?.used, 70);
      expect(inner?.expectedUsed, 68);
      BarPopup.openCard.value = null;
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _AiUsageBackend extends AiUsageBackend {
  int refreshes = 0;

  @override
  Future<void> refresh() async => refreshes++;
}
