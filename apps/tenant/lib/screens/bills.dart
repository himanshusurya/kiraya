import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

/// All issued bills for the tenancy, latest first.
class BillsTab extends StatelessWidget {
  const BillsTab({super.key, required this.tenancyId});
  final String tenancyId;

  @override
  Widget build(BuildContext context) => Loader<List<Json>>(
        load: () => KirayaApi.instance.bills(tenancyId),
        builder: (context, bills, _) => BillList(bills: bills),
      );
}

class BillList extends StatelessWidget {
  const BillList({super.key, required this.bills});
  final List<Json> bills;

  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: bills.isEmpty
            ? [EmptyState(text: tr('no_bills'), icon: Icons.receipt_outlined)]
            : [for (final b in bills) BillCard(bill: b)],
      );
}
