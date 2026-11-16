import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

/// Small bottom-sheet forms used from the tenancy screen. Each returns true when something was saved.

Future<bool?> _sheet(BuildContext context, String title, List<Widget> Function(StateSetter set) fields,
    Future<void> Function() onSave) {
  final form = GlobalKey<FormState>();
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
      child: StatefulBuilder(
        builder: (c, set) => Form(
          key: form,
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(20), children: [
            Text(title, style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 16),
            ...fields(set),
            const SizedBox(height: 20),
            BigButton(
              label: tr('save'),
              icon: Icons.check,
              onPressed: () async {
                if (!form.currentState!.validate()) return;
                final ok = await runBusy(c, () async {
                  await onSave();
                  return true;
                });
                if (ok == true && c.mounted) {
                  Navigator.pop(c, true);
                }
              },
            ),
          ]),
        ),
      ),
    ),
  );
}

const quickCharges = <String, num>{'Fan': 420, 'Cooler': 500, 'Medicine': 120, 'Repair': 0};

Future<bool?> showChargeDialog(BuildContext context, String tenancyId) {
  final label = TextEditingController();
  final amount = TextEditingController();
  var recurring = false;
  var date = todayIst();
  return _sheet(
    context,
    tr('add_charge'),
    (set) => [
      Wrap(spacing: 8, children: [
        for (final e in quickCharges.entries)
          ActionChip(
            label: Text(e.key),
            onPressed: () => set(() {
              label.text = e.key;
              if (e.value > 0) amount.text = '${e.value}';
            }),
          ),
      ]),
      const SizedBox(height: 12),
      TextFormField(
        controller: label,
        decoration: InputDecoration(labelText: tr('charge_name')),
        validator: (v) => (v ?? '').trim().isEmpty ? tr('required') : null,
      ),
      const SizedBox(height: 12),
      NumberField(controller: amount, label: tr('amount'), prefix: '₹ ', decimal: true, allowNegative: true),
      const SizedBox(height: 12),
      SegmentedButton<bool>(
        segments: [
          ButtonSegment(value: false, label: Text(tr('charge_once'))),
          ButtonSegment(value: true, label: Text(tr('charge_monthly'))),
        ],
        selected: {recurring},
        onSelectionChanged: (v) => set(() => recurring = v.first),
      ),
      const SizedBox(height: 12),
      DateField(label: tr('date'), value: date, onChanged: (d) => set(() => date = d)),
    ],
    () => KirayaApi.instance.addCharge(tenancyId, label.text.trim(), toNum(amount.text.trim()),
        kind: recurring ? 'RECURRING' : 'ONE_OFF', start: date),
  );
}

Future<bool?> showAdjustDialog(BuildContext context, String tenancyId) {
  final amount = TextEditingController();
  final reason = TextEditingController();
  var add = true;
  var date = todayIst();
  return _sheet(
    context,
    tr('adjust'),
    (set) => [
      Text(tr('adjust_help')),
      const SizedBox(height: 12),
      SegmentedButton<bool>(
        segments: [
          ButtonSegment(value: true, icon: const Icon(Icons.add), label: Text(tr('debit'))),
          ButtonSegment(value: false, icon: const Icon(Icons.remove), label: Text(tr('credit'))),
        ],
        selected: {add},
        onSelectionChanged: (v) => set(() => add = v.first),
      ),
      const SizedBox(height: 12),
      NumberField(controller: amount, label: tr('amount'), prefix: '₹ ', decimal: true),
      const SizedBox(height: 12),
      TextFormField(
        controller: reason,
        decoration: InputDecoration(labelText: tr('reason')),
        validator: (v) => (v ?? '').trim().isEmpty ? tr('required') : null,
      ),
      const SizedBox(height: 12),
      DateField(label: tr('date'), value: date, onChanged: (d) => set(() => date = d)),
    ],
    () {
      final a = toNum(amount.text.trim()).abs();
      return KirayaApi.instance.adjust(tenancyId, add ? a : -a, reason.text.trim(), date);
    },
  );
}

Future<bool?> showRentDialog(BuildContext context, String tenancyId, Object? current) {
  final amount = TextEditingController(text: '${toNum(current)}');
  return _sheet(
    context,
    tr('edit_rent'),
    (set) => [NumberField(controller: amount, label: tr('monthly_rent'), prefix: '₹ ', decimal: true, autofocus: true)],
    () => KirayaApi.instance.updateTenancy(tenancyId, {'monthly_rent': toNum(amount.text.trim())}),
  );
}

/// Owner records the tenant's notice to leave. Shows how many days short it is.
Future<bool?> showNoticeDialog(BuildContext context, Json summary, Json settings) {
  final period = toNum(settings['notice_period_days'] ?? 30).toInt();
  var given = todayIst();
  var leave = todayIst().add(Duration(days: period));
  final note = TextEditingController();
  return _sheet(
    context,
    tr('give_notice'),
    (set) {
      final short = period - leave.difference(given).inDays;
      final suggested = (toNum(summary['monthly_rent']) * (short > 0 ? short : 0) / 30).round();
      return [
        DateField(label: tr('date'), value: given, onChanged: (d) => set(() => given = d)),
        const SizedBox(height: 12),
        DateField(label: tr('leave_date'), value: leave, first: given, onChanged: (d) => set(() => leave = d)),
        const SizedBox(height: 12),
        Text(short > 0 ? tr('notice_short', {'d': short, 'a': rupees(suggested)}) : tr('notice_ok'),
            style: TextStyle(color: short > 0 ? kWarn : kGood, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        TextField(controller: note, decoration: InputDecoration(labelText: tr('note'))),
      ];
    },
    () => KirayaApi.instance.giveNotice(summary['tenancy_id'] as String, leave,
        givenOn: given, note: note.text.trim().isEmpty ? null : note.text.trim()),
  );
}
