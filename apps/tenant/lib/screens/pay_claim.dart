import 'dart:typed_data';

import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

import '../photo.dart';
import '../util.dart';

const claimModes = ['PHONEPE', 'GPAY', 'UPI_OTHER', 'CASH', 'BANK'];

/// What the tenant filled in on the "I have paid" form.
class PayClaim {
  PayClaim({
    required this.amount,
    required this.paidOn,
    required this.mode,
    required this.idempotencyKey,
    this.ref,
    this.note,
    this.photo,
  });
  final num amount;
  final DateTime paidOn;
  final String mode;
  final String idempotencyKey;
  final String? ref, note;
  final Uint8List? photo;
}

/// "I have paid": uploads the optional screenshot and sends a claim for the owner to confirm.
class PayClaimScreen extends StatelessWidget {
  const PayClaimScreen({super.key, required this.tenancyId, required this.balance});
  final String tenancyId;
  final num balance;

  Future<void> _send(BuildContext context, PayClaim c) async {
    final api = KirayaApi.instance;
    final id = await runBusy(context, () async {
      String? proof;
      if (c.photo != null) {
        // Keyed by the idempotency key, so a retry overwrites instead of duplicating.
        proof = await api.upload('proof/$tenancyId/${c.idempotencyKey}.jpg', c.photo!);
      }
      return api.claimPayment(tenancyId, c.paidOn, c.amount, c.mode,
          ref: c.ref, note: c.note, proofPath: proof, idempotencyKey: c.idempotencyKey);
    });
    if (id != null && context.mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('i_paid'))),
        body: PayClaimForm(
          balance: balance,
          today: todayIst(),
          pickImage: () => pickPhoto(context),
          onSubmit: (c) => _send(context, c),
        ),
      );
}

/// Presentational form (no network). [onSubmit] gets a validated [PayClaim].
class PayClaimForm extends StatefulWidget {
  const PayClaimForm({super.key, required this.balance, required this.today, required this.onSubmit, this.pickImage});
  final num balance;
  final DateTime today;
  final Future<void> Function(PayClaim claim) onSubmit;
  final Future<Uint8List?> Function()? pickImage;

  @override
  State<PayClaimForm> createState() => _PayClaimFormState();
}

class _PayClaimFormState extends State<PayClaimForm> {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: widget.balance > 0 ? amountText(widget.balance) : '');
  final _ref = TextEditingController();
  final _note = TextEditingController();
  // One key per form open: double taps / retries can't create two claims.
  final _key = randomId();
  late DateTime _date = widget.today;
  String _mode = claimModes.first;
  Uint8List? _photo;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final b = await widget.pickImage?.call();
    if (b != null && mounted) setState(() => _photo = b);
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    final amount = toNum(_amount.text.trim());
    if (amount <= 0) {
      showMessage(context, tr('amount_zero'), error: true);
      return;
    }
    String? clean(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    setState(() => _busy = true);
    try {
      await widget.onSubmit(PayClaim(
        amount: amount,
        paidOn: _date,
        mode: _mode,
        idempotencyKey: _key,
        ref: _mode == 'CASH' ? null : clean(_ref),
        note: clean(_note),
        photo: _photo,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            NumberField(controller: _amount, label: tr('amount'), prefix: '₹ ', decimal: true),
            const SizedBox(height: 16),
            DateField(
              label: tr('paid_on'),
              value: _date,
              first: widget.today.subtract(const Duration(days: 365)),
              last: widget.today,
              onChanged: (d) => setState(() => _date = d),
            ),
            const SizedBox(height: 16),
            Text(tr('pay_mode'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in claimModes)
                ChoiceChip(
                  label: Text(tr('mode_$m'), style: const TextStyle(fontSize: 17)),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  selected: _mode == m,
                  onSelected: (_) => setState(() => _mode = m),
                ),
            ]),
            if (_mode != 'CASH') ...[
              const SizedBox(height: 16),
              TextFormField(controller: _ref, decoration: InputDecoration(labelText: tr('upi_ref'))),
            ],
            const SizedBox(height: 16),
            PhotoPickButton(
              label: tr('add_screenshot'),
              addedLabel: tr('screenshot_added'),
              hasPhoto: _photo != null,
              onPick: widget.pickImage == null ? null : _pick,
              onRemove: () => setState(() => _photo = null),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _note,
              maxLines: 2,
              decoration: InputDecoration(labelText: tr('note_optional')),
            ),
            const SizedBox(height: 12),
            Text(tr('claim_help'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            BigButton(label: tr('send_to_owner'), icon: Icons.send, onPressed: _busy ? null : _submit),
          ],
        ),
      );
}
