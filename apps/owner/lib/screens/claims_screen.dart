import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

/// Payments the tenants said they made ("I paid"); owner confirms or rejects.
class ClaimsScreen extends StatefulWidget {
  const ClaimsScreen({super.key});

  @override
  State<ClaimsScreen> createState() => _ClaimsScreenState();
}

class _ClaimsScreenState extends State<ClaimsScreen> {
  final _loader = GlobalKey<LoaderState<List<Json>>>();

  Future<void> _decide(Json p, bool approve) async {
    String? reason;
    if (!approve) {
      final ctl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(tr('reject')),
          content: TextField(controller: ctl, autofocus: true, decoration: InputDecoration(labelText: tr('reject_reason'))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('reject'))),
          ],
        ),
      );
      if (ok != true) return;
      reason = ctl.text.trim().isEmpty ? null : ctl.text.trim();
    }
    if (!mounted) return;
    final r = await runBusy(context, () async {
      await KirayaApi.instance.confirmPayment(p['id'] as String, approve, reason);
      return true;
    }, success: approve ? tr('claim_approved') : tr('claim_rejected'));
    if (r == true) await _loader.currentState?.reload();
  }

  Future<void> _proof(String path) async {
    final url = await runBusy(context, () => KirayaApi.instance.signedUrl(path));
    if (url == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => Dialog(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('ok'))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('claims'))),
        body: Loader<List<Json>>(
          key: _loader,
          load: KirayaApi.instance.pendingClaims,
          builder: (context, claims, _) {
            if (claims.isEmpty) {
              return ListView(children: [EmptyState(text: tr('no_claims'), icon: Icons.verified_outlined)]);
            }
            return ListView(padding: const EdgeInsets.all(12), children: [
              for (final p in claims)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(tr('room_n', {'n': (p['tenancy'] as Map?)?['room']?['number'] ?? '?'}),
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        ),
                        Text(rupees(p['amount']),
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                      ]),
                      const SizedBox(height: 4),
                      InfoRow(tr('date'), fmtDate(p['paid_on'])),
                      for (final s in ((p['payment_split'] as List?) ?? const []).cast<Json>())
                        InfoRow(tr('mode_${s['mode']}'), s['ref']?.toString() ?? ''),
                      if ((p['note'] ?? '').toString().isNotEmpty) InfoRow(tr('note'), '${p['note']}'),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.end, children: [
                        if (p['proof_path'] != null)
                          TextButton.icon(
                            onPressed: () => _proof(p['proof_path'] as String),
                            icon: const Icon(Icons.image_outlined),
                            label: Text(tr('view_proof')),
                          ),
                        OutlinedButton.icon(
                          onPressed: () => _decide(p, false),
                          icon: const Icon(Icons.close, color: kBad),
                          label: Text(tr('reject')),
                        ),
                        FilledButton.icon(
                          onPressed: () => _decide(p, true),
                          icon: const Icon(Icons.check),
                          label: Text(tr('approve')),
                        ),
                      ]),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      );
}
