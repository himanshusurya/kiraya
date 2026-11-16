import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

import '../screens2/people_screen.dart';
import 'move_out_screen.dart';
import 'payment_screen.dart';
import 'shift_screen.dart';
import 'tenancy_dialogs.dart';

/// Everything loaded for one tenancy screen.
class TenancyData {
  TenancyData(this.summary, this.bills, this.ledger, this.payments, this.charges, this.settings, this.settlement);
  final Json summary;
  final List<Json> bills, ledger, payments, charges;
  final Json settings;
  final Json? settlement;

  bool get live => summary['status'] == 'ACTIVE' || summary['status'] == 'ON_NOTICE';

  static Future<TenancyData> load(String id) async {
    final api = KirayaApi.instance;
    final r = await Future.wait<Object?>([
      api.tenancySummary(id),
      api.bills(id),
      api.ledger(id),
      api.payments(id),
      api.charges(id),
      api.settings(),
      api.settlement(id),
    ]);
    if (r[0] == null) throw Exception(tr('nothing_here'));
    return TenancyData(r[0] as Json, r[1] as List<Json>, r[2] as List<Json>, r[3] as List<Json>, r[4] as List<Json>,
        r[5] as Json, r[6] as Json?);
  }
}

class TenancyScreen extends StatefulWidget {
  const TenancyScreen({super.key, required this.tenancyId});
  final String tenancyId;

  @override
  State<TenancyScreen> createState() => _TenancyScreenState();
}

class _TenancyScreenState extends State<TenancyScreen> {
  late Future<TenancyData> _future = TenancyData.load(widget.tenancyId);

  Future<void> _reload() async {
    final f = TenancyData.load(widget.tenancyId);
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<TenancyData>(
        future: _future,
        builder: (context, snap) {
          final d = snap.data;
          return DefaultTabController(
            length: 4,
            child: Scaffold(
              appBar: AppBar(
                title: Text(d == null
                    ? tr('loading')
                    : '${tr('room_n', {'n': d.summary['room_number']})} · ${d.summary['primary_name'] ?? ''}'),
                bottom: TabBar(
                  isScrollable: true,
                  labelColor: Theme.of(context).colorScheme.onPrimary,
                  unselectedLabelColor: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.7),
                  indicatorColor: Theme.of(context).colorScheme.onPrimary,
                  tabs: [
                    Tab(text: tr('home')),
                    Tab(text: tr('bills')),
                    Tab(text: tr('ledger')),
                    Tab(text: tr('payments')),
                  ],
                ),
              ),
              body: snap.connectionState != ConnectionState.done
                  ? const Center(child: CircularProgressIndicator())
                  : snap.hasError
                      ? Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(friendlyError(snap.error!)),
                          OutlinedButton(onPressed: _reload, child: Text(tr('retry'))),
                        ]))
                      : TabBarView(children: [
                          RefreshIndicator(onRefresh: _reload, child: _SummaryTab(d!, _reload)),
                          RefreshIndicator(
                            onRefresh: _reload,
                            child: d.bills.isEmpty
                                ? ListView(children: const [EmptyState(icon: Icons.receipt_long)])
                                : ListView(
                                    padding: const EdgeInsets.only(bottom: 24),
                                    children: [for (final b in d.bills) BillCard(bill: b)],
                                  ),
                          ),
                          RefreshIndicator(onRefresh: _reload, child: LedgerList(entries: d.ledger)),
                          RefreshIndicator(onRefresh: _reload, child: _PaymentsTab(d, _reload)),
                        ]),
              floatingActionButton: d != null && d.live
                  ? FloatingActionButton.extended(
                      icon: const Icon(Icons.currency_rupee),
                      label: Text(tr('record_payment')),
                      onPressed: () => _recordPayment(context, d),
                    )
                  : null,
            ),
          );
        },
      );

  Future<void> _recordPayment(BuildContext context, TenancyData d) async {
    final paymentId = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => PaymentScreen(summary: d.summary)));
    if (paymentId == null || !context.mounted) return;
    await _reload();
    if (!context.mounted) return;
    showUndo(context, tr('saved'), () async {
      await KirayaApi.instance.voidPayment(paymentId, 'Undo');
      await _reload();
    });
  }
}

