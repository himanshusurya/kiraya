import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

const paymentModes = ['CASH', 'PHONEPE', 'GPAY', 'UPI_OTHER', 'BANK'];

class _Split {
  _Split(this.mode, String amount) : amount = TextEditingController(text: amount);
  String mode;
  final TextEditingController amount;
  final ref = TextEditingController();
}

/// "Payment received": one or more parts (e.g. ₹2000 cash + ₹500 PhonePe), Splitwise-style record.
/// Pops with the new payment id.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.summary});
  final Json summary;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _form = GlobalKey<FormState>();
  final _note = TextEditingController();
  final _key = const Uuid().v4();
  late final List<_Split> _splits = [
    _Split('CASH', toNum(widget.summary['balance']) > 0 ? '${toNum(widget.summary['balance'])}' : ''),
  ];
  DateTime _date = todayIst();

  num get _total => _splits.fold<num>(0, (s, x) => s + toNum(x.amount.text.trim()));

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _total <= 0) return;
    final splits = [
      for (final s in _splits)
        if (toNum(s.amount.text.trim()) > 0)
          {'mode': s.mode, 'amount': toNum(s.amount.text.trim()), if (s.ref.text.trim().isNotEmpty) 'ref': s.ref.text.trim()},
    ];
    final id = await runBusy(
      context,
      () => KirayaApi.instance.recordPayment(widget.summary['tenancy_id'] as String, _date, splits,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(), idempotencyKey: _key),
    );
    if (id != null && mounted) {
      showMessage(context, tr('payment_saved', {'a': rupees(_total)}));
      Navigator.pop(context, id);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('${tr('record_payment')} · ${tr('room_n', {'n': widget.summary['room_number']})}')),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            BalanceText(widget.summary['balance']),
            const SizedBox(height: 16),
            for (var i = 0; i < _splits.length; i++) ...[
              if (i > 0) const Divider(height: 32),
              Text(tr('how_paid'), style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final m in paymentModes)
                  ChoiceChip(
                    label: Text(tr('mode_$m')),
                    selected: _splits[i].mode == m,
                    onSelected: (_) => setState(() => _splits[i].mode = m),
                  ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: NumberField(
                    controller: _splits[i].amount,
                    label: tr('amount'),
                    prefix: '₹ ',
                    decimal: true,
                    autofocus: i == 0,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                if (i > 0)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _splits.removeAt(i)),
                  ),
              ]),
              if (_splits[i].mode != 'CASH') ...[
                const SizedBox(height: 10),
                TextField(controller: _splits[i].ref, decoration: InputDecoration(labelText: tr('ref_optional'))),
              ],
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text(tr('add_split')),
                onPressed: () => setState(() => _splits.add(_Split('PHONEPE', ''))),
              ),
            ),
            const SizedBox(height: 8),
            DateField(label: tr('date'), value: _date, last: todayIst(), onChanged: (d) => setState(() => _date = d)),
            const SizedBox(height: 12),
            TextField(controller: _note, decoration: InputDecoration(labelText: tr('note'))),
            const SizedBox(height: 20),
            InfoRow(tr('total'), rupees(_total), bold: true),
            const SizedBox(height: 12),
            BigButton(label: tr('save'), icon: Icons.check, onPressed: _total > 0 ? _save : null),
          ]),
        ),
      );
}
