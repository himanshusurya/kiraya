import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

import 'person_form.dart' show numText;

const _modes = ['CASH', 'PHONEPE', 'GPAY', 'UPI_OTHER', 'BANK'];

String monthLabel(Object? v) {
  final d = toDate(v);
  return d == null ? '-' : '${tr('s2_month_${d.month}')} ${d.year}';
}

/// Money received month by month, and who still has to pay.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key, this.onOpenTenancy});
  final void Function(String tenancyId)? onOpenTenancy;

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('s2_reports')),
          bottom: TabBar(
            labelColor: onPrimary,
            unselectedLabelColor: onPrimary.withValues(alpha: 0.75),
            indicatorColor: onPrimary,
            labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            tabs: [Tab(text: tr('s2_collection')), Tab(text: tr('s2_who_owes'))],
          ),
        ),
        body: TabBarView(children: [const _CollectionTab(), _DuesTab(onOpenTenancy: onOpenTenancy)]),
      ),
    );
  }
}

class _CollectionTab extends StatelessWidget {
  const _CollectionTab();

  @override
  Widget build(BuildContext context) => Loader<List<Json>>(
        load: KirayaApi.instance.monthlyCollection,
        builder: (context, rows, _) {
          final byMonth = <String, Map<String, num>>{};
          final counts = <String, Map<String, num>>{};
          for (final r in rows) {
            final m = '${r['month']}';
            final mode = '${r['mode']}';
            byMonth.putIfAbsent(m, () => {})[mode] = (byMonth[m]![mode] ?? 0) + toNum(r['amount']);
            counts.putIfAbsent(m, () => {})[mode] = (counts[m]![mode] ?? 0) + toNum(r['payments']);
          }
          final months = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));
          if (months.isEmpty) return ListView(children: [EmptyState(text: tr('s2_no_collection'), icon: Icons.bar_chart)]);
          return ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
            for (final m in months)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(
                        child: Text(monthLabel(m),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      ),
                      Text(rupees(byMonth[m]!.values.fold<num>(0, (a, b) => a + b)),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold, color: kGood)),
                    ]),
                    const Divider(),
                    for (final mode in [..._modes, ...byMonth[m]!.keys.where((k) => !_modes.contains(k))])
                      if (byMonth[m]![mode] != null)
                        InfoRow(
                          '${tr('mode_$mode')}  (${tr('s2_n_payments', {'n': numText(counts[m]![mode])})})',
                          rupees(byMonth[m]![mode]),
                        ),
                  ]),
                ),
              ),
          ]);
        },
      );
}

class _DuesTab extends StatelessWidget {
  const _DuesTab({this.onOpenTenancy});
  final void Function(String tenancyId)? onOpenTenancy;

  @override
  Widget build(BuildContext context) => Loader<List<Json>>(
        load: KirayaApi.instance.tenancySummaries,
        builder: (context, rows, _) {
          final list = [...rows]..sort((a, b) => toNum(b['balance']).compareTo(toNum(a['balance'])));
          final owing = list.where((r) => toNum(r['balance']) > 0).toList();
          final total = owing.fold<num>(0, (a, r) => a + toNum(r['balance']));
          return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            Card(
              color: (total > 0 ? kBad : kGood).withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Text(tr('s2_total_due'), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(rupees(total),
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold, color: total > 0 ? kBad : kGood)),
                  Text(tr('s2_rooms_owing', {'n': owing.length})),
                ]),
              ),
            ),
            if (list.isEmpty) EmptyState(text: tr('s2_no_tenants_now')),
            for (final r in list)
              ListTile(
                leading: CircleAvatar(child: Text('${r['room_number']}', style: const TextStyle(fontSize: 12))),
                title: Text('${r['primary_name'] ?? '-'}'),
                subtitle: Text(r['last_paid_on'] == null
                    ? tr('s2_never_paid')
                    : tr('s2_last_paid', {'d': fmtDate(r['last_paid_on'])})),
                trailing: BalanceText(r['balance']),
                onTap: onOpenTenancy == null ? null : () => onOpenTenancy!(r['tenancy_id'] as String),
              ),
          ]);
        },
      );
}