class _SummaryTab extends StatelessWidget {
  const _SummaryTab(this.d, this.reload);
  final TenancyData d;
  final Future<void> Function() reload;

  Json get s => d.summary;
  String get id => s['tenancy_id'] as String;

  Future<void> _then(BuildContext context, Future<bool?> f) async {
    if (await f == true) await reload();
  }

  void _remind(BuildContext context) {
    final phone = s['primary_phone']?.toString() ?? '';
    if (phone.isEmpty) return showMessage(context, tr('no_phone'), error: true);
    final key = Lang.instance.isHindi ? 'reminder_hi' : 'reminder_en';
    final tpl = (d.settings[key]?.toString().trim().isNotEmpty ?? false) ? d.settings[key].toString() : tr('reminder_default');
    final text = fillTemplate(tpl, {
      'name': '${s['primary_name'] ?? ''}',
      'room': '${s['room_number']}',
      'due': rupees(toNum(s['balance']) > 0 ? s['balance'] : 0),
      'date': fmtDate(todayIst()),
    });
    openUri(whatsappUri(phone, text));
  }

  @override
  Widget build(BuildContext context) {
    final onNotice = s['status'] == 'ON_NOTICE';
    final phone = s['primary_phone']?.toString() ?? '';
    final recurring = d.charges.where((c) => c['kind'] == 'RECURRING' && c['active'] == true).toList();
    Widget action(IconData icon, String key, VoidCallback onTap, {Color? color}) => SizedBox(
          width: 160,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft, foregroundColor: color, padding: const EdgeInsets.all(12)),
            onPressed: onTap,
            icon: Icon(icon),
            label: Text(tr(key), maxLines: 2),
          ),
        );

    return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text('${s['primary_name'] ?? ''}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ),
              StatusChip(tr('tstatus_${s['status']}'), color: onNotice ? kWarn : (d.live ? kGood : Colors.grey)),
            ]),
            if (phone.isNotEmpty)
              Row(children: [
                Text(phone),
                IconButton(icon: const Icon(Icons.call), onPressed: () => openUri(callUri(phone))),
                IconButton(icon: const Icon(Icons.chat, color: kGood), onPressed: () => openUri(whatsappUri(phone, ''))),
              ]),
            const SizedBox(height: 8),
            BalanceText(s['balance'], big: true),
            const SizedBox(height: 8),
            InfoRow(tr('monthly_rent'), rupees(s['monthly_rent'])),
            InfoRow(tr('advance_held'), rupees(s['advance_held'])),
            InfoRow(tr('date'), tr('since', {'d': fmtDate(s['start_date'])})),
            if (d.live) InfoRow(tr('next_bill', {'d': ''}).trim(), fmtDate(s['next_bill_date'])),
            if (s['last_paid_on'] != null) InfoRow(tr('last_paid', {'d': ''}).trim(), fmtDate(s['last_paid_on'])),
            if (onNotice && s['leave_on'] != null)
              InfoRow(tr('leave_date'), fmtDate(s['leave_on']), bold: true, color: kWarn),
          ]),
        ),
      ),
      if (d.settlement != null) _SettlementCard(d.settlement!),
      if (d.live) ...[
        SectionTitle(tr('actions')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            action(Icons.chat, 'remind', () => _remind(context), color: kGood),
            action(Icons.add_card, 'add_charge', () => _then(context, showChargeDialog(context, id))),
            action(Icons.tune, 'adjust', () => _then(context, showAdjustDialog(context, id))),
            action(Icons.edit, 'edit_rent', () => _then(context, showRentDialog(context, id, s['monthly_rent']))),
            action(Icons.group, 'people', () async {
              await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => PeopleScreen(tenancyId: id)));
              await reload();
            }),
            if (!onNotice)
              action(Icons.event_busy, 'give_notice', () => _then(context, showNoticeDialog(context, s, d.settings)))
            else
              action(Icons.undo, 'withdraw_notice', () async {
                if (!await confirm(context, tr('withdraw_notice'))) return;
                if (!context.mounted) return;
                await runBusy(context, () => KirayaApi.instance.withdrawNotice(id), success: tr('saved'));
                await reload();
              }),
            action(Icons.swap_horiz, 'shift_room', () async {
              final newId = await Navigator.push<String>(
                  context, MaterialPageRoute(builder: (_) => ShiftScreen(summary: s)));
              if (newId != null && context.mounted) {
                Navigator.pushReplacement(
                    context, MaterialPageRoute<void>(builder: (_) => TenancyScreen(tenancyId: newId)));
              }
            }),
            action(Icons.logout, 'move_out', () async {
              final done = await Navigator.push<bool>(
                  context, MaterialPageRoute(builder: (_) => MoveOutScreen(summary: s, settings: d.settings)));
              if (done == true) await reload();
            }, color: kBad),
          ]),
        ),
      ] else
        ListTile(
          leading: const Icon(Icons.group),
          title: Text(tr('people')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => PeopleScreen(tenancyId: id))),
        ),
      if (recurring.isNotEmpty) ...[
        SectionTitle(tr('charges')),
        for (final c in recurring)
          ListTile(
            title: Text('${c['label']}'),
            subtitle: Text(tr('since', {'d': fmtDate(c['start_date'])}) +
                (c['end_date'] != null ? ' → ${fmtDate(c['end_date'])}' : '')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(rupees(c['amount']), style: const TextStyle(fontWeight: FontWeight.bold)),
              if (d.live && c['end_date'] == null)
                IconButton(
                  tooltip: tr('stop_charge'),
                  icon: const Icon(Icons.stop_circle_outlined, color: kBad),
                  onPressed: () async {
                    if (!await confirm(context, '${tr('stop_charge')}: ${c['label']}')) return;
                    if (!context.mounted) return;
                    await runBusy(context, () => KirayaApi.instance.stopCharge(c['id'] as String), success: tr('saved'));
                    await reload();
                  },
                ),
            ]),
          ),
      ],
    ]);
  }
}

