import 'package:flutter/services.dart';
import 'package:flutter/physics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

import '../../bar_theme.dart';
import '../notifications/notification_view.dart';
import '../tray/tray_menu_popup.dart';
import '../workspaces/bar_workspaces.dart';
import '../workspaces/workspace_overview.dart';
import 'bar_detail_card.dart';
import 'bar_popup.dart';
import 'popup_measure.dart';
import '../sidebar/right_sidebar.dart';

class BarPopupApp extends StatefulWidget {
  const BarPopupApp({super.key});

  @override
  State<BarPopupApp> createState() => _BarPopupAppState();
}

class _BarPopupAppState extends State<BarPopupApp>
    with SingleTickerProviderStateMixin {
  late final _emergence = AnimationController(vsync: this);
  bool _dismissing = false;
  int _dismissGeneration = 0;
  bool get _card => const {
    'media',
    'battery',
    'datetime',
    'resources',
    'notifications',
  }.contains(_kind);
  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) == true ||
      WidgetsBinding
          .instance
          .platformDispatcher
          .accessibilityFeatures
          .disableAnimations;

  void _emerge({required bool opening}) {
    final resume =
        _dismissing || (!_emergence.isAnimating && _emergence.value == 0);
    _dismissing = false;
    _dismissGeneration++;
    if (!opening && !resume) return;
    if (_reduceMotion) {
      _emergence.value = 1;
      return;
    }
    if (opening) _emergence.value = 0;
    _emergence
        .animateWith(
          SpringSimulation(
            SpringDescription.withDampingRatio(
              mass: 1,
              stiffness: 380,
              ratio: .8,
            ),
            _emergence.value,
            1,
            0,
          ),
        )
        .then((_) {
          if (mounted && !_dismissing) _emergence.value = 1;
        });
  }

  Future<void> _dismiss() async {
    if (!_card || _dismissing) return;
    final generation = ++_dismissGeneration;
    _dismissing = true;
    try {
      if (_reduceMotion) {
        _emergence.value = 0;
      } else {
        await _emergence
            .animateBack(
              0,
              duration: const Duration(milliseconds: 200),
              curve: Easing.emphasizedAccelerate,
            )
            .orCancel;
      }
      if (mounted && _dismissing && generation == _dismissGeneration) {
        await BarPopup.channel.invokeMethod<void>('hidden');
      }
    } on TickerCanceled {
      // A new hover resumes the same shape from its current progress.
    }
  }

  final _navigator = GlobalKey<NavigatorState>();
  String? _kind;
  int _contentGeneration = 0;
  int _opening = 0;
  Map<String, Object?> _data = const {};
  RemyaTheme? _theme;
  String? _actionError;
  bool _batteryActionPending = false;

  @override
  void initState() {
    super.initState();
    BarPopup.channel.setMethodCallHandler((call) async {
      if (call.method == 'dismiss') {
        _send(_dismiss());
        return;
      }
      if (call.method != 'content') throw MissingPluginException();
      final arguments = call.arguments;
      if (arguments is! Map ||
          arguments['theme'] is! Map ||
          arguments['data'] is! Map ||
          !const {
            'tooltip',
            'sidebar',
            'resources',
            'media',
            'battery',
            'datetime',
            'tray-menu',
            'notifications',
            notificationToastsKind,
            workspaceOverviewKind,
          }.contains(arguments['kind'])) {
        throw PlatformException(
          code: 'invalid-content',
          message: 'Invalid popup content',
        );
      }
      final baseTheme = RemyaTheme.fromMap(
        Map<String, dynamic>.from(arguments['theme'] as Map),
      );
      final seed = _seedColor(arguments['seed']);
      final theme = seed == null
          ? baseTheme
          : RemyaTheme(
              styleVariant: baseTheme.styleVariant,
              mode: baseTheme.mode,
              seedColor: seed,
            );
      final data = Map<String, Object?>.from(arguments['data'] as Map);
      if (arguments['kind'] == 'tooltip' &&
          (data['message'] is! String || data['scale'] is! num)) {
        throw PlatformException(
          code: 'invalid-content',
          message: 'Invalid tooltip content',
        );
      }
      if (arguments['kind'] == _kind && !data.containsKey('scale')) {
        data['scale'] = _data['scale'];
      }
      if (mounted) {
        setState(() {
          if (_kind != arguments['kind'] || _data['token'] != data['token']) {
            _actionError = null;
          }
          final opening =
              arguments['opening'] == true || _kind != arguments['kind'];
          _contentGeneration++;
          if (arguments['opening'] == true || _kind != arguments['kind']) {
            _navigator.currentState?.popUntil((route) => route.isFirst);
            _opening++;
          }
          _kind = arguments['kind'] as String;
          _data = data;
          _theme = theme;
          if (_card) {
            _emerge(opening: opening);
          } else {
            _dismissing = false;
            _dismissGeneration++;
            _emergence.stop();
          }
        });
      }
    });
    BarPopup.channel.invokeMethod<void>('ready');
  }

  @override
  void dispose() {
    BarPopup.channel.setMethodCallHandler(null);
    _emergence.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    if (theme == null) return const SizedBox.shrink();
    final scale = _data['scale'];
    final textScale = scale is num && scale.isFinite && scale > 0
        ? scale.toDouble()
        : 1.0;
    final details = switch (_kind) {
      'battery' => {
        ..._data,
        'pending': _batteryActionPending,
        'error': _actionError,
      },
      'media' || 'tray-menu' when _actionError != null => {
        ..._data,
        'error': _actionError,
      },
      _ => _data,
    };
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigator,
      theme: barTheme(theme.theme(.light)),
      darkTheme: barTheme(theme.theme(.dark)),
      themeMode: theme.mode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: .linear(textScale)),
        child: MouseRegion(
          onEnter: (_) => _send(BarPopup.enter()),
          onExit: (_) {
            if (_kind != 'sidebar') {
              _navigator.currentState?.popUntil((route) => route.isFirst);
            }
            _send(BarPopup.leave());
          },
          child: child!,
        ),
      ),
      home: _kind == 'sidebar'
          ? Align(
              alignment: .topRight,
              child: TweenAnimationBuilder<double>(
                key: ValueKey(_opening),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                tween: Tween(begin: 1, end: 0),
                builder: (context, offset, child) => FractionalTranslation(
                  translation: Offset(offset, 0),
                  child: child,
                ),
                child: RightSidebar(
                  data: details,
                  onAction: BarPopup.action,
                  onHeight: _resize,
                ),
              ),
            )
          : SingleChildScrollView(
              child: PopupMeasure(
                generation: _contentGeneration,
                onHeight: (height) => _send(
                  BarPopup.channel.invokeMethod<void>('resize', {
                    'height': height.ceil(),
                  }),
                ),
                child:
                    _kind == 'tooltip' ||
                        _card ||
                        _kind == notificationToastsKind
                    ? _content(details, textScale)
                    : TweenAnimationBuilder<double>(
                        key: ValueKey(_opening),
                        duration: const Duration(milliseconds: 150),
                        tween: Tween(begin: 0, end: 1),
                        curve: Curves.easeOutCubic,
                        builder: (context, progress, child) => Opacity(
                          opacity: progress,
                          child: Transform.scale(
                            scale: .96 + .04 * progress,
                            alignment: _kind == 'tray-menu'
                                ? .topLeft
                                : .topCenter,
                            child: child,
                          ),
                        ),
                        child: _content(details, textScale),
                      ),
              ),
            ),
    );
  }

  Widget _content(Map<String, Object?> details, double textScale) => Column(
    mainAxisSize: .min,
    crossAxisAlignment: .stretch,
    children: [
      if (_actionError case final error?
          when _kind != 'media' && _kind != 'battery' && _kind != 'tray-menu')
        MaterialBanner(
          content: Text(error),
          actions: [
            TextButton(
              onPressed: () => setState(() => _actionError = null),
              child: const Text('Dismiss'),
            ),
          ],
        ),
      Flexible(
        child: switch (_kind) {
          'tooltip' => _TooltipContent(
            message: _data['message'] as String,
            scale: textScale,
            tray: _data['tray'] == true,
          ),
          workspaceOverviewKind => WorkspaceOverview(
            workspaces: details['workspaces'] as List? ?? const [],
            onAction: _action,
          ),
          notificationToastsKind => NotificationToasts(
            data: details,
            onAction: _action,
          ),
          'tray-menu' => TrayMenuPopup(
            key: ValueKey(_data['token']),
            data: details,
            onAction: _action,
          ),
          _ => BarDetailCard(
            kind: _kind!,
            data: details,
            onAction: _action,
            styleVariant: _theme!.styleVariant,
            seedColor: _seedColor(details['cardSeed']),
            emergence: _emergence,
          ),
        },
      ),
    ],
  );

  void _resize(double height) => _send(
    BarPopup.channel.invokeMethod<void>('resize', {'height': height.ceil()}),
  );

  void _send(Future<void> request) {
    request.catchError((Object error) => debugPrint('Bar popup: $error'));
  }

  Future<void> _action(Map<String, Object?> action) async {
    final kind = _kind;
    final token = _data['token'];
    final battery = kind == 'battery';
    if (battery) {
      if (_batteryActionPending) return;
      setState(() => _batteryActionPending = true);
    }
    try {
      await BarPopup.action(action);
      if (mounted && _kind == kind && _data['token'] == token) {
        setState(() => _actionError = null);
      }
    } catch (error) {
      debugPrint('Bar popup action: $error');
      if (mounted && _kind == kind && _data['token'] == token) {
        setState(() => _actionError = 'Action failed. Please try again.');
      }
    } finally {
      if (mounted && battery) setState(() => _batteryActionPending = false);
    }
  }
}

Color? _seedColor(Object? rgb) =>
    rgb is int && rgb >= 0 && rgb <= 0xFFFFFF ? Color(0xFF000000 | rgb) : null;

class _TooltipContent extends StatelessWidget {
  const _TooltipContent({
    required this.message,
    required this.scale,
    required this.tray,
  });
  final String message;
  final double scale;
  final bool tray;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: tray
          ? theme.colorScheme.inverseSurface
          : theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: .circular(tray ? 4 : 8),
        side: tray
            ? .none
            : BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: .antiAlias,
      child: Padding(
        padding: .symmetric(horizontal: tray ? 8 : 12, vertical: tray ? 4 : 8),
        child: Text(
          message,
          textScaler: .linear(scale),
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: tray ? 12 : null,
            color: tray
                ? theme.colorScheme.onInverseSurface
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
