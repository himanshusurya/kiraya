import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

/// Hisaab: the running ledger and the list of payments (with their status).
class HisaabTab extends StatelessWidget {
  const HisaabTab({super.key, required this.tenancyId});
  final String tenancyId;

  @override
  Widget build(BuildContext context) {
    final api = KirayaApi.instance;
    final scheme = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        Material(
          color: scheme.surfaceContainer,
          child: TabBar(
            labelStyle: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            tabs: [Tab(text: tr('ledger')), Tab(text: tr('payments'))],
          ),
        ),
        Expanded(
          child: TabBarView(children: [
            Loader<List<Json>>(
              load: () => api.ledger(tenancyId),
              builder: (context, rows, _) => rows.isEmpty
                  ? ListView(children: [EmptyState(icon: Icons.receipt_long)])
                  : LedgerList(entries: rows),
            ),
            Loader<List<Json>>(
              load: () => api.payments(tenancyId),
              builder: (context, rows, _) => PaymentList(payments: rows),
            ),
          ]),
        ),
      ]),
    );
  }
}

class PaymentList extends StatelessWidget {
  const PaymentList({super.key, required this.payments});
  final List<Json> payments;

  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: payments.isEmpty
            ? [EmptyState(text: tr('no_payments'), icon: Icons.payments_outlined)]
            : [for (final p in payments) Card(child: PaymentTile(payment: p))],
      );
}

/// One payment: amount, date, modes, UPI ref, note, owner's reject reason and status chip.
class PaymentTile extends StatelessWidget {
  const PaymentTile({super.key, required this.payment});
  final Json payment;

  @override
  Widget build(BuildContext context) {
    final splits = ((payment['payment_split'] as List?) ?? const []).cast<Json>();
    final modes = splits.map((s) => tr('mode_${s['mode']}')).join(' + ');
    final refs = splits.map((s) => s['ref']?.toString() ?? '').where((r) => r.isNotEmpty).join(', ');
    final note = payment['note']?.toString() ?? '';
    final reason = payment['reject_reason']?.toString() ?? '';
    final status = payment['status']?.toString() ?? '';
    return ListTile(
      title: Text(rupees(payment['amount']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text([fmtDate(payment['paid_on']), if (modes.isNotEmpty) modes].join(' · ')),
        if (refs.isNotEmpty) Text(tr('ref', {'r': refs})),
        if (note.isNotEmpty) Text(note),
        if (status == 'REJECTED' && reason.isNotEmpty)
          Text(tr('reason', {'r': reason}), style: const TextStyle(color: kBad, fontWeight: FontWeight.w600)),
      ]),
      trailing: StatusChip.payment(status),
    );
  }
}
