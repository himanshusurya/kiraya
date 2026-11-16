import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

import 'people_screen.dart';
import 'person_form.dart';

/// New tenant in an empty room: Stay → People → Extra charges → Review & Save.
/// Pops with the new tenancy id.
class OnboardScreen extends StatefulWidget {
  const OnboardScreen({super.key, required this.room});

  /// A `v_room_board` row (room_id, number, default_rent, last_reading, last_reading_date …).
  final Json room;

  @override
  State<OnboardScreen> createState() => _OnboardScreenState();
}

class _Person {
  _Person(this.id);
  final int id;
  Json data = {};
  bool app = false;
}

class _Charge {
  _Charge(String label, String amount, this.recurring)
      : label = TextEditingController(text: label),
        amount = TextEditingController(text: amount);
  final TextEditingController label, amount;
  bool recurring;

  void dispose() {
    label.dispose();
    amount.dispose();
  }
}

/// Quick-add chips: (string key, amount, monthly?).
const _presets = [
  ('s2_preset_fan', 420, true),
  ('s2_preset_cooler', 500, true),
  ('s2_preset_tv', 200, true),
  ('s2_preset_fridge', 300, true),
  ('s2_preset_medicine', 0, false),
  ('s2_preset_discount', 0, true),
];

class _OnboardScreenState extends State<OnboardScreen> {
  static const _stepKeys = ['s2_step_stay', 's2_step_people', 's2_step_charges', 's2_step_review'];
  final _forms = List.generate(3, (_) => GlobalKey<FormState>());
  int _step = 0;

  DateTime _start = todayIst();
  DateTime _advDate = todayIst();
  bool _advDateTouched = false;
  late final _rent = TextEditingController(text: numText(widget.room['default_rent'] ?? widget.room['monthly_rent']));
  final _advance = TextEditingController();
  late final _reading = TextEditingController(text: numText(widget.room['last_reading']));
  final _opening = TextEditingController();
  final _dueDays = TextEditingController();
  final _grace = TextEditingController();
  final _lateFee = TextEditingController();
  final _notes = TextEditingController();
  Json _settings = {};

  int _nextId = 0;
  late final List<_Person> _people = [_Person(_nextId++)];
  final List<_Charge> _charges = [];

  @override
  void initState() {
    super.initState();
    _loadDefaults();
  }

  Future<void> _loadDefaults() async {
    try {
      final s = await KirayaApi.instance.settings();
      if (!mounted) return;
      setState(() {
        _settings = s;
        if (_advance.text.isEmpty) _advance.text = numText(s['default_advance']);
      });
    } catch (_) {
      // Defaults are only a convenience; the owner can type the values.
    }
  }

  @override
  void dispose() {
    for (final c in [_rent, _advance, _reading, _opening, _dueDays, _grace, _lateFee, _notes]) {
      c.dispose();
    }
    for (final c in _charges) {
      c.dispose();
    }
    super.dispose();
  }

  String get _roomNo => '${widget.room['number'] ?? ''}';
  num? _num(TextEditingController c) => num.tryParse(c.text.trim());

  bool _validateStep() {
    if (_step >= 3) return true;
    if (!(_forms[_step].currentState?.validate() ?? true)) {
      showMessage(context, tr('s2_fix_red'), error: true);
      return false;
    }
    if (_step == 1 && !_people.every((p) => isPersonValid(p.data))) {
      showMessage(context, tr('s2_name_phone_needed'), error: true);
      return false;
    }
    return true;
  }

  void _next() {
    if (!_validateStep()) return;
    FocusScope.of(context).unfocus();
    setState(() => _step++);
  }

  void _back() {
    FocusScope.of(context).unfocus();
    setState(() => _step--);
  }

  Json _payload() {
    final reading = _num(_reading);
    final opening = _num(_opening);
    final due = int.tryParse(_dueDays.text.trim());
    final grace = int.tryParse(_grace.text.trim());
    final late = _num(_lateFee);
    return {
      'room_id': widget.room['room_id'] ?? widget.room['id'],
      'start_date': isoDate(_start),
      'monthly_rent': _num(_rent) ?? 0,
      'advance_amount': _num(_advance) ?? 0,
      'advance_date': isoDate(_advDate),
      'move_in_reading': ?reading,
      if (opening != null && opening != 0) 'opening_balance': opening,
      'due_after_days': ?due,
      'grace_days': ?grace,
      'late_fee': ?late,
      if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
      'tenants': [
        for (var i = 0; i < _people.length; i++) {..._people[i].data, 'is_primary': i == 0, 'app_access': _people[i].app},
      ],
      'charges': [
        for (final c in _charges)
          if (c.label.text.trim().isNotEmpty && (_num(c.amount) ?? 0) != 0)
            {'label': c.label.text.trim(), 'amount': _num(c.amount), 'kind': c.recurring ? 'RECURRING' : 'ONE_OFF'},
      ],
    };
  }

