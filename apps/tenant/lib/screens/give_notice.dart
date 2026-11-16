import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

import '../util.dart';

/// Give (or change) notice to leave. Warns when the notice is shorter than the period.
class GiveNoticeScreen extends StatelessWidget {
  const GiveNoticeScreen({
    super.key,
    required this.tenancyId,
    required this.settings,
    required this.onDone,
    this.currentLeaveOn,
  });
  final String tenancyId;
  final Json settings;
  final DateTime? currentLeaveOn;
  final Future<void> Function() onDone;

  Future<void> _send(BuildContext context, DateTime leaveOn, String? note) async {
    final yes = await confirm(
      context,
      '${tr('notice_confirm', {'d': fmtDate(leaveOn)})}\n\n${tr('notice_cannot_undo')}',
      title: tr('give_notice'),
    );
    if (!yes || !context.mounted) return;
    final res = await runBusy(context, () => KirayaApi.instance.giveNotice(tenancyId, leaveOn, note: note));
    if (res == null || !context.mounted) return;
    final short = toNum(res['short_by_days']).round();
    if (short > 0) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.warning_amber, color: kWarn, size: 40),
          title: Text(tr('notice_sent')),
          content: Text(
            toNum(res['suggested_shortfall']) > 0
                ? tr('notice_short_amount', {'d': short, 'amt': rupees(res['suggested_shortfall'])})
                : tr('notice_short', {'d': short}),
            style: const TextStyle(fontSize: 17),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(tr('ok')))],
        ),
      );
    } else {
      showMessage(context, tr('notice_sent'));
    }
    await onDone();
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(currentLeaveOn == null ? tr('give_notice') : tr('change_leave_date'))),
        body: GiveNoticeForm(
          periodDays: noticePeriodDays(settings),
          today: todayIst(),
          initialLeaveOn: currentLeaveOn,
          onSubmit: (d, note) => _send(context, d, note),
        ),
      );
}

/// Presentational form: notice period, leaving date and a live "days short" warning.
class GiveNoticeForm extends StatefulWidget {
  const GiveNoticeForm({
    super.key,
    required this.periodDays,
    required this.today,
    required this.onSubmit,
    this.initialLeaveOn,
  });
  final int periodDays;
  final DateTime today;
  final DateTime? initialLeaveOn;
  final Future<void> Function(DateTime leaveOn, String? note) onSubmit;

  @override
  State<GiveNoticeForm> createState() => _GiveNoticeFormState();
}

class _GiveNoticeFormState extends State<GiveNoticeForm> {
  late DateTime _leaveOn = widget.initialLeaveOn ?? widget.today.add(Duration(days: widget.periodDays));
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await widget.onSubmit(_leaveOn, _note.text.trim().isEmpty ? null : _note.text.trim());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final short = noticeShortBy(widget.periodDays, widget.today, _leaveOn);
    final color = short > 0 ? kWarn : kGood;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(tr('notice_period', {'n': widget.periodDays}),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        DateField(
          label: tr('leave_date'),
          value: _leaveOn.isBefore(widget.today) ? widget.today : _leaveOn,
          first: widget.today,
          last: widget.today.add(const Duration(days: 365)),
          onChanged: (d) => setState(() => _leaveOn = d),
        ),
        const SizedBox(height: 12),
        Text(tr('notice_days_given', {'n': daysBetween(widget.today, _leaveOn)})),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Icon(short > 0 ? Icons.warning_amber : Icons.check_circle, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(short > 0 ? tr('notice_short', {'d': short}) : tr('notice_ok'),
                  style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 16)),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        TextField(controller: _note, maxLines: 2, decoration: InputDecoration(labelText: tr('note_optional'))),
        const SizedBox(height: 24),
        BigButton(label: tr('send_to_owner'), icon: Icons.send, onPressed: _busy ? null : _submit),
      ],
    );
  }
}
