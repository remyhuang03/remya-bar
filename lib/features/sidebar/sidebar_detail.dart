part of 'right_sidebar.dart';

class _DetailSections {
  const _DetailSections({
    required this.top,
    this.items = const [],
    this.bottom = const [],
  });

  final List<Widget> top;
  final List<Widget> items;
  final List<Widget> bottom;
}

class _SidebarDetail extends StatefulWidget {
  const _SidebarDetail({
    super.key,
    required this.kind,
    required this.data,
    required this.adapter,
    required this.onSelectAdapter,
    required this.busy,
    required this.send,
    required this.pad,
    required this.onHeight,
    this.error,
  });

  final String kind;
  final Map<String, Object?> data;
  final Map? adapter;
  final ValueChanged<String?> onSelectAdapter;
  final bool busy;
  final Future<bool> Function(String action, {Object? value, Object? target})
  send;
  final double pad;
  final ValueChanged<double> onHeight;
  final Widget? error;

  @override
  State<_SidebarDetail> createState() => _SidebarDetailState();
}

class _SidebarDetailState extends State<_SidebarDetail> {
  String? _expanded;
  double? _topHeight;
  double? _itemsHeight;
  double? _bottomHeight;

  void _expand(String id) =>
      setState(() => _expanded = _expanded == id ? null : id);

  void _reportHeight({required bool hasItems, required bool hasBottom}) {
    final top = _topHeight;
    final items = hasItems ? _itemsHeight : 0.0;
    final bottom = hasBottom ? _bottomHeight : 0.0;
    if (top == null || items == null || bottom == null) return;
    final gaps = (hasItems ? 12.0 : 0.0) + (hasBottom ? 12.0 : 0.0);
    widget.onHeight(top + items + bottom + gaps);
  }

  Widget _button(
    String label,
    VoidCallback? action, {
    bool exclusive = false,
  }) => FilledButton.tonal(
    onPressed: exclusive && widget.busy ? null : action,
    child: Text(label),
  );

