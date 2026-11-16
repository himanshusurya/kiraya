import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

/// Extra charges (e.g. Fan ₹420 every month, one-time repairs).
class ChargesScreen extends StatelessWidget {
  const ChargesScreen({super.key, required this.tenancyId});
  final String tenancyId;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('my_charges'))),
        body: Loader<List<Json>>(
          load: () => KirayaApi.instance.charges(tenancyId),
          builder: (context, rows, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: rows.isEmpty
                ? [EmptyState(text: tr('no_charges'), icon: Icons.playlist_add_check)]
                : [for (final c in rows) Card(child: ChargeTile(charge: c))],
          ),
        ),
      );
}

class ChargeTile extends StatelessWidget {
  const ChargeTile({super.key, required this.charge});
  final Json charge;

  @override
  Widget build(BuildContext context) {
    final recurring = charge['kind'] == 'RECURRING';
    final end = toDate(charge['end_date']);
    final stopped = charge['active'] == false || (end != null && end.isBefore(todayIst()));
    final when = recurring
        ? [
            tr('every_month'),
            tr('from_date', {'d': fmtDate(charge['start_date'])}),
            if (end != null) tr('till_date', {'d': fmtDate(end)}),
          ].join(' · ')
        : '${tr('one_time')} · ${fmtDate(charge['start_date'])}';
    return ListTile(
      title: Text(charge['label']?.toString() ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      subtitle: Text(when),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(rupees(charge['amount']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        if (stopped) Text(tr('stopped'), style: const TextStyle(color: Colors.grey)),
      ]),
    );
  }
}

/// Advance (security deposit) held by the owner, with its history.
class AdvanceScreen extends StatelessWidget {
  const AdvanceScreen({super.key, required this.tenancyId});
  final String tenancyId;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('advance_title'))),
        body: Loader<List<Json>>(
          load: () => KirayaApi.instance.advance(tenancyId),
          builder: (context, rows, _) => AdvanceView(rows: rows),
        ),
      );
}

class AdvanceView extends StatelessWidget {
  const AdvanceView({super.key, required this.rows});
  final List<Json> rows;

  @override
  Widget build(BuildContext context) {
    final held = rows.fold<num>(0, (s, r) => s + toNum(r['amount']));
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('advance_held')),
              Text(rupees(held),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: kGood)),
            ]),
          ),
        ),
        if (rows.isEmpty) EmptyState(text: tr('no_advance'), icon: Icons.savings_outlined),
        for (final r in rows.reversed)
          ListTile(
            title: Text(r['note']?.toString().isNotEmpty == true
                ? r['note'].toString()
                : (toNum(r['amount']) >= 0 ? tr('advance_given') : tr('advance_out'))),
            subtitle: Text(fmtDate(r['txn_date'])),
            trailing: Text(
              toNum(r['amount']) >= 0 ? '+ ${rupees(r['amount'])}' : '− ${rupees(-toNum(r['amount']))}',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: toNum(r['amount']) >= 0 ? kGood : kBad),
            ),
          ),
      ],
    );
  }
}
