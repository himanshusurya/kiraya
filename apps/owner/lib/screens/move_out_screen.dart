import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

/// Move-out & settlement: final reading, cleaning, short-notice charge (owner decides),
/// other deductions; advance is used first and the rest is refunded or still due.
class MoveOutScreen extends StatefulWidget {
  const MoveOutScreen({super.key, required this.summary, required this.settings});
  final Json summary;
  final Json settings;

  @override
  State<MoveOutScreen> createState() => _MoveOutScreenState();
}

class _Extra {
  final label = TextEditingController();
  final amount = TextEditingController();
}

class _MoveOutScreenState extends State<MoveOutScreen> {
  final _form = GlobalKey<FormState>();
  late DateTime _leave = toDate(widget.summary['leave_on']) ?? todayIst();
  final _reading = TextEditingController();
  late final _cleaning = TextEditingController(text: '${toNum(widget.settings['cleaning_charge'] ?? 500)}');
  final _shortfall = TextEditingController(text: '0');
  final _note = TextEditingController();
  final List<_Extra> _extras = [];
  bool _absconded = false, _waive = false;
  Json? _notice;
  num? _lastReading;

  String get _id => widget.summary['tenancy_id'] as String;

  @override
  void initState() {
    super.initState();
    KirayaApi.instance.activeNotice(_id).then((n) {
      if (mounted) setState(() => _notice = n);
    });
    KirayaApi.instance.roomBoard().then((rooms) {
      final r = rooms.where((x) => x['room_id'] == widget.summary['room_id']);
      if (mounted && r.isNotEmpty) setState(() => _lastReading = toNum(r.first['last_reading']));
    });
  }

  /// Days short and suggested charge (rent/30 per day); owner decides whether to use it.
  (int, num) get _suggestion {
    final period = toNum(widget.settings['notice_period_days'] ?? 30).toInt();
    final given = toDate(_notice?['given_on']);
    final short = given == null ? period : (period - _leave.difference(given).inDays);
    final days = short > 0 ? short : 0;
    return (days, (toNum(widget.summary['monthly_rent']) * days / 30).round());
  }

  Future<void> _settle() async {
    if (!_form.currentState!.validate()) return;
    if (!await confirm(context, '${tr('move_out')} · ${tr('room_n', {'n': widget.summary['room_number']})}')) return;
    if (!mounted) return;
    final res = await runBusy(
      context,
      () => KirayaApi.instance.settleMoveOut(
        _id,
        _leave,
        finalReading: _reading.text.trim().isEmpty ? null : toNum(_reading.text.trim()),
        noticeShortfall: toNum(_shortfall.text.trim()),
        cleaning: toNum(_cleaning.text.trim()),
        extra: [
          for (final e in _extras)
            if (e.label.text.trim().isNotEmpty && toNum(e.amount.text.trim()) != 0)
              {'label': e.label.text.trim(), 'amount': toNum(e.amount.text.trim())},
        ],
        absconded: _absconded,
        writeOffRest: _waive,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      ),
    );
    if (res == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('settled')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('advance_used', {'a': rupees(res['advance_used'])})),
          const SizedBox(height: 8),
          if (toNum(res['refund']) > 0)
            Text(tr('refund_to_give', {'a': rupees(res['refund'])}),
                style: const TextStyle(fontWeight: FontWeight.bold, color: kGood, fontSize: 18)),
          if (toNum(res['still_due']) > 0)
            Text(tr('still_due_after', {'a': rupees(res['still_due'])}),
                style: const TextStyle(fontWeight: FontWeight.bold, color: kBad, fontSize: 18)),
          if (toNum(res['written_off']) > 0) Text('${tr('kind_WRITE_OFF')}: ${rupees(res['written_off'])}'),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(tr('ok')))],
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final (shortDays, suggested) = _suggestion;
    return Scaffold(
      appBar: AppBar(title: Text('${tr('move_out')} · ${tr('room_n', {'n': widget.summary['room_number']})}')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          BalanceText(widget.summary['balance']),
          InfoRow(tr('advance_held'), rupees(widget.summary['advance_held'])),
          const SizedBox(height: 16),
          DateField(
            label: tr('leave_date'),
            value: _leave,
            first: toDate(widget.summary['start_date']),
            onChanged: (d) => setState(() => _leave = d),
          ),
          const SizedBox(height: 12),
          NumberField(
            controller: _reading,
            label: tr('final_reading'),
            decimal: true,
            required: false,
            helper: _lastReading == null ? null : '${tr('previous_reading')}: $_lastReading',
          ),
          const SizedBox(height: 12),
          NumberField(controller: _cleaning, label: tr('cleaning_charge'), prefix: '₹ ', decimal: true),
          const SizedBox(height: 12),
          NumberField(controller: _shortfall, label: tr('short_notice_charge'), prefix: '₹ ', decimal: true),
          if (shortDays > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _shortfall.text = '$suggested'),
                child: Text(tr('notice_short', {'d': shortDays, 'a': rupees(suggested)})),
              ),
            ),
          SectionTitle(tr('other_deductions'),
              trailing: IconButton(icon: const Icon(Icons.add), onPressed: () => setState(() => _extras.add(_Extra())))),
          for (final e in _extras)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(
                  flex: 3,
                  child: TextField(controller: e.label, decoration: InputDecoration(labelText: tr('charge_name'))),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: NumberField(controller: e.amount, label: tr('amount'), prefix: '₹ ', required: false),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _extras.remove(e))),
              ]),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('left_without_paying')),
            value: _absconded,
            onChanged: (v) => setState(() => _absconded = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('waive_rest')),
            value: _waive,
            onChanged: (v) => setState(() => _waive = v),
          ),
          TextField(controller: _note, decoration: InputDecoration(labelText: tr('note'))),
          const SizedBox(height: 20),
          BigButton(label: tr('settle_now'), icon: Icons.task_alt, onPressed: _settle),
        ]),
      ),
    );
  }
}
