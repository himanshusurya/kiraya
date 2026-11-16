import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'format.dart';
import 'i18n.dart';
import 'theme.dart';

/// Full-width primary action with an icon.
class BigButton extends StatelessWidget {
  const BigButton({super.key, required this.label, this.icon, this.onPressed, this.outlined = false});
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final child = Text(label, textAlign: TextAlign.center);
    final btn = outlined
        ? (icon == null
            ? OutlinedButton(onPressed: onPressed, child: child)
            : OutlinedButton.icon(onPressed: onPressed, icon: Icon(icon), label: child))
        : (icon == null
            ? FilledButton(onPressed: onPressed, child: child)
            : FilledButton.icon(onPressed: onPressed, icon: Icon(icon), label: child));
    return SizedBox(width: double.infinity, child: btn);
  }
}

/// Coloured pill for a status word.
class StatusChip extends StatelessWidget {
  const StatusChip(this.text, {super.key, this.color = Colors.grey});
  final String text;
  final Color color;

  factory StatusChip.bill(String status) => switch (status) {
        'PAID' => StatusChip(tr('paid'), color: kGood),
        'PARTIAL' => StatusChip(tr('partly_paid'), color: kWarn),
        'DRAFT' => StatusChip(tr('draft'), color: Colors.blueGrey),
        _ => StatusChip(tr('unpaid'), color: kBad),
      };

  factory StatusChip.payment(String status) => switch (status) {
        'CONFIRMED' => StatusChip(tr('received'), color: kGood),
        'PENDING_CONFIRM' => StatusChip(tr('pending'), color: kWarn),
        'REJECTED' => StatusChip(tr('rejected'), color: kBad),
        _ => StatusChip(tr('cancelled'), color: Colors.grey),
      };

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
      );
}

/// Balance shown as "To pay ₹X" (red), "Paid extra ₹X" (green) or "All paid".
class BalanceText extends StatelessWidget {
  const BalanceText(this.balance, {super.key, this.big = false});
  final Object? balance;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final b = toNum(balance);
    final style = (big ? Theme.of(context).textTheme.headlineMedium : Theme.of(context).textTheme.titleMedium)
        ?.copyWith(fontWeight: FontWeight.bold, color: b > 0 ? kBad : kGood);
    final text = b > 0 ? '${tr('to_pay')} ${rupees(b)}' : (b < 0 ? '${tr('extra_paid')} ${rupees(-b)}' : tr('all_clear'));
    return Text(text, style: style);
  }
}

/// Numeric field for rupees / meter values.
class NumberField extends StatelessWidget {
  const NumberField({
    super.key,
    required this.controller,
    required this.label,
    this.required = true,
    this.decimal = false,
    this.allowNegative = false,
    this.prefix,
    this.helper,
    this.autofocus = false,
    this.onChanged,
  });
  final TextEditingController controller;
  final String label;
  final bool required, decimal, allowNegative, autofocus;
  final String? prefix, helper;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        autofocus: autofocus,
        onChanged: onChanged,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal, signed: allowNegative),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(allowNegative ? r'[-0-9.]' : r'[0-9.]')),
        ],
        decoration: InputDecoration(labelText: label, prefixText: prefix, helperText: helper),
        validator: (v) {
          final s = (v ?? '').trim();
          if (s.isEmpty) return required ? tr('required') : null;
          return num.tryParse(s) == null ? tr('invalid_number') : null;
        },
      );
}

/// Date picker field.
class DateField extends StatelessWidget {
  const DateField({super.key, required this.label, required this.value, required this.onChanged, this.first, this.last});
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? first, last;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: value,
            firstDate: first ?? DateTime(2020),
            lastDate: last ?? DateTime(2100),
          );
          if (d != null) onChanged(d);
        },
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_month)),
          child: Text(fmtDate(value)),
        ),
      );
}

/// Label/value row used on detail screens.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.bold = false, this.color});
  final String label;
  final String value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
            Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w500, color: color)),
          ],
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, this.text, this.icon = Icons.inbox_outlined});
  final String? text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            Text(text ?? tr('nothing_here'), textAlign: TextAlign.center),
          ]),
        ),
      );
}

/// Loads data with a spinner, error + retry, and pull-to-refresh.
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;

  @override
  State<Loader<T>> createState() => LoaderState<T>();
}

class LoaderState<T> extends State<Loader<T>> {
  late Future<T> _future = widget.load();

  Future<void> reload() async {
    final f = widget.load();
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off, size: 48, color: kBad),
                  const SizedBox(height: 8),
                  Text(friendlyError(snap.error!), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: reload, child: Text(tr('retry'))),
                ]),
              ),
            );
          }
          return RefreshIndicator(onRefresh: reload, child: widget.builder(context, snap.data as T, reload));
        },
      );
}

