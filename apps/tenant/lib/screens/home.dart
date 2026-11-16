import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

import '../shell.dart';
import '../util.dart';
import 'hisaab.dart';
import 'pay_claim.dart';

class HomeInfo {
  HomeInfo({required this.summary, required this.bills, required this.payments, this.settlement});
  final Json summary;
  final List<Json> bills;
  final List<Json> payments;
  final Json? settlement;
}

class HomeTab extends StatelessWidget {
  const HomeTab({super.key, required this.data, required this.tenancy});
  final TenantData data;
  final Json tenancy;

  String get _id => tenancy['tenancy_id'].toString();

  Future<HomeInfo> _load() async {
    final api = KirayaApi.instance;
    final res = await Future.wait<Object?>([
      api.tenancySummary(_id),
      api.bills(_id),
      api.payments(_id),
      isLive(tenancy) ? Future<Json?>.value(null) : api.settlement(_id),
    ]);
    return HomeInfo(
      summary: (res[0] as Json?) ?? tenancy,
      bills: res[1] as List<Json>,
      payments: res[2] as List<Json>,
      settlement: res[3] as Json?,
    );
  }

  @override
  Widget build(BuildContext context) => Loader<HomeInfo>(
        load: _load,
        builder: (context, info, reload) {
          Future<void> claim() async {
            final ok = await Navigator.push<bool>(
              context,
              MaterialPageRoute(builder: (_) => PayClaimScreen(tenancyId: _id, balance: toNum(info.summary['balance']))),
            );
            if (ok == true && context.mounted) {
              showMessage(context, tr('claim_sent'));
              await reload();
            }
          }

          final s = info.summary;
          return HomeView(
            summary: s,
            settings: data.settings,
            latestBill: info.bills.firstOrNull,
            pendingClaims: info.payments.where((p) => p['status'] == 'PENDING_CONFIRM').toList(),
            settlement: info.settlement,
            onPay: () => payByUpi(context, s, data.settings, onClaim: claim),
            onClaim: claim,
            onCall: () => _contactOwner(context, data.settings, (p) => callUri(p)),
            onWhatsApp: () => _contactOwner(
                context, data.settings, (p) => whatsappUri(p, tr('wa_hello', {'room': s['room_number']}))),
          );
        },
      );
}

Future<void> _contactOwner(BuildContext context, Json settings, Uri Function(String phone) uri) async {
  final phone = settingText(settings, 'owner_phone');
  if (phone.isEmpty) {
    showMessage(context, tr('owner_phone_missing'), error: true);
    return;
  }
  var ok = false;
  try {
    ok = await openUri(uri(phone));
  } catch (_) {}
  if (!ok && context.mounted) showMessage(context, tr('error'), error: true);
}

/// Opens the phone's UPI app with the owner's UPI ID and the amount due filled in.
Future<void> payByUpi(BuildContext context, Json summary, Json settings, {VoidCallback? onClaim}) async {
  final upiId = settingText(settings, 'upi_id');
  if (upiId.isEmpty) {
    showMessage(context, tr('upi_not_set'), error: true);
    return;
  }
  final name = settingText(settings, 'upi_name');
  final balance = toNum(summary['balance']);
  final uri = upiUri(
    upiId: upiId,
    name: name.isEmpty ? 'Owner' : name,
    amount: balance > 0 ? balance : null,
    note: 'Room ${summary['room_number']} rent',
  );
  var ok = false;
  try {
    ok = await openUri(uri);
  } catch (_) {}
  if (!context.mounted) return;
  if (!ok) {
    showMessage(context, tr('no_upi_app'), error: true);
  } else {
    showMessage(context, tr('after_upi'),
        action: onClaim == null ? null : SnackBarAction(label: tr('i_paid'), onPressed: onClaim));
  }
}

/// Pure presentational home screen (no network) – easy to test with plain maps.
class HomeView extends StatelessWidget {
  const HomeView({
    super.key,
    required this.summary,
    required this.settings,
    this.latestBill,
    this.pendingClaims = const [],
    this.settlement,
    this.onPay,
    this.onClaim,
    this.onCall,
    this.onWhatsApp,
  });
  final Json summary;
  final Json settings;
  final Json? latestBill;
  final List<Json> pendingClaims;
  final Json? settlement;
  final VoidCallback? onPay, onClaim, onCall, onWhatsApp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final live = isLive(summary);
    final balance = toNum(summary['balance']);
    final status = summary['status']?.toString() ?? '';
    final statusColor = status == 'ACTIVE' ? kGood : (status == 'ON_NOTICE' ? kWarn : Colors.grey);
    final hasOwnerPhone = settingText(settings, 'owner_phone').isNotEmpty;
    final s = settlement;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.meeting_room, color: theme.colorScheme.primary, size: 32),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr('room_n', {'n': summary['room_number']}),
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                ),
                Flexible(child: StatusChip(tenancyStatusText(summary), color: statusColor)),
              ]),
              const SizedBox(height: 12),
              BalanceText(balance, big: true),
              const SizedBox(height: 8),
              if (live && summary['next_bill_date'] != null) InfoRow(tr('next_bill'), fmtDate(summary['next_bill_date'])),
              if (summary['monthly_rent'] != null) InfoRow(tr('monthly_rent'), rupees(summary['monthly_rent'])),
              InfoRow(tr('advance_held'), rupees(summary['advance_held'])),
              if (summary['last_paid_on'] != null) InfoRow(tr('last_paid'), fmtDate(summary['last_paid_on'])),
            ]),
          ),
        ),
        if (live || balance > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(children: [
              BigButton(label: tr('pay_now'), icon: Icons.currency_rupee, onPressed: onPay),
              const SizedBox(height: 10),
              BigButton(label: tr('i_paid'), icon: Icons.check_circle_outline, outlined: true, onPressed: onClaim),
            ]),
          ),
        if (pendingClaims.isNotEmpty) ...[
          SectionTitle(tr('waiting_owner')),
          for (final p in pendingClaims) Card(child: PaymentTile(payment: p)),
        ],
        if (!live && s != null) ...[
          SectionTitle(tr('settlement')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                InfoRow(tr('left_on'), fmtDate(s['leave_date'])),
                InfoRow(tr('advance_used'), rupees(s['advance_applied'])),
                if (toNum(s['refund_amount']) > 0) InfoRow(tr('refund'), rupees(s['refund_amount']), color: kGood),
                if (toNum(s['written_off']) > 0) InfoRow(tr('written_off'), rupees(s['written_off'])),
                if (toNum(s['balance_after']) > 0)
                  InfoRow(tr('still_due'), rupees(s['balance_after']), bold: true, color: kBad),
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerLeft, child: StatusChip(tr('outcome_${s['outcome']}'))),
              ]),
            ),
          ),
        ],
        if (hasOwnerPhone)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
            child: Column(children: [
              BigButton(label: tr('call_owner'), icon: Icons.call, outlined: true, onPressed: onCall),
              const SizedBox(height: 10),
              BigButton(label: tr('whatsapp_owner'), icon: Icons.chat, outlined: true, onPressed: onWhatsApp),
            ]),
          ),
        if (latestBill != null) ...[
          SectionTitle(tr('latest_bill')),
          BillCard(bill: latestBill!),
        ],
      ],
    );
  }
}