class _SettlementCard extends StatelessWidget {
  const _SettlementCard(this.st);
  final Json st;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${tr('settled')} · ${fmtDate(st['leave_date'])}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            InfoRow(tr('advance'), rupees(st['advance_held'])),
            InfoRow(tr('advance_used', {'a': ''}).replaceAll(':', '').trim(), rupees(st['advance_applied'])),
            InfoRow(tr('refund_to_give', {'a': ''}).replaceAll(':', '').trim(), rupees(st['refund_amount'])),
            if (toNum(st['written_off']) > 0) InfoRow(tr('kind_WRITE_OFF'), rupees(st['written_off'])),
            InfoRow(tr('balance'), rupees(st['balance_after']), bold: true),
          ]),
        ),
      );
}

class _PaymentsTab extends StatelessWidget {
  const _PaymentsTab(this.d, this.reload);
  final TenancyData d;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    if (d.payments.isEmpty) return ListView(children: const [EmptyState(icon: Icons.payments_outlined)]);
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: d.payments.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final p = d.payments[i];
        final splits = ((p['payment_split'] as List?) ?? const []).cast<Json>();
        final modes = splits.map((x) => '${tr('mode_${x['mode']}')} ${rupees(x['amount'])}').join(' + ');
        return ListTile(
          title: Text(rupees(p['amount']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          subtitle: Text([
            fmtDate(p['paid_on']),
            modes,
            if ((p['note'] ?? '').toString().isNotEmpty) '${p['note']}',
            if ((p['reject_reason'] ?? '').toString().isNotEmpty) '${p['reject_reason']}',
          ].join('\n')),
          isThreeLine: true,
          trailing: StatusChip.payment(p['status'] as String),
          onLongPress: p['status'] != 'CONFIRMED' || !d.live
              ? null
              : () async {
                  if (!await confirm(context, tr('cancel_payment_q', {'a': rupees(p['amount'])}),
                      title: tr('cancel_payment'))) {
                    return;
                  }
                  if (!context.mounted) return;
                  await runBusy(context, () => KirayaApi.instance.voidPayment(p['id'] as String),
                      success: tr('cancelled'));
                  await reload();
                },
        );
      },
    );
  }
}
