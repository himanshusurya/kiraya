import 'package:flutter/services.dart';
import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

import 'person_form.dart';

/// property_id of the signed-in owner (needed when inserting rooms / notices).
Future<String> ownerPropertyId() async {
  final me = await KirayaAuth.me();
  final id = me?['property_id'];
  if (id == null) throw Exception(tr('s2_login_again'));
  return id as String;
}

enum _Kind { money, days, text, phone, longText }

/// key, kind, decimal, ask "from date"
const _moneySettings = [
  ('electricity_rate', _Kind.money, true, true),
  ('cleaning_charge', _Kind.money, false, false),
  ('default_advance', _Kind.money, false, false),
  ('late_fee', _Kind.money, false, false),
];
const _daySettings = [
  ('due_after_bill_days', _Kind.days, false, false),
  ('grace_days', _Kind.days, false, false),
  ('notice_period_days', _Kind.days, false, false),
  ('meter_reading_day', _Kind.days, false, false),
];
const _payInfoSettings = [
  ('upi_id', _Kind.text, false, false),
  ('upi_name', _Kind.text, false, false),
  ('owner_phone', _Kind.phone, false, false),
];
const _messageSettings = [
  ('reminder_en', _Kind.longText, false, false),
  ('reminder_hi', _Kind.longText, false, false),
];

const kRoomStatuses = ['VACANT', 'OCCUPIED', 'OWNER_USE', 'MAINTENANCE'];

Color roomStatusColor(String? s) => switch (s) {
      'VACANT' => kGood,
      'OCCUPIED' => Colors.blueGrey,
      'MAINTENANCE' => kWarn,
      _ => Colors.grey,
    };

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

typedef _SettingsData = ({Json settings, List<Json> rooms});

class _SettingsScreenState extends State<SettingsScreen> {
  final _loader = GlobalKey<LoaderState<_SettingsData>>();
  final _api = KirayaApi.instance;

  Future<_SettingsData> _load() async {
    final r = await Future.wait<Object>([_api.settings(), _api.rooms()]);
    return (settings: r[0] as Json, rooms: r[1] as List<Json>);
  }

  Future<void> _reload() async => _loader.currentState?.reload();

  String _display(_Kind kind, Object? v) {
    if (v == null || v.toString().isEmpty) return tr('s2_not_set');
    return switch (kind) {
      _Kind.money => rupees(v),
      _Kind.days => numText(v),
      _ => v.toString(),
    };
  }

  Future<void> _save(String key, Object? value, [DateTime? from]) async {
    final ok = await runBusy(context, () async {
      await _api.updateSetting(key, value, from);
      return true;
    },
        success: from != null && from != todayIst()
            ? tr('s2_saved_from', {'d': fmtDate(from)})
            : tr('saved'));
    if (ok == true) await _reload();
  }

  Future<void> _edit((String, _Kind, bool, bool) s, Object? current) async {
    final (key, kind, decimal, withDate) = s;
    final r = await showDialog<(Object, DateTime?)>(
      context: context,
      builder: (_) => _SettingDialog(
        title: tr('s2_set_$key'),
        help: tr('s2_set_${key}_help'),
        kind: kind,
        decimal: decimal,
        withDate: withDate,
        initial: kind == _Kind.money || kind == _Kind.days ? numText(current) : (current ?? '').toString(),
        settingKey: key,
      ),
    );
    if (r == null || !mounted) return;
    await _save(key, r.$1, r.$2);
  }

