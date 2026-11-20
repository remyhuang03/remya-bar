import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import 'weather_backend.dart';
import 'weather_controller.dart';

/// Content shared by the bar card and the settings location dialog.
class WeatherLocationPicker extends StatefulWidget {
  const WeatherLocationPicker({
    super.key,
    required this.onClose,
    this.controller,
  });

  final VoidCallback onClose;
  final WeatherController? controller;

  @override
  State<WeatherLocationPicker> createState() => _WeatherLocationPickerState();
}

class _WeatherLocationPickerState extends State<WeatherLocationPicker> {
  late final _weather = widget.controller ?? WeatherController.instance;
  final _search = TextEditingController();
  String? _revision;
  String? _saveError;
  Timer? _debounce;
  int _searchGeneration = 0;
  bool _manual = false;
  bool _searching = false;
  List<WeatherLocation>? _matches;
  String? _searchError;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _searchChanged(String input) {
    _debounce?.cancel();
    final generation = ++_searchGeneration;
    final query = input.trim();
    final canSearch = !_manual && query.runes.length >= 2;
    setState(() {
      _searching = canSearch;
      _matches = null;
      _searchError = null;
    });
    if (!canSearch) return;

    final language = View.of(context).platformDispatcher.locale.languageCode
        .toLowerCase();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final matches = await _weather.backend.search(
          query,
          language: language.length == 2 ? language : 'en',
        );
        if (!mounted || generation != _searchGeneration) return;
        setState(() {
          _matches = matches;
          _searching = false;
        });
      } catch (_) {
        if (!mounted || generation != _searchGeneration) return;
        setState(() {
          _searchError = 'Could not find locations. Try again.';
          _searching = false;
        });
      }
    });
  }

  void _setManual(bool value) {
    _manual = value;
    _searchChanged(_search.text);
  }

  Future<void> _select(WeatherLocation location) async {
    final revision = _revision;
    if (revision == null || _weather.savingLocation) return;
    setState(() => _saveError = null);
    if (await _weather.select(location, revision)) {
      if (mounted) widget.onClose();
    } else if (mounted) {
      setState(
        () => _saveError =
            _weather.locationError ?? 'Could not save the location.',
      );
    }
  }

  Future<void> _reloadLocations() async {
    await _weather.reload();
    if (mounted) {
      setState(() {
        _revision = _weather.locationRevision;
        _saveError = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _weather,
    builder: (context, _) {
      _revision ??= _weather.locationRevision;
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final supporting = theme.textTheme.bodySmall?.copyWith(
        color: colors.onSurfaceVariant,
      );
      final canSelect = _revision != null && !_weather.savingLocation;
      return Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        spacing: 16,
        children: [
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: Text(
                  _manual ? 'Enter coordinates' : 'Choose a location',
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Close location picker',
                onPressed: _weather.savingLocation ? null : widget.onClose,
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
          if (_saveError ?? (_revision == null ? _weather.locationError : null)
              case final error?)
            _PickerError(
              message: error,
              action: 'Reload',
              onAction: _reloadLocations,
            ),
          if (_manual)
            _ManualLocationForm(
              onBack: () => _setManual(false),
              onSelect: canSelect ? _select : null,
              saving: _weather.savingLocation,
            )
          else ...[
            TextField(
              autofocus: true,
              controller: _search,
              enabled: !_weather.savingLocation,
              onChanged: _searchChanged,
              onSubmitted: (_) {
                final matches = _matches;
                if (canSelect && matches != null && matches.length == 1) {
                  unawaited(_select(matches.single));
                }
              },
              textInputAction: .search,
              decoration: _field(
                colors,
                'Search city or postal code',
                helper: 'City, region and country help distinguish matches',
              ),
            ),
            if (_searching)
              const LinearProgressIndicator(
                semanticsLabel: 'Searching for locations',
              )
            else if (_searchError case final error?)
              _PickerError(
                message: error,
                action: 'Retry',
                onAction: () => _searchChanged(_search.text),
              )
            else if (_matches case final results?)
              if (results.isEmpty)
                Semantics(
                  liveRegion: true,
                  child: const Text('No matching locations'),
                )
              else
                for (final result in results)
                  _LocationResult(
                    location: result,
                    selected: sameWeatherLocation(_weather.location, result),
                    onTap: canSelect ? () => _select(result) : null,
                  )
            else
              Text(
                'Enter at least two characters to search.',
                style: supporting,
              ),
            Align(
              alignment: .centerLeft,
              child: TextButton(
                onPressed: _weather.savingLocation
                    ? null
                    : () => _setManual(true),
                child: const Text('Enter coordinates'),
              ),
            ),
          ],
          Text(
            'Search text and the selected coordinates are sent to Open-Meteo.',
            style: supporting,
          ),
          Text('Location search by GeoNames / Open-Meteo', style: supporting),
        ],
      );
    },
  );
}

InputDecoration _field(ColorScheme colors, String label, {String? helper}) =>
    InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 3,
      filled: true,
      fillColor: colors.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: .circular(12),
        borderSide: .none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: .circular(12),
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
    );

class _LocationResult extends StatelessWidget {
  const _LocationResult({
    required this.location,
    required this.selected,
    required this.onTap,
  });

  final WeatherLocation location;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final region = weatherRegion(location);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: colors.surfaceContainerHighest,
        borderRadius: .circular(16),
        clipBehavior: .antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 66),
            child: Padding(
              padding: const .symmetric(horizontal: 16, vertical: 12),
              child: Row(
                spacing: 12,
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      mainAxisSize: .min,
                      spacing: 2,
                      children: [
                        Text(location.name, style: theme.textTheme.bodyLarge),
                        if (region.isNotEmpty)
                          Text(
                            region,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_rounded, size: 20, color: colors.primary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ManualLocationForm extends StatefulWidget {
  const _ManualLocationForm({
    required this.onBack,
    required this.onSelect,
    required this.saving,
  });

  final VoidCallback onBack;
  final ValueChanged<WeatherLocation>? onSelect;
  final bool saving;

  @override
  State<_ManualLocationForm> createState() => _ManualLocationFormState();
}

class _ManualLocationFormState extends State<_ManualLocationForm> {
  final _form = GlobalKey<FormState>();
  late String _name;
  late double _latitude;
  late double _longitude;

  static double? _parse(String? value) =>
      double.tryParse((value ?? '').trim().replaceAll(',', '.'));

  static String? _coordinateError(String? value, int bound) {
    final parsed = _parse(value);
    return parsed != null && parsed >= -bound && parsed <= bound
        ? null
        : 'Enter a value from −$bound to $bound.';
  }

  void _submit() {
    final select = widget.onSelect;
    if (select == null || !_form.currentState!.validate()) return;
    _form.currentState!.save();
    select(
      WeatherLocation(name: _name, latitude: _latitude, longitude: _longitude),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Form(
      key: _form,
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        spacing: 12,
        children: [
          TextFormField(
            autofocus: true,
            enabled: !widget.saving,
            textInputAction: .next,
            decoration: _field(colors, 'Location name'),
            validator: (value) {
              final label = value?.trim() ?? '';
              return label.isEmpty ||
                      utf8.encode(label).length > 256 ||
                      RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(label)
                  ? 'Enter a valid location name.'
                  : null;
            },
            onSaved: (value) => _name = value!.trim(),
          ),
          TextFormField(
            enabled: !widget.saving,
            textInputAction: .next,
            decoration: _field(colors, 'Latitude'),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            validator: (value) => _coordinateError(value, 90),
            onSaved: (value) => _latitude = _parse(value)!,
          ),
          TextFormField(
            enabled: !widget.saving,
            decoration: _field(colors, 'Longitude'),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            onFieldSubmitted: (_) => _submit(),
            validator: (value) => _coordinateError(value, 180),
            onSaved: (value) => _longitude = _parse(value)!,
          ),
          Align(
            alignment: .centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: widget.saving ? null : widget.onBack,
                  child: const Text('Back'),
                ),
                FilledButton(
                  onPressed: widget.onSelect == null ? null : _submit,
                  child: Text(widget.saving ? 'Saving…' : 'Save location'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerError extends StatelessWidget {
  const _PickerError({
    required this.message,
    required this.action,
    required this.onAction,
  });

  final String message;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Row(
    spacing: 8,
    children: [
      Expanded(child: Semantics(liveRegion: true, child: Text(message))),
      TextButton(onPressed: onAction, child: Text(action)),
    ],
  );
}