void showMessage(BuildContext context, String text, {bool error = false, SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? kBad : null,
      action: action,
      duration: Duration(seconds: action != null ? 5 : 3),
    ));
}

/// Runs [action] with a blocking spinner; shows the friendly error on failure.
/// Returns the result, or null if it failed.
Future<T?> runBusy<T>(BuildContext context, Future<T> Function() action, {String? success}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(canPop: false, child: Center(child: CircularProgressIndicator())),
  );
  try {
    final r = await action();
    nav.pop();
    if (success != null && context.mounted) showMessage(context, success);
    return r;
  } catch (e) {
    nav.pop();
    if (context.mounted) showMessage(context, friendlyError(e), error: true);
    return null;
  }
}

/// Simple yes/no confirmation.
Future<bool> confirm(BuildContext context, String message, {String? title, String? yes}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title ?? tr('are_you_sure')),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(yes ?? tr('yes'))),
        ],
      ),
    ) ??
    false;

/// Shows a 5-second "Undo" snackbar after a money action (HLD: confirm + undo).
void showUndo(BuildContext context, String text, Future<void> Function() undo) {
  showMessage(context, text,
      action: SnackBarAction(
        label: tr('undo'),
        onPressed: () => runBusy(context, undo, success: tr('cancelled')),
      ));
}

/// EN / हिं switch for app bars.
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key, this.onChanged});
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextButton(
        style: TextButton.styleFrom(foregroundColor: Theme.of(context).appBarTheme.foregroundColor),
        onPressed: () async {
          final next = Lang.instance.isHindi ? 'en' : 'hi';
          await Lang.instance.set(next);
          onChanged?.call(next);
        },
        child: Text(Lang.instance.isHindi ? 'EN' : 'हिं', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      );
}

/// Section heading.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
        child: Row(children: [
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
          ),
          ?trailing,
        ]),
      );
}

/// One bill with its lines (used by both apps).
class BillCard extends StatelessWidget {
  const BillCard({super.key, required this.bill, this.trailing, this.onLineLongPress});
  final Map<String, dynamic> bill;
  final Widget? trailing;
  final void Function(Map<String, dynamic> line)? onLineLongPress;

  @override
  Widget build(BuildContext context) {
    final lines = ((bill['bill_line'] as List?) ?? const []).cast<Map<String, dynamic>>()
      ..sort((a, b) => toNum(a['sort']).compareTo(toNum(b['sort'])));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                tr('from_to', {'a': fmtDateShort(bill['cycle_start']), 'b': fmtDate(bill['cycle_end'])}),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            StatusChip.bill(bill['status'] as String),
          ]),
          if (bill['due_date'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(tr('due_on', {'d': fmtDate(bill['due_date'])})),
            ),
          const Divider(),
          for (final l in lines)
            InkWell(
              onLongPress: onLineLongPress == null ? null : () => onLineLongPress!(l),
              child: InfoRow(_lineLabel(l), rupees(l['amount'])),
            ),
          const Divider(),
          InfoRow(tr('total'), rupees(bill['total']), bold: true),
          ?trailing,
        ]),
      ),
    );
  }

  static String _lineLabel(Map<String, dynamic> l) {
    final kind = l['kind'] as String;
    if (kind == 'ELECTRICITY' && l['qty'] != null) {
      return '${tr('electricity')} (${toNum(l['qty'])} ${tr('units')} × ₹${toNum(l['rate'])})';
    }
    if (kind == 'RENT' || kind == 'ELECTRICITY') return tr('line_$kind');
    return l['label']?.toString() ?? tr('line_$kind');
  }
}

/// Ledger (hisaab) table with a running balance.
class LedgerList extends StatelessWidget {
  const LedgerList({super.key, required this.entries});
  final List<Map<String, dynamic>> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return EmptyState(icon: Icons.receipt_long);
    num running = 0;
    final rows = <Widget>[];
    for (final e in entries) {
      final dr = toNum(e['debit']), cr = toNum(e['credit']);
      running += dr - cr;
      rows.add(ListTile(
        dense: false,
        title: Text(e['note']?.toString().isNotEmpty == true ? e['note'].toString() : tr('kind_${e['kind']}')),
        subtitle: Text('${fmtDate(e['entry_date'])} · ${tr('kind_${e['kind']}')}'),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(dr > 0 ? '+ ${rupees(dr)}' : '− ${rupees(cr)}',
              style: TextStyle(fontWeight: FontWeight.bold, color: dr > 0 ? kBad : kGood)),
          Text('= ${rupees(running)}', style: const TextStyle(fontSize: 12)),
        ]),
      ));
    }
    return ListView(physics: const AlwaysScrollableScrollPhysics(), children: rows.reversed.toList());
  }
}