  Widget _tile(Json settings, (String, _Kind, bool, bool) s) {
    final (key, kind, _, _) = s;
    final v = settings[key];
    final long = kind == _Kind.longText || kind == _Kind.text;
    return ListTile(
      title: Text(tr('s2_set_$key')),
      subtitle: Text(long ? '${tr('s2_set_${key}_help')}\n${_display(kind, v)}' : tr('s2_set_${key}_help')),
      isThreeLine: long,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (!long)
          Text(_display(kind, v),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(width: 4),
        const Icon(Icons.edit, size: 20),
      ]),
      onTap: () => _edit(s, v),
    );
  }

  Future<void> _editRoom([Json? room]) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _RoomPage(room: room)));
    if (saved == true) await _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('settings'))),
        body: Loader<_SettingsData>(
          key: _loader,
          load: _load,
          builder: (context, data, _) {
            final s = data.settings;
            final lang = (s['language_default'] ?? 'en').toString();
            return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
              SectionTitle(tr('s2_sec_money')),
              for (final x in _moneySettings) _tile(s, x),
              SectionTitle(tr('s2_sec_dates')),
              for (final x in _daySettings) _tile(s, x),
              SwitchListTile(
                title: Text(tr('s2_set_auto_issue')),
                subtitle: Text(tr('s2_set_auto_issue_help')),
                value: s['auto_issue'] == true,
                onChanged: (v) => _save('auto_issue', v),
              ),
              SectionTitle(tr('s2_sec_payment_info')),
              for (final x in _payInfoSettings) _tile(s, x),
              SectionTitle(tr('s2_sec_messages')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(tr('s2_placeholder_help'), style: Theme.of(context).textTheme.bodyMedium),
              ),
              for (final x in _messageSettings) _tile(s, x),
              SectionTitle(tr('s2_set_language_default')),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('s2_set_language_default_help')),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    for (final l in const ['en', 'hi'])
                      ChoiceChip(
                        label: Text(l == 'en' ? tr('english') : tr('hindi')),
                        selected: lang == l,
                        onSelected: (_) => lang == l ? null : _save('language_default', l),
                      ),
                  ]),
                ]),
              ),
              SectionTitle(
                tr('s2_rooms'),
                trailing: TextButton.icon(
                    onPressed: () => _editRoom(), icon: const Icon(Icons.add), label: Text(tr('s2_add_room'))),
              ),
              if (data.rooms.isEmpty) EmptyState(text: tr('s2_no_rooms'), icon: Icons.meeting_room_outlined),
              for (final r in data.rooms)
                ListTile(
                  leading: CircleAvatar(child: Text('${r['number']}', style: const TextStyle(fontSize: 12))),
                  title: Text(tr('room_n', {'n': r['number']})),
                  subtitle: Text([
                    floorLabel(r['floor']),
                    if (r['default_rent'] != null) '${tr('rent')} ${rupees(r['default_rent'])}',
                    if (r['has_meter'] == false) tr('s2_no_meter'),
                  ].where((e) => e.isNotEmpty).join(' · ')),
                  trailing: StatusChip(tr('s2_rstatus_${r['status']}'), color: roomStatusColor(r['status'] as String?)),
                  onTap: () => _editRoom(r),
                ),
            ]);
          },
        ),
      );
}

String floorLabel(Object? floor) {
  if (floor == null) return '';
  final f = toNum(floor).toInt();
  return f == 0 ? tr('s2_ground_floor') : tr('s2_floor_n', {'n': f});
}

class _SettingDialog extends StatefulWidget {
  const _SettingDialog({
    required this.title,
    required this.help,
    required this.kind,
    required this.decimal,
    required this.withDate,
    required this.initial,
    required this.settingKey,
  });
  final String title, help, initial, settingKey;
  final _Kind kind;
  final bool decimal, withDate;

  @override
  State<_SettingDialog> createState() => _SettingDialogState();
}

class _SettingDialogState extends State<_SettingDialog> {
  final _form = GlobalKey<FormState>();
  late final _c = TextEditingController(text: widget.initial);
  DateTime _from = todayIst();

  bool get _numeric => widget.kind == _Kind.money || widget.kind == _Kind.days;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String? _validate(String? v) {
    final s = (v ?? '').trim();
    if (_numeric) {
      final n = num.tryParse(s);
      if (n == null || n < 0) return tr('invalid_number');
      if (widget.settingKey == 'meter_reading_day' && (n < 1 || n > 28)) return tr('s2_day_1_28');
      return null;
    }
    if (widget.kind == _Kind.phone && s.isNotEmpty && normalizePhone(s).length != 10) return tr('s2_phone_10');
    return null;
  }

