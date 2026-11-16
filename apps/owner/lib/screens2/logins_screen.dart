import 'dart:math';

import 'package:flutter/services.dart';
import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

/// Six random digits.
String randomPin() {
  final r = Random.secure();
  return List.generate(6, (_) => r.nextInt(10)).join();
}

/// Phone + PIN logins for owners and tenants.
class LoginsScreen extends StatefulWidget {
  const LoginsScreen({super.key});

  @override
  State<LoginsScreen> createState() => _LoginsScreenState();
}

class _LoginsScreenState extends State<LoginsScreen> {
  final _loader = GlobalKey<LoaderState<List<Json>>>();
  final _api = KirayaApi.instance;
  List<Json> _logins = const [];

  Future<List<Json>> _load() async => _logins = await _api.logins();
  Future<void> _reload() async => _loader.currentState?.reload();

  Future<void> _showPin(String name, String phone, String pin) => showDialog<void>(
        context: context,
        builder: (_) => _PinReadyDialog(name: name, phone: phone, pin: pin),
      );

  Future<void> _resetPin(Json u) async {
    final r = await showDialog<_LoginInput>(
      context: context,
      builder: (_) => _LoginDialog(title: tr('s2_reset_pin_for', {'name': u['name']})),
    );
    if (r == null || !mounted) return;
    final ok = await runBusy(context, () async {
      await _api.manageLogin({'action': 'reset_pin', 'phone': u['phone'], 'pin': r.pin});
      return true;
    });
    if (ok == true && mounted) await _showPin('${u['name']}', '${u['phone']}', r.pin);
  }

  Future<void> _setActive(Json u, bool active) async {
    final q = active ? tr('s2_turn_on_q', {'name': u['name']}) : tr('s2_turn_off_q', {'name': u['name']});
    if (!await confirm(context, q, yes: active ? tr('s2_turn_on') : tr('s2_turn_off'))) return;
    if (!mounted) return;
    final ok = await runBusy(context, () async {
      await _api.manageLogin({'action': 'set_active', 'phone': u['phone'], 'active': active});
      return true;
    }, success: tr('saved'));
    if (ok == true) await _reload();
  }

  Future<void> _giveTenantLogin() async {
    final existing = {for (final u in _logins) u['tenant_id']}..remove(null);
    final person = await Navigator.push<Json>(
        context, MaterialPageRoute(builder: (_) => _PickTenantPage(hasLogin: existing.cast<String>().toSet())));
    if (person == null || !mounted) return;
    final r = await showDialog<_LoginInput>(
      context: context,
      builder: (_) => _LoginDialog(
        title: tr('s2_login_for', {'name': person['full_name']}),
        askPhone: true,
        initialPhone: '${person['phone'] ?? ''}',
      ),
    );
    if (r == null || !mounted) return;
    final ok = await runBusy(context, () async {
      await _api.manageLogin({'action': 'create_tenant_login', 'tenant_id': person['id'], 'pin': r.pin, 'phone': r.phone});
      return true;
    });
    if (ok != true || !mounted) return;
    await _reload();
    if (mounted) await _showPin('${person['full_name']}', r.phone, r.pin);
  }

  Future<void> _addOwner() async {
    final r = await showDialog<_LoginInput>(
      context: context,
      builder: (_) => _LoginDialog(title: tr('s2_add_owner_login'), askName: true, askPhone: true),
    );
    if (r == null || !mounted) return;
    final ok = await runBusy(context, () async {
      await _api.manageLogin({'action': 'create_owner', 'name': r.name, 'phone': r.phone, 'pin': r.pin});
      return true;
    });
    if (ok != true || !mounted) return;
    await _reload();
    if (mounted) await _showPin(r.name, r.phone, r.pin);
  }

  Widget _card(Json u) {
    final owner = u['role'] == 'OWNER';
    final active = u['active'] != false;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: active ? null : Colors.black12,
              child: Icon(owner ? Icons.admin_panel_settings : Icons.person),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${u['name'] ?? '-'}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                Text('${u['phone'] ?? ''}'),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              StatusChip(owner ? tr('s2_role_owner') : tr('s2_role_tenant'), color: owner ? Colors.indigo : Colors.teal),
              if (!active) ...[const SizedBox(height: 4), StatusChip(tr('s2_login_off'), color: kBad)],
            ]),
          ]),
          if ((u['phone'] ?? '').toString().isNotEmpty)
            Wrap(spacing: 4, children: [
              TextButton.icon(onPressed: () => _resetPin(u), icon: const Icon(Icons.password), label: Text(tr('s2_reset_pin'))),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: active ? kBad : kGood),
                onPressed: () => _setActive(u, !active),
                icon: Icon(active ? Icons.block : Icons.check_circle_outline),
                label: Text(active ? tr('s2_turn_off') : tr('s2_turn_on')),
              ),
            ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('s2_logins'))),
        body: Loader<List<Json>>(
          key: _loader,
          load: _load,
          builder: (context, rows, _) {
            final owners = rows.where((u) => u['role'] == 'OWNER').toList();
            final tenants = rows.where((u) => u['role'] != 'OWNER').toList();
            return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: BigButton(label: tr('s2_give_tenant_login'), icon: Icons.person_add, onPressed: _giveTenantLogin),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: BigButton(
                    label: tr('s2_add_owner_login'), icon: Icons.admin_panel_settings, outlined: true, onPressed: _addOwner),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(tr('s2_logins_help'), style: Theme.of(context).textTheme.bodyMedium),
              ),
              SectionTitle(tr('s2_owners')),
              for (final u in owners) _card(u),
              SectionTitle(tr('s2_tenants')),
              if (tenants.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(tr('s2_no_tenant_logins'))),
              for (final u in tenants) _card(u),
            ]);
          },
        ),
      );
}

