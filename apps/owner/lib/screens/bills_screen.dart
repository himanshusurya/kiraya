import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

/// Draft bills: make due bills, check each one, add/remove lines, then send (issue).
class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  final _loader = GlobalKey<LoaderState<List<Json>>>();
  Future<void> _reload() async => _loader.currentState?.reload();

  Future<void> _generate() async {
    final n = await runBusy(context, KirayaApi.instance.generateDueBills);
    if (n == null || !mounted) return;
    showMessage(context, n == 0 ? tr('no_bills_due') : tr('bills_made', {'n': n}));
    await _reload();
  }

  Future<void> _issueAll(int count) async {
    if (!await confirm(context, tr('issue_all_confirm', {'n': count})) || !mounted) return;
    final n = await runBusy(context, KirayaApi.instance.issueAllDrafts);
    if (n == null || !mounted) return;
    showMessage(context, tr('bills_issued', {'n': n}));
    await _reload();
  }

  Future<void> _addLine(Json bill) async {
    final label = TextEditingController();
    final amount = TextEditingController();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('add_line')),
        content: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: label,
              autofocus: true,
              decoration: InputDecoration(labelText: tr('charge_name')),
              validator: (v) => (v ?? '').trim().isEmpty ? tr('required') : null,
            ),
            const SizedBox(height: 12),
            NumberField(controller: amount, label: tr('amount'), prefix: '₹ ', decimal: true, allowNegative: true),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('cancel'))),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(c, true);
            },
            child: Text(tr('save')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await runBusy(context, () async {
      await KirayaApi.instance.addBillLine(bill['id'] as String, label.text.trim(), toNum(amount.text.trim()));
      return true;
    });
    if (r == true) await _reload();
  }

  Future<void> _removeLine(Json line) async {
    if (line['kind'] == 'RENT') return;
    if (!await confirm(context, tr('remove_line_q', {'l': line['label'] ?? tr('line_${line['kind']}')})) || !mounted) {
      return;
    }
    final r = await runBusy(context, () async {
      await KirayaApi.instance.removeBillLine(line['id'] as String);
      return true;
    });
    if (r == true) await _reload();
  }

  Future<void> _issue(Json bill) async {
    final r = await runBusy(context, () async {
      await KirayaApi.instance.issueBill(bill['id'] as String);
      return true;
    }, success: tr('bill_issued'));
    if (r == true) await _reload();
  }

  Future<void> _discard(Json bill) async {
    if (!await confirm(context, tr('discard_confirm')) || !mounted) return;
    final r = await runBusy(context, () async {
      await KirayaApi.instance.discardDraft(bill['id'] as String);
      return true;
    });
    if (r == true) await _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('bills'))),
        body: Loader<List<Json>>(
          key: _loader,
          load: KirayaApi.instance.draftBills,
          builder: (context, drafts, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            children: [
              BigButton(label: tr('generate_bills'), icon: Icons.post_add, outlined: true, onPressed: _generate),
              const SizedBox(height: 4),
              Text(tr('drafts_help'), style: Theme.of(context).textTheme.bodySmall),
              if (drafts.isEmpty) EmptyState(text: tr('no_drafts'), icon: Icons.receipt_long),
              if (drafts.length > 1) ...[
                const SizedBox(height: 12),
                BigButton(label: tr('issue_all'), icon: Icons.send, onPressed: () => _issueAll(drafts.length)),
              ],
              for (final b in drafts) ...[
                SectionTitle(tr('room_n', {'n': (b['tenancy'] as Map?)?['room']?['number'] ?? '?'})),
                BillCard(
                  bill: b,
                  onLineLongPress: _removeLine,
                  trailing: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.end, children: [
                      TextButton.icon(onPressed: () => _discard(b), icon: const Icon(Icons.delete_outline), label: Text(tr('discard'))),
                      OutlinedButton.icon(onPressed: () => _addLine(b), icon: const Icon(Icons.add), label: Text(tr('add_line'))),
                      FilledButton.icon(onPressed: () => _issue(b), icon: const Icon(Icons.send), label: Text(tr('issue'))),
                    ]),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}
