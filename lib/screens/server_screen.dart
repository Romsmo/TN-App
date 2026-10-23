import 'package:flutter/material.dart';
import 'package:tn_core/tn_core.dart';

import '../app_scope.dart';
import '../services/app_config.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'common.dart';

/// "Server verbinden": the address, the access data, the status and the known nodes.
class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key});

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  late final TextEditingController _address;
  final _accessId = TextEditingController();
  final _accessSecret = TextEditingController();
  String? _addressError;
  bool _app = true;
  String? _accessMessage;

  @override
  void initState() {
    super.initState();
    _address = TextEditingController(text: context.app.settings.value.serverAddress ?? '');
  }

  @override
  void dispose() {
    _address.dispose();
    _accessId.dispose();
    _accessSecret.dispose();
    super.dispose();
  }

  void _connect() {
    final r = normalizeServerAddress(_address.text, allowInsecure: buildConfig.allowInsecureServer);
    switch (r) {
      case AddressError(:final reason):
        setState(() => _addressError = switch (reason) {
              AddressProblem.empty => 'server.errorEmpty',
              AddressProblem.invalid => 'server.errorInvalid',
              AddressProblem.insecure => 'server.errorInsecure',
              AddressProblem.credentials => 'server.errorCredentials',
            });
      case AddressOk(:final url):
        setState(() => _addressError = null);
        _address.text = url;
        context.app.settings.update((s) => s.copyWith(serverAddress: url));
    }
  }

  void _useDiscovery() {
    setState(() => _addressError = null);
    _address.text = '';
    context.app.settings.update((s) => s.copyWith(serverAddress: null));
  }

  Future<void> _saveAccess() async {
    final id = _accessId.text.trim();
    final secret = _accessSecret.text.trim();
    if (id.isEmpty || secret.isEmpty) {
      setState(() => _accessMessage = 'server.accessIncomplete');
      return;
    }
    await context.app.credentials.set(_app ? AppCredentials(id, secret) : ClientCredentials(id, secret));
    _accessId.clear();
    _accessSecret.clear();
    if (mounted) setState(() => _accessMessage = 'server.accessSaved');
  }

  Future<void> _clearAccess() async {
    await context.app.credentials.clear();
    if (mounted) setState(() => _accessMessage = null);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final c = context.colors;
    return ListenableBuilder(
      listenable: Listenable.merge([app.settings, app.tn]),
      builder: (context, _) {
        final snap = app.tn.snapshot;
        final sync = snap.sync;
        final nodes = snap.network?.knownNodes ?? const <NodeView>[];
        final current = {...?snap.network?.currentNodes};
        final server = app.settings.value.serverAddress;
        return SubPage(
          title: context.t('server.title'),
          children: [
            CardSection(title: context.t('server.address'), children: [
              TextField(
                controller: _address,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.none,
                decoration: const InputDecoration(hintText: 'node.example.org'),
                style: TnText.body.copyWith(color: c.text),
              ),
              Hint(context.t('server.addressHint')),
              if (_addressError != null)
                Semantics(liveRegion: true, child: Text(context.t(_addressError!), style: TextStyle(fontSize: 15, color: c.danger))),
              PrimaryButton(label: context.t('server.connect'), onPressed: _connect),
              SoftButton(label: context.t('server.auto'), onPressed: _useDiscovery),
              Hint(server != null ? context.t('server.usingServer', {'address': server}) : context.t('server.usingDiscovery')),
            ]),
            CardSection(title: context.t('server.access'), children: [
              Hint(context.t('server.accessHint')),
              Row(children: [
                Expanded(child: _KindButton(label: context.t('server.accessKind.app'), selected: _app, onTap: () => setState(() => _app = true))),
                const SizedBox(width: Space.sm),
                Expanded(child: _KindButton(label: context.t('server.accessKind.client'), selected: !_app, onTap: () => setState(() => _app = false))),
              ]),
              TextField(
                controller: _accessId,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(hintText: context.t('server.accessId')),
                style: TnText.body.copyWith(color: c.text),
              ),
              TextField(
                controller: _accessSecret,
                autocorrect: false,
                enableSuggestions: false,
                obscureText: true,
                decoration: InputDecoration(hintText: context.t('server.accessSecret')),
                style: TnText.body.copyWith(color: c.text),
              ),
              if (_accessMessage != null) Hint(context.t(_accessMessage!)),
              PrimaryButton(label: context.t('server.accessSave'), onPressed: _saveAccess),
              SoftButton(label: context.t('server.accessClear'), onPressed: _clearAccess),
            ]),
            CardSection(title: context.t('server.status'), children: [
              if (snap.phase == Phase.starting) Hint(context.t('status.starting')),
              if (snap.phase == Phase.noCredentials) Hint(context.t('status.noCredentials')),
              if (snap.phase == Phase.error) Hint(context.t('status.error', {'message': snap.error ?? context.t('common.unknown')})),
              if (sync != null) ...[
                Body(context.t('server.connection.${sync.connection.name}')),
                Hint(context.t('server.lastSync', {
                  'time': sync.lastSyncedAtUnixMs != null ? formatDateTime(context, sync.lastSyncedAtUnixMs!) : context.t('common.never'),
                })),
                Hint(context.t('server.pending', {'count': sync.pendingWrites})),
                if (sync.lastErrorCode != null) Hint(context.t('server.lastError', {'code': sync.lastErrorCode!})),
              ],
              if (snap.network?.onlineNetwork != null) Hint(context.t('server.online', {'count': snap.network!.onlineNetwork!})),
              PrimaryButton(label: context.t('server.syncNow'), onPressed: snap.service == null ? null : () => app.tn.syncNow()),
            ]),
            CardSection(title: context.t('server.nodes'), children: [
              if (nodes.isEmpty) Hint(context.t('server.nodesNone')),
              for (final n in nodes)
                Semantics(
                  container: true,
                  label: '${n.address}, ${context.t('server.tier.${n.tier.name}')}',
                  child: ExcludeSemantics(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Body(n.address),
                      Hint([
                        context.t('server.tier.${n.tier.name}'),
                        if (current.contains(n.nodeId)) context.t('server.nodeUsed'),
                        if (n.backedOff) context.t('server.nodeBackedOff'),
                      ].join(' · ')),
                    ]),
                  ),
                ),
            ]),
          ],
        );
      },
    );
  }
}

class _KindButton extends StatelessWidget {
  const _KindButton({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        child: selected ? PrimaryButton(label: label, onPressed: onTap) : SoftButton(label: label, onPressed: onTap),
      );
}