typedef _LoginInput = ({String name, String phone, String pin});

/// PIN entry (plus name / phone when needed) with a "Make random PIN" button.
class _LoginDialog extends StatefulWidget {
  const _LoginDialog({required this.title, this.askName = false, this.askPhone = false, this.initialPhone = ''});
  final String title;
  final bool askName, askPhone;
  final String initialPhone;

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  late final _phone = TextEditingController(text: widget.initialPhone);
  final _pin = TextEditingController(text: randomPin());

  @override
  void dispose() {
    for (final c in [_name, _phone, _pin]) {
      c.dispose();
    }
    super.dispose();
  }

  void _ok() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop<_LoginInput>(
        context, (name: _name.text.trim(), phone: normalizePhone(_phone.text), pin: _pin.text.trim()));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (widget.askName) ...[
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: tr('s2_name')),
                  validator: (v) => (v ?? '').trim().isEmpty ? tr('required') : null,
                ),
                const SizedBox(height: 12),
              ],
              if (widget.askPhone) ...[
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                  decoration: InputDecoration(labelText: tr('phone'), prefixIcon: const Icon(Icons.phone)),
                  validator: (v) => normalizePhone(v ?? '').length == 10 ? null : tr('s2_phone_10'),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _pin,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(fontSize: 28, letterSpacing: 8, fontWeight: FontWeight.bold),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                decoration: InputDecoration(labelText: tr('pin')),
                validator: (v) => RegExp(r'^\d{6}$').hasMatch(v ?? '') ? null : tr('s2_pin_6'),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _pin.text = randomPin()),
                  icon: const Icon(Icons.casino_outlined),
                  label: Text(tr('s2_random_pin')),
                ),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('cancel'))),
          FilledButton(onPressed: _ok, child: Text(tr('save'))),
        ],
      );
}

/// Shows the new PIN with WhatsApp / copy so the owner can send it.
class _PinReadyDialog extends StatelessWidget {
  const _PinReadyDialog({required this.name, required this.phone, required this.pin});
  final String name, phone, pin;

  String get _message => tr('s2_login_message', {'name': name, 'phone': phone, 'pin': pin});

  @override
  Widget build(BuildContext context) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: kGood, size: 48),
        title: Text(tr('s2_login_ready')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('s2_share_pin_help')),
          const SizedBox(height: 12),
          InfoRow(tr('s2_name'), name),
          InfoRow(tr('phone'), phone),
          const SizedBox(height: 8),
          Center(
            child: SelectableText(pin,
                style: const TextStyle(fontSize: 36, letterSpacing: 10, fontWeight: FontWeight.bold)),
          ),
        ]),
        actionsOverflowButtonSpacing: 8,
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _message));
              if (context.mounted) showMessage(context, tr('s2_copied'));
            },
            icon: const Icon(Icons.copy),
            label: Text(tr('s2_copy')),
          ),
          FilledButton.icon(
            onPressed: () => openUri(whatsappUri(phone, _message)),
            icon: const Icon(Icons.chat),
            label: Text(tr('s2_send_whatsapp')),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('done'))),
        ],
      );
}

/// Everyone currently staying (from live tenancies), to pick who gets a login.
class _PickTenantPage extends StatelessWidget {
  const _PickTenantPage({required this.hasLogin});
  final Set<String> hasLogin;

  Future<List<(String, Json)>> _load() async {
    final api = KirayaApi.instance;
    final ts = await api.tenancySummaries();
    final occs = await Future.wait(ts.map((t) => api.occupants(t['tenancy_id'] as String)));
    return [
      for (var i = 0; i < ts.length; i++)
        for (final o in occs[i])
          if (o['left_on'] == null && o['tenant'] != null) ('${ts[i]['room_number']}', Json.from(o['tenant'] as Map)),
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('s2_pick_person'))),
        body: Loader<List<(String, Json)>>(
          load: _load,
          builder: (context, rows, _) {
            if (rows.isEmpty) return ListView(children: [EmptyState(text: tr('s2_no_tenants_now'))]);
            return ListView(children: [
              for (final (room, p) in rows)
                ListTile(
                  leading: CircleAvatar(child: Text(room, style: const TextStyle(fontSize: 12))),
                  title: Text('${p['full_name'] ?? '-'}'),
                  subtitle: Text('${tr('room_n', {'n': room})} · ${p['phone'] ?? tr('s2_no_phone')}'),
                  enabled: !hasLogin.contains(p['id']),
                  trailing: hasLogin.contains(p['id'])
                      ? StatusChip(tr('s2_has_login'), color: kGood)
                      : const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, p),
                ),
            ]);
          },
        ),
      );
}