  Future<void> _save() async {
    final mainName = '${_people.first.data['full_name'] ?? ''}';
    final id = await runBusy(context, () => KirayaApi.instance.onboard(_payload()), success: tr('s2_onboard_done'));
    if (id == null || !mounted) return;
    final addPhotos = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text(tr('s2_id_photos')),
        content: Text(tr('s2_ask_id_photos', {'name': mainName})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('later'))),
          FilledButton.icon(
            onPressed: () => Navigator.pop(c, true),
            icon: const Icon(Icons.add_a_photo),
            label: Text(tr('s2_add_photos_now')),
          ),
        ],
      ),
    );
    if (addPhotos == true && mounted) {
      final occ = await runBusy(context, () => KirayaApi.instance.occupants(id));
      if (occ != null && occ.isNotEmpty && mounted) {
        final main = occ.firstWhere((o) => o['is_primary'] == true, orElse: () => occ.first);
        await Navigator.push(
            context, MaterialPageRoute<void>(builder: (_) => PersonDetailScreen(tenantId: main['tenant_id'] as String)));
      }
    }
    if (mounted) Navigator.pop(context, id);
  }

  // ---------------- steps ----------------
  static const _gap = SizedBox(height: 16);

  Widget _small(String text) => Padding(
        padding: const EdgeInsets.only(top: 4, left: 4),
        child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  String _settingHint(String key, {bool money = false}) {
    final v = _settings[key];
    if (v == null) return tr('s2_blank_uses_setting');
    return tr('s2_blank_uses_value', {'v': money ? rupees(v) : numText(v)});
  }

  Widget _stayStep() {
    final last = widget.room['last_reading'];
    return ListView(padding: const EdgeInsets.all(16), children: [
      DateField(
        label: tr('s2_start_date'),
        value: _start,
        onChanged: (d) => setState(() {
          _start = d;
          if (!_advDateTouched) _advDate = d;
        }),
      ),
      _small(tr('s2_start_help')),
      _gap,
      NumberField(controller: _rent, label: tr('s2_monthly_rent'), prefix: '₹ '),
      _gap,
      NumberField(
          controller: _advance,
          label: tr('s2_advance_amount'),
          prefix: '₹ ',
          required: false,
          helper: tr('s2_advance_help')),
      _gap,
      DateField(
        label: tr('s2_advance_date'),
        value: _advDate,
        onChanged: (d) => setState(() {
          _advDate = d;
          _advDateTouched = true;
        }),
      ),
      _gap,
      NumberField(
        controller: _reading,
        label: tr('s2_move_in_reading'),
        decimal: true,
        required: false,
        helper: last == null
            ? tr('s2_reading_help')
            : tr('s2_last_reading_was', {'v': numText(last), 'd': fmtDate(widget.room['last_reading_date'])}),
      ),
      _gap,
      NumberField(
        controller: _opening,
        label: tr('s2_opening_balance'),
        prefix: '₹ ',
        required: false,
        allowNegative: true,
        helper: tr('s2_opening_help'),
      ),
      const SizedBox(height: 8),
      Card(
        margin: EdgeInsets.zero,
        child: ExpansionTile(
          leading: const Icon(Icons.tune),
          title: Text(tr('s2_more_options')),
          subtitle: Text(tr('s2_more_options_help')),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            NumberField(
                controller: _dueDays,
                label: tr('s2_due_after_days'),
                required: false,
                helper: _settingHint('due_after_bill_days')),
            _gap,
            NumberField(
                controller: _grace, label: tr('s2_grace_days'), required: false, helper: _settingHint('grace_days')),
            _gap,
            NumberField(
                controller: _lateFee,
                label: tr('s2_late_fee'),
                prefix: '₹ ',
                required: false,
                helper: _settingHint('late_fee', money: true)),
            _gap,
            TextFormField(
              controller: _notes,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: tr('note')),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _peopleStep() => ListView(padding: const EdgeInsets.all(12), children: [
        for (final (i, person) in _people.indexed)
          Card(
            key: ValueKey(person.id),
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Icon(i == 0 ? Icons.star : Icons.person, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(i == 0 ? tr('s2_main_tenant') : tr('s2_person_n', {'n': i + 1}),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  if (i > 0)
                    IconButton(
                      tooltip: tr('remove'),
                      icon: const Icon(Icons.delete_outline, color: kBad),
                      onPressed: () => setState(() => _people.remove(person)),
                    ),
                ]),
                const SizedBox(height: 8),
                PersonForm(initial: person.data, onChanged: (v) => person.data = v),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('s2_give_app_login')),
                  subtitle: Text(tr('s2_give_app_login_help')),
                  value: person.app,
                  onChanged: (v) => setState(() => person.app = v),
                ),
              ]),
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => setState(() => _people.add(_Person(_nextId++))),
          icon: const Icon(Icons.person_add),
          label: Text(tr('s2_add_another_person')),
        ),
      ]);

  Widget _chargesStep() => ListView(padding: const EdgeInsets.all(16), children: [
        Text(tr('s2_charges_help'), style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in _presets)
            ActionChip(
              avatar: const Icon(Icons.add),
              label: Text(p.$2 > 0 ? '${tr(p.$1)} ₹${p.$2}' : tr(p.$1)),
              onPressed: () => setState(() => _charges.add(_Charge(tr(p.$1), p.$2 > 0 ? '${p.$2}' : '', p.$3))),
            ),
        ]),
        const SizedBox(height: 12),
        if (_charges.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(tr('s2_no_charges'))),
        for (final c in _charges)
          Card(
            key: ObjectKey(c),
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: c.label,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(labelText: tr('s2_charge_name')),
                      validator: (v) => (v ?? '').trim().isEmpty ? tr('required') : null,
                    ),
                  ),
                  IconButton(
                    tooltip: tr('remove'),
                    icon: const Icon(Icons.delete_outline, color: kBad),
                    onPressed: () => setState(() {
                      _charges.remove(c);
                      c.dispose();
                    }),
                  ),
                ]),
                const SizedBox(height: 12),
                NumberField(
                    controller: c.amount,
                    label: tr('amount'),
                    prefix: '₹ ',
                    allowNegative: true,
                    helper: tr('s2_discount_help')),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  ChoiceChip(
                    label: Text(tr('s2_every_month')),
                    selected: c.recurring,
                    onSelected: (_) => setState(() => c.recurring = true),
                  ),
                  ChoiceChip(
                    label: Text(tr('s2_one_time')),
                    selected: !c.recurring,
                    onSelected: (_) => setState(() => c.recurring = false),
                  ),
                ]),
              ]),
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => setState(() => _charges.add(_Charge('', '', true))),
          icon: const Icon(Icons.add),
          label: Text(tr('s2_add_other_charge')),
        ),
      ]);

  Widget _reviewStep() {
    final p = _payload();
    final people = (p['tenants'] as List).cast<Json>();
    final charges = (p['charges'] as List).cast<Json>();
    Widget card(String title, List<Widget> rows, int step) => Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ),
                TextButton.icon(
                    onPressed: () => setState(() => _step = step), icon: const Icon(Icons.edit), label: Text(tr('edit'))),
              ]),
              Padding(padding: const EdgeInsets.only(right: 8), child: Column(children: rows)),
            ]),
          ),
        );
    return ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
      card(tr('s2_step_stay'), [
        InfoRow(tr('room'), _roomNo, bold: true),
        InfoRow(tr('s2_start_date'), fmtDate(_start)),
        InfoRow(tr('s2_monthly_rent'), rupees(p['monthly_rent']), bold: true),
        InfoRow(tr('advance'), '${rupees(p['advance_amount'])} · ${fmtDate(_advDate)}'),
        if (p['move_in_reading'] != null) InfoRow(tr('s2_move_in_reading'), numText(p['move_in_reading'])),
        if (p['opening_balance'] != null) InfoRow(tr('s2_opening_balance'), rupees(p['opening_balance'])),
        if (p['due_after_days'] != null) InfoRow(tr('s2_due_after_days'), '${p['due_after_days']}'),
        if (p['grace_days'] != null) InfoRow(tr('s2_grace_days'), '${p['grace_days']}'),
        if (p['late_fee'] != null) InfoRow(tr('s2_late_fee'), rupees(p['late_fee'])),
      ], 0),
      card(tr('s2_step_people'), [
        for (var i = 0; i < people.length; i++)
          InfoRow(
            '${people[i]['full_name'] ?? '-'}${i == 0 ? ' (${tr('s2_main')})' : ''}',
            '${people[i]['phone'] ?? ''}${people[i]['app_access'] == true ? ' · ${tr('s2_app')}' : ''}',
          ),
      ], 1),
      card(tr('s2_step_charges'), [
        if (charges.isEmpty) InfoRow(tr('s2_no_charges_short'), ''),
        for (final c in charges)
          InfoRow('${c['label']}',
              '${rupees(c['amount'])} ${c['kind'] == 'RECURRING' ? tr('s2_per_month') : tr('s2_once')}'),
      ], 2),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Text(tr('s2_review_help'), style: Theme.of(context).textTheme.bodyLarge),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (_step) {
      0 => _stayStep(),
      1 => _peopleStep(),
      2 => _chargesStep(),
      _ => _reviewStep(),
    };
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(tr('s2_onboard_title', {'n': _roomNo}))),
        body: Column(children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.primaryContainer,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('s2_step_of', {'a': _step + 1, 'b': 4}), style: Theme.of(context).textTheme.bodyMedium),
              Text(tr(_stepKeys[_step]),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: (_step + 1) / 4),
            ]),
          ),
          Expanded(child: _step < 3 ? Form(key: _forms[_step], child: body) : body),
        ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(children: [
              if (_step > 0) ...[
                Expanded(child: BigButton(label: tr('back'), icon: Icons.arrow_back, outlined: true, onPressed: _back)),
                const SizedBox(width: 12),
              ],
              Expanded(
                flex: 2,
                child: _step < 3
                    ? BigButton(label: tr('next'), icon: Icons.arrow_forward, onPressed: _next)
                    : BigButton(label: tr('s2_save_tenant'), icon: Icons.check, onPressed: _save),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
