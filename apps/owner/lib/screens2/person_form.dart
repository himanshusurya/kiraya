import 'package:flutter/services.dart';
import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

/// Free-text `tenant` columns edited by [PersonForm] (mirrors the paper renter form).
const kPersonTextFields = [
  'full_name',
  'father_name',
  'phone',
  'alt_phone',
  'email',
  'occupation',
  'workplace',
  'caste',
  'religion',
  'permanent_address',
  'native_police_station',
  'id_number',
  'vehicle_number',
  'emergency_name',
  'emergency_phone',
  'notes',
];

/// Every `tenant` column [PersonForm] can emit.
const kPersonFields = [...kPersonTextFields, 'dob', 'age', 'gender', 'id_type'];

const kGenders = ['MALE', 'FEMALE', 'OTHER'];
const kIdTypes = ['AADHAAR', 'PAN', 'DL', 'VOTER', 'PASSPORT', 'OTHER'];
const _phoneFields = {'phone', 'alt_phone', 'emergency_phone'};

/// Name and a 10-digit mobile number are the only must-haves.
bool isPersonValid(Json p) =>
    (p['full_name'] ?? '').toString().trim().isNotEmpty && normalizePhone((p['phone'] ?? '').toString()).length == 10;

/// 1200 -> "1200", 12.5 -> "12.5", null -> "".
String numText(Object? v) {
  if (v == null || v.toString().isEmpty) return '';
  final n = toNum(v);
  return n == n.roundToDouble() ? n.round().toString() : n.toString();
}

/// Label for a tenant column, used by the detail screens.
String personFieldLabel(String key) => tr('s2_f_$key');

/// Display text for a tenant column value.
String personFieldValue(String key, Object? v) {
  if (v == null) return '';
  final s = v.toString();
  if (key == 'dob') return fmtDate(v);
  if (key == 'gender' && kGenders.contains(s)) return tr('s2_gender_$s');
  if (key == 'id_type' && kIdTypes.contains(s)) return tr('s2_id_$s');
  return s;
}

/// The renter form. Name + phone are required; the rest is optional and grouped.
/// Emits a Json of tenant columns with empty values left out.
class PersonForm extends StatefulWidget {
  const PersonForm({super.key, this.initial, required this.onChanged});
  final Json? initial;
  final ValueChanged<Json> onChanged;

  @override
  State<PersonForm> createState() => _PersonFormState();
}

class _PersonFormState extends State<PersonForm> {
  late final Map<String, TextEditingController> _c = {
    for (final k in [...kPersonTextFields, 'age']) k: TextEditingController(text: _initialText(k)),
  };
  DateTime? _dob;
  String? _gender;
  String? _idType;

  String _initialText(String k) {
    final v = widget.initial?[k];
    if (v == null) return '';
    return k == 'age' ? numText(v) : v.toString();
  }