  @override
  Widget build(BuildContext context) {
    final sections = switch (widget.kind) {
      'internet' => _wifi(),
      'bluetooth' => _bluetooth(),
      'audio' => _audio(),
      'power' => _power(),
      _ => const _DetailSections(top: []),
    };
    final top = [if (widget.error != null) widget.error!, ...sections.top];
    final hasItems = sections.items.isNotEmpty;
    final hasBottom = sections.bottom.isNotEmpty;
    if (!hasItems) _itemsHeight = 0;
    if (!hasBottom) _bottomHeight = 0;
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 12,
      children: [
        Padding(
          padding: .symmetric(horizontal: widget.pad),
          child: PopupMeasure(
            onHeight: (height) {
              _topHeight = height;
              _reportHeight(hasItems: hasItems, hasBottom: hasBottom);
            },
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .stretch,
              spacing: 8,
              children: top,
            ),
          ),
        ),
        if (hasItems)
          Flexible(
            fit: .loose,
            child: SingleChildScrollView(
              primary: false,
              padding: .symmetric(horizontal: widget.pad),
              child: PopupMeasure(
                onHeight: (height) {
                  _itemsHeight = height;
                  _reportHeight(hasItems: true, hasBottom: hasBottom);
                },
                child: Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .stretch,
                  spacing: 8,
                  children: sections.items,
                ),
              ),
            ),
          ),
        if (hasBottom)
          Padding(
            padding: .symmetric(horizontal: widget.pad),
            child: PopupMeasure(
              onHeight: (height) {
                _bottomHeight = height;
                _reportHeight(hasItems: hasItems, hasBottom: true);
              },
              child: Column(
                mainAxisSize: .min,
                crossAxisAlignment: .stretch,
                spacing: 8,
                children: sections.bottom,
              ),
            ),
          ),
      ],
    );
  }

  _DetailSections _wifi() {
    final network = _map(widget.data['network']);
    final device = _rowsOf<Map>(network['devices'])
        .where((device) => device['interface'] == network['adapter'])
        .firstOrNull;
    final accessPoints = _rowsOf<Map>(device?['networks'])
      ..sort((a, b) {
        final connected =
            (b['in_use'] == true ? 1 : 0) - (a['in_use'] == true ? 1 : 0);
        return connected == 0
            ? ((b['signal'] as int?) ?? 0).compareTo((a['signal'] as int?) ?? 0)
            : connected;
      });
    final enabled = network['wifi_enabled'] == true;
    final canConnect = enabled && device != null;
    final connecting = network['connecting'];
    final failure = _map(network['failure']);
    final connectedIsVisible = accessPoints.any(
      (point) => point['in_use'] == true,
    );
    final connectedName = device?['connection'];
    if (!connectedIsVisible && connectedName is String) {
      accessPoints.insert(0, {
        'in_use': true,
        'ssid': connectedName,
        'known_uuid': device?['uuid'],
      });
    }
    return _DetailSections(
      top: [
        Row(
          children: [
            const Expanded(child: Text('Available networks')),
            IconButton(
              tooltip: 'Scan for Wi-Fi networks',
              onPressed: canConnect
                  ? () => widget.send('sidebar.wifi-scan')
                  : null,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        if (network['available'] != true || device == null)
          const Text('Wi-Fi unavailable')
        else if (!enabled)
          const Text('Wi-Fi is off')
        else if (accessPoints.isEmpty)
          const Text('No networks found'),
        if (failure['ssid'] case final String ssid) ...[
          Text(failure['message'] as String? ?? 'Could not connect to $ssid'),
          if (failure['needs_password'] == true)
            Align(
              alignment: .centerLeft,
              child: _button(
                'Enter password',
                () => _wifiCredentials(
                  ssid: ssid,
                  uuid: failure['uuid'] as String?,
                  hidden:
                      failure['uuid'] == null &&
                      !accessPoints.any((point) => point['ssid'] == ssid),
                ),
                exclusive: true,
              ),
            ),
        ],
      ],
      items: [
        if (enabled)
          for (final point in accessPoints) _wifiRow(point, device, connecting),
      ],
      bottom: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _button(
              'Network settings',
              () => widget.send('sidebar.settings', target: 'wifi'),
            ),
            _button(
              'Hidden network…',
              canConnect && connecting == null
                  ? () => _wifiCredentials()
                  : null,
              exclusive: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _wifiRow(Map point, Map? device, Object? connecting) {
    final ssid = point['ssid'] as String;
    final uuid = point['known_uuid'] as String?;
    final selected = point['in_use'] == true;
    final security = point['security'];
    final secured = security != null && security != 'open';
    final signal = point['signal'] as int?;
    final frequency = point['frequency'] as num?;
    final expanded = _expanded == ssid;
    final pending = connecting == ssid;
    final supported =
        uuid != null ||
        const {'open', 'wpa', 'wpa2', 'wpa3'}.contains(security);
    final subtitle = [
      if (pending)
        'Connecting…'
      else if (selected)
        'Connected'
      else if (uuid != null)
        'Saved',
      if (selected && frequency != null)
        '${frequency >= 5900
            ? 6
            : frequency >= 4900
            ? 5
            : 2.4} GHz',
      if (device?['speed_mbps'] case final num speed when selected)
        '$speed Mb/s',
      if (!pending && !selected) secured ? 'Secured' : 'Open',
    ].join(' • ');
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        _DetailRow(
          icon: switch (signal) {
            final int value when value < 30 => Icons.network_wifi_1_bar_rounded,
            final int value when value < 55 => Icons.network_wifi_2_bar_rounded,
            final int value when value < 75 => Icons.network_wifi_3_bar_rounded,
            _ => Icons.wifi_rounded,
          },
          title: ssid,
          subtitle: subtitle,
          selected: selected,
          pending: pending,
          trailing: secured ? Icons.lock_rounded : null,
          onTap: selected
              ? () => _expand(ssid)
              : widget.busy || connecting != null
              ? null
              : !supported
              ? () => widget.send('sidebar.settings', target: 'wifi')
              : secured && uuid == null
              ? () => _wifiCredentials(ssid: ssid)
              : () => widget.send(
                  'sidebar.wifi-connect',
                  value: uuid == null ? {'ssid': ssid} : {'uuid': uuid},
                ),
        ),
        if (selected && expanded)
          Wrap(
            spacing: 4,
            children: [
              TextButton(
                onPressed: () => widget.send('sidebar.wifi-disconnect'),
                child: const Text('Disconnect'),
              ),
              if (uuid != null)
                TextButton(
                  onPressed: widget.busy
                      ? null
                      : () async {
                          if (await _confirm('Forget $ssid?', 'Forget') &&
                              mounted) {
                            await widget.send(
                              'sidebar.wifi-forget',
                              target: uuid,
                            );
                          }
                        },
                  child: const Text('Forget'),
                ),
              TextButton(
                onPressed: () => _wifiDetails(point, device),
                child: const Text('Details'),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _wifiDetails(Map point, Map? device) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(point['ssid'] as String),
      content: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        spacing: 8,
        children: [
          if (point['security'] case final String security)
            Text('Security: ${security.toUpperCase()}'),
          if (point['signal'] case final int signal)
            PercentText('$signal', prefix: 'Signal: '),
          if (point['frequency'] case final int frequency)
            Text('Frequency: $frequency MHz'),
          if (device?['speed_mbps'] case final int speed)
            Text('Link speed: $speed Mb/s'),
          for (final address in _rowsOf<String>(device?['ipv4']))
            Text('IPv4: $address'),
          for (final address in _rowsOf<String>(device?['ipv6']))
            Text('IPv6: $address'),
          if (device?['gateway'] case final String gateway)
            Text('Gateway: $gateway'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );

  Future<void> _wifiCredentials({
    String? ssid,
    String? uuid,
    bool? hidden,
  }) async {
    final request = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => _WifiCredentials(
        ssid: ssid,
        uuid: uuid,
        hidden: hidden ?? ssid == null,
      ),
    );
    if (mounted && request != null) {
      await widget.send('sidebar.wifi-connect', value: request);
    }
  }

  Future<bool> _confirm(String title, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  _DetailSections _bluetooth() {
    final bluetooth = _map(widget.data['bluetooth']);
    final adapter = widget.adapter;
    final adapters = _rowsOf<Map>(bluetooth['adapters']);
    final adapterId = adapter?['id'];
    final enabled = adapter?['powered'] == true;
    final scanning = _rowsOf<String>(bluetooth['scanning']).contains(adapterId);
    final pairing = bluetooth['operation'] != null;
    final prompt = _map(bluetooth['prompt']);
    final devices =
        _rowsOf<Map>(bluetooth['devices'])
            .where(
              (device) =>
                  device['adapter'] == adapterId &&
                  device['blocked'] != true &&
                  (scanning ||
                      device['paired'] == true ||
                      device['bonded'] == true ||
                      device['connected'] == true),
            )
            .toList()
          ..sort(
            (a, b) =>
                (b['connected'] == true ? 1 : 0) -
                (a['connected'] == true ? 1 : 0),
          );
    return _DetailSections(
      top: [
        Text(
          adapterId == null
              ? 'Bluetooth unavailable'
              : enabled
              ? 'Bluetooth devices'
              : 'Bluetooth is off',
        ),
        if (adapters.length > 1)
          DropdownButton<String>(
            isExpanded: true,
            value: adapterId as String?,
            onChanged: pairing ? null : widget.onSelectAdapter,
            items: [
              for (final item in adapters)
                DropdownMenuItem(
                  value: item['id'] as String,
                  child: Text(
                    item['name'] as String? ?? item['address'] as String,
                  ),
                ),
            ],
          ),
        if (bluetooth['error'] case final String error) Text(error),
        if (prompt.isNotEmpty)
          _PairPrompt(
            key: ValueKey(prompt['id']),
            prompt: prompt,
            busy: widget.busy,
            send: (value) =>
                widget.send('sidebar.bluetooth-respond', value: value),
          ),
        if (pairing)
          Align(
            alignment: .centerLeft,
            child: _button(
              'Cancel pairing',
              () => widget.send(
                'sidebar.bluetooth-cancel',
                value: <String, Object?>{},
              ),
              exclusive: true,
            ),
          ),
      ],
      items: [
        for (final device in devices) ...[
          _DetailRow(
            icon: Icons.bluetooth_rounded,
            title: device['name'] as String? ?? device['address'] as String,
            subtitle: device['connected'] == true
                ? 'Connected'
                : device['paired'] == true || device['bonded'] == true
                ? 'Paired'
                : 'Available',
            selected: device['connected'] == true,
            trailing: Icons.chevron_right_rounded,
            onTap: () => _expand(device['id'] as String),
          ),
          if (_expanded == device['id'])
            Wrap(
              spacing: 8,
              children: [
                _button(
                  device['connected'] == true
                      ? 'Disconnect'
                      : device['paired'] == true
                      ? 'Connect'
                      : 'Pair',
                  enabled && !pairing
                      ? () => _deviceAction(
                          device['connected'] == true
                              ? 'disconnect'
                              : device['paired'] == true
                              ? 'connect'
                              : 'pair',
                          device,
                        )
                      : null,
                  exclusive:
                      device['connected'] != true && device['paired'] != true,
                ),
                if (device['paired'] == true || device['bonded'] == true)
                  _button(
                    'Forget',
                    !pairing && enabled
                        ? () async {
                            if (await _confirm(
                                  'Forget ${device['name'] ?? device['address']}?',
                                  'Forget',
                                ) &&
                                mounted) {
                              await _deviceAction('forget', device);
                            }
                          }
                        : null,
                    exclusive: true,
                  ),
              ],
            ),
        ],
      ],
      bottom: [
        Wrap(
          spacing: 8,
          children: [
            _button(
              'Bluetooth settings',
              () => widget.send('sidebar.settings', target: 'bluetooth'),
            ),
            _button(
              scanning ? 'Stop scan' : 'Scan',
              enabled && !pairing
                  ? () => widget.send(
                      'sidebar.bluetooth-scan',
                      value: {'adapter': adapterId, 'enabled': !scanning},
                    )
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  Future<bool> _deviceAction(String action, Map device) => widget.send(
    'sidebar.bluetooth-$action',
    value: {'adapter': device['adapter'], 'device': device['id']},
  );

  _DetailSections _audio() {
    final system = _map(_map(widget.data['sound'])['system']);
    final devices = _rowsOf<Map>(system['devices'])
        .where((device) => device['direction'] == 'output')
        .toList();
    return _DetailSections(
      top: [
        Text(devices.isEmpty ? 'Audio output unavailable' : 'Output devices'),
      ],
      items: [
        for (final device in devices)
          _DetailRow(
            icon: Icons.headphones_rounded,
            title: device['description'] as String? ?? device['name'] as String,
            subtitle: device['name'] == system['default_output']
                ? 'Default output'
                : 'Available',
            selected: device['name'] == system['default_output'],
            onTap: device['name'] == system['default_output']
                ? null
                : () => widget.send(
                    'sidebar.output-device',
                    target: device['name'],
                  ),
          ),
      ],
      bottom: [
        Align(
          alignment: .centerLeft,
          child: _button(
            'Sound settings',
            () => widget.send('sidebar.settings', target: 'sound-volume'),
          ),
        ),
      ],
    );
  }

  _DetailSections _power() {
    final power = _map(widget.data['power']);
    final system = _map(power['system']);
    final profiles = _rowsOf<String>(system['profiles']);
    return _DetailSections(
      top: [
        Text(profiles.isEmpty ? 'Power modes unavailable' : 'Power mode'),
        if (power['conflict'] == true)
          const Text('Resolve the power mode conflict in Settings.'),
      ],
      items: [
        for (final profile in profiles)
          _DetailRow(
            icon: switch (profile) {
              'power-saver' => Icons.energy_savings_leaf_rounded,
              'performance' => Icons.speed_rounded,
              _ => Icons.bolt_rounded,
            },
            title: _profileLabel(profile),
            subtitle: profile == system['profile']
                ? 'Current mode'
                : 'Available',
            selected: profile == system['profile'],
            onTap: power['conflict'] == true || profile == system['profile']
                ? null
                : () => widget.send('sidebar.profile', value: profile),
          ),
      ],
      bottom: [
        Align(
          alignment: .centerLeft,
          child: _button(
            'Power settings',
            () => widget.send('sidebar.settings', target: 'power'),
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.selected = false,
    this.pending = false,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool pending;
  final IconData? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.primaryContainer : Colors.transparent,
      borderRadius: .circular(selected ? 24 : 20),
      clipBehavior: .antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: selected || pending
            ? Colors.transparent
            : colors.onSurface.withValues(alpha: .08),
        child: Padding(
          padding: const .fromLTRB(8, 8, 16, 8),
          child: Row(
            spacing: 12,
            children: [
              Material(
                color: selected
                    ? colors.primary
                    : colors.surfaceContainerHighest,
                borderRadius: .circular(selected ? 14 : 22),
                child: SizedBox.square(
                  dimension: 44,
                  child: Icon(
                    icon,
                    size: 20,
                    color: selected
                        ? colors.onPrimary
                        : colors.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: _SidebarLabel(
                  title,
                  subtitle,
                  titleColor: selected ? colors.onPrimaryContainer : null,
                  subtitleColor: pending
                      ? colors.primary
                      : selected
                      ? colors.onPrimaryContainer
                      : null,
                ),
              ),
              if (pending)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if ((selected ? Icons.check_rounded : trailing)
                  case final mark?)
                Icon(
                  mark,
                  size: 18,
                  color: selected
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WifiCredentials extends StatefulWidget {
  const _WifiCredentials({this.ssid, this.uuid, required this.hidden});
  final String? ssid;
  final String? uuid;
  final bool hidden;

  @override
  State<_WifiCredentials> createState() => _WifiCredentialsState();
}

class _WifiCredentialsState extends State<_WifiCredentials> {
  late final _name = TextEditingController(
    text: widget.hidden ? widget.ssid : null,
  );
  final _password = TextEditingController();
  String _security = 'wpa2';
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  void _connect() {
    final name = widget.hidden ? _name.text : widget.ssid!;
    final password = _security == 'open' ? null : _password.text;
    if (name.isEmpty || (password != null && password.length < 8)) {
      setState(() => _error = 'Enter the network name and a valid password.');
      return;
    }
    Navigator.pop(context, {
      if (widget.uuid case final uuid?) 'uuid': uuid else 'ssid': name,
      'password': ?password,
      if (widget.hidden) 'hidden_security': _security,
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.hidden ? 'Hidden network' : widget.ssid!),
    content: Column(
      mainAxisSize: .min,
      spacing: 12,
      children: [
        if (widget.hidden) ...[
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Network name'),
          ),
          DropdownButtonFormField<String>(
            initialValue: _security,
            decoration: const InputDecoration(labelText: 'Security'),
            items: const [
              DropdownMenuItem(value: 'wpa2', child: Text('WPA2 Personal')),
              DropdownMenuItem(value: 'wpa3', child: Text('WPA3 Personal')),
              DropdownMenuItem(value: 'open', child: Text('Open')),
            ],
            onChanged: (value) => setState(() => _security = value!),
          ),
        ],
        if (_security != 'open')
          TextField(
            controller: _password,
            autofocus: !widget.hidden,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Password'),
            onSubmitted: (_) => _connect(),
          ),
        if (_error case final error?) Text(error),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _connect, child: const Text('Connect')),
    ],
  );
}

class _PairPrompt extends StatefulWidget {
  const _PairPrompt({
    super.key,
    required this.prompt,
    required this.busy,
    required this.send,
  });
  final Map prompt;
  final bool busy;
  final ValueChanged<Map<String, Object?>> send;

  @override
  State<_PairPrompt> createState() => _PairPromptState();
}

class _PairPromptState extends State<_PairPrompt> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.prompt['kind'] as String? ?? '';
    final pin = kind == 'RequestPinCode';
    final passkey = kind == 'RequestPasskey';
    final display = kind.startsWith('Display');
    final valid = pin
        ? RegExp(r'^[a-zA-Z0-9]{1,16}$').hasMatch(_code.text)
        : !passkey || RegExp(r'^\d{1,6}$').hasMatch(_code.text);
    return Column(
      crossAxisAlignment: .start,
      spacing: 8,
      children: [
        Text(
          pin || passkey
              ? 'Enter the pairing code'
              : display
              ? 'Enter this code on your device'
              : 'Confirm Bluetooth pairing',
        ),
        if (widget.prompt['code'] case final String code)
          Text(code, style: Theme.of(context).textTheme.titleLarge),
        if (pin || passkey)
          TextField(
            controller: _code,
            decoration: const InputDecoration(labelText: 'Pairing code'),
            onChanged: (_) => setState(() {}),
          ),
        if (!display)
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: widget.busy || !valid
                    ? null
                    : () => widget.send({
                        'request': widget.prompt['id'],
                        'accept': true,
                        if (pin) 'pin': _code.text,
                        if (passkey) 'passkey': int.parse(_code.text),
                      }),
                child: const Text('Confirm'),
              ),
              TextButton(
                onPressed: widget.busy
                    ? null
                    : () => widget.send({
                        'request': widget.prompt['id'],
                        'accept': false,
                      }),
                child: const Text('Reject'),
              ),
            ],
          ),
      ],
    );
  }
}