  void _ok() {
    if (!_form.currentState!.validate()) return;
    final s = _c.text.trim();
    final Object value = switch (widget.kind) {
      _Kind.money || _Kind.days => (() {
          final n = num.parse(s);
          return n == n.roundToDouble() && !widget.decimal ? n.toInt() : n;
        })(),
      _Kind.phone => normalizePhone(s),
      _ => s,
    };
    Navigator.pop(context, (value, widget.withDate ? _from : null));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(widget.help),
              const SizedBox(height: 12),
              TextFormField(
                controller: _c,
                autofocus: true,
                minLines: widget.kind == _Kind.longText ? 3 : 1,
                maxLines: widget.kind == _Kind.longText ? 6 : 1,
                keyboardType: _numeric
                    ? TextInputType.numberWithOptions(decimal: widget.decimal)
                    : (widget.kind == _Kind.phone ? TextInputType.phone : TextInputType.text),
                inputFormatters: _numeric ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : null,
                decoration: InputDecoration(prefixText: widget.kind == _Kind.money ? '₹ ' : null),
                validator: _validate,
              ),
              if (widget.kind == _Kind.longText) ...[
                const SizedBox(height: 8),
                Text(tr('s2_placeholder_help'), style: Theme.of(context).textTheme.bodySmall),
              ],
              if (widget.withDate) ...[
                const SizedBox(height: 16),
                DateField(label: tr('s2_from_date'), value: _from, onChanged: (d) => setState(() => _from = d)),
                const SizedBox(height: 4),
                Text(tr('s2_from_date_help'), style: Theme.of(context).textTheme.bodySmall),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('cancel'))),
          FilledButton(onPressed: _ok, child: Text(tr('save'))),
        ],
      );
}

/// Add or edit one room.
class _RoomPage extends StatefulWidget {
  const _RoomPage({this.room});
  final Json? room;

  @override
  State<_RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<_RoomPage> {
  final _form = GlobalKey<FormState>();
  late final _number = TextEditingController(text: '${widget.room?['number'] ?? ''}');
  late final _floor = TextEditingController(text: numText(widget.room?['floor']));
  late final _rent = TextEditingController(text: numText(widget.room?['default_rent']));
  late final _notes = TextEditingController(text: '${widget.room?['notes'] ?? ''}');
  late String _status = (widget.room?['status'] ?? 'VACANT') as String;
  late bool _hasMeter = widget.room?['has_meter'] != false;

  bool get _isNew => widget.room == null;

  @override
  void dispose() {
    for (final c in [_number, _floor, _rent, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final values = <String, dynamic>{
      'number': _number.text.trim(),
      'floor': int.tryParse(_floor.text.trim()),
      'default_rent': num.tryParse(_rent.text.trim()),
      'has_meter': _hasMeter,
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      if (_status != 'OCCUPIED') 'status': _status,
    };
    final ok = await runBusy(context, () async {
      if (_isNew) {
        await KirayaApi.instance.addRoom({...values, 'property_id': await ownerPropertyId()});
      } else {
        await KirayaApi.instance.updateRoom(widget.room!['id'] as String, values);
      }
      return true;
    }, success: tr('saved'));
    if (ok == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(_isNew ? tr('s2_add_room') : tr('s2_edit_room', {'n': widget.room!['number']}))),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            TextFormField(
              controller: _number,
              decoration: InputDecoration(labelText: tr('s2_room_number')),
              validator: (v) => (v ?? '').trim().isEmpty ? tr('required') : null,
            ),
            const SizedBox(height: 16),
            NumberField(controller: _floor, label: tr('s2_floor'), required: false, helper: tr('s2_floor_help')),
            const SizedBox(height: 16),
            NumberField(controller: _rent, label: tr('s2_default_rent'), prefix: '₹ ', required: false),
            const SizedBox(height: 16),
            Text(tr('s2_room_status'), style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 6),
            if (_status == 'OCCUPIED')
              Text(tr('s2_occupied_help'))
            else
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final s in kRoomStatuses.where((s) => s != 'OCCUPIED'))
                  ChoiceChip(
                    label: Text(tr('s2_rstatus_$s')),
                    selected: _status == s,
                    onSelected: (_) => setState(() => _status = s),
                  ),
              ]),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('s2_has_meter')),
              subtitle: Text(tr('s2_has_meter_help')),
              value: _hasMeter,
              onChanged: (v) => setState(() => _hasMeter = v),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notes,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: tr('note')),
            ),
          ]),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: BigButton(label: tr('save'), icon: Icons.check, onPressed: _save),
          ),
        ),
      );
}