  @override
  void initState() {
    super.initState();
    _dob = toDate(widget.initial?['dob']);
    _gender = widget.initial?['gender']?.toString();
    _idType = widget.initial?['id_type']?.toString();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _emit();
    });
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Json get _value {
    final m = <String, dynamic>{};
    for (final k in kPersonTextFields) {
      final v = _c[k]!.text.trim();
      if (v.isNotEmpty) m[k] = _phoneFields.contains(k) ? normalizePhone(v) : v;
    }
    final age = int.tryParse(_c['age']!.text.trim());
    if (age != null) m['age'] = age;
    if (_dob != null) m['dob'] = isoDate(_dob!);
    if (_gender != null && _gender!.isNotEmpty) m['gender'] = _gender;
    if (_idType != null && _idType!.isNotEmpty) m['id_type'] = _idType;
    return m;
  }

  void _emit() => widget.onChanged(_value);

  String? _phoneCheck(String? v, {bool required = false}) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return required ? tr('required') : null;
    return normalizePhone(s).length == 10 ? null : tr('s2_phone_10');
  }

  Widget _text(
    String key, {
    bool required = false,
    bool phone = false,
    bool number = false,
    int maxLines = 1,
    TextInputType? type,
    TextCapitalization cap = TextCapitalization.words,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          key: Key('pf_$key'),
          controller: _c[key],
          minLines: 1,
          maxLines: maxLines,
          keyboardType: phone ? TextInputType.phone : (number ? TextInputType.number : type),
          textCapitalization: phone || number ? TextCapitalization.none : cap,
          inputFormatters: phone
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')), LengthLimitingTextInputFormatter(14)]
              : (number ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)] : null),
          decoration: InputDecoration(
            labelText: personFieldLabel(key) + (required ? ' *' : ''),
            prefixIcon: phone ? const Icon(Icons.phone) : null,
          ),
          validator: phone
              ? (v) => _phoneCheck(v, required: required)
              : (required ? (v) => (v ?? '').trim().isEmpty ? tr('required') : null : null),
          onChanged: (_) => _emit(),
        ),
      );

  Widget _chips(String labelKey, List<String> values, String prefix, String? selected, ValueChanged<String?> onPick) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(labelKey), style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final v in values)
              ChoiceChip(
                label: Text(tr('$prefix$v')),
                selected: selected == v,
                onSelected: (on) {
                  onPick(on ? v : null);
                  _emit();
                },
              ),
          ]),
        ]),
      );

  Future<void> _pickDob() async {
    final today = todayIst();
    final d = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(today.year - 25),
      firstDate: DateTime(1920),
      lastDate: today,
      initialDatePickerMode: DatePickerMode.year,
    );
    if (d == null || !mounted) return;
    var age = today.year - d.year;
    if (today.month < d.month || (today.month == d.month && today.day < d.day)) age--;
    setState(() {
      _dob = d;
      _c['age']!.text = '$age';
    });
    _emit();
  }

  Widget _group(String titleKey, IconData icon, List<String> keys, List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ExpansionTile(
          leading: Icon(icon),
          title: Text(tr(titleKey)),
          initiallyExpanded: keys.any((k) => (widget.initial?[k]?.toString() ?? '').isNotEmpty),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          children: children,
        ),
      );

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _text('full_name', required: true),
        _text('phone', required: true, phone: true),
        _text('father_name'),
        _chips('s2_f_gender', kGenders, 's2_gender_', _gender, (v) => setState(() => _gender = v)),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: _pickDob,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: personFieldLabel('dob'),
                    suffixIcon: _dob == null
                        ? const Icon(Icons.calendar_month)
                        : IconButton(
                            tooltip: tr('remove'),
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() => _dob = null);
                              _emit();
                            },
                          ),
                  ),
                  child: Text(_dob == null ? tr('s2_optional') : fmtDate(_dob)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: _text('age', number: true)),
        ]),
        _text('occupation'),
        _text('workplace'),
        const SizedBox(height: 4),
        _group('s2_group_id', Icons.badge_outlined, ['id_type', 'id_number'], [
          _chips('s2_f_id_type', kIdTypes, 's2_id_', _idType, (v) => setState(() => _idType = v)),
          _text('id_number', cap: TextCapitalization.characters),
        ]),
        _group('s2_group_address', Icons.home_outlined, ['permanent_address', 'native_police_station'], [
          _text('permanent_address', maxLines: 4, cap: TextCapitalization.sentences),
          _text('native_police_station'),
        ]),
        _group('s2_group_emergency', Icons.contact_phone_outlined, ['emergency_name', 'emergency_phone'], [
          _text('emergency_name'),
          _text('emergency_phone', phone: true),
        ]),
        _group('s2_group_other', Icons.more_horiz,
            ['alt_phone', 'email', 'caste', 'religion', 'vehicle_number', 'notes'], [
          _text('alt_phone', phone: true),
          _text('email', type: TextInputType.emailAddress, cap: TextCapitalization.none),
          _text('caste'),
          _text('religion'),
          _text('vehicle_number', cap: TextCapitalization.characters),
          _text('notes', maxLines: 4, cap: TextCapitalization.sentences),
        ]),
      ]);
}
