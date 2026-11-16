import 'package:intl/intl.dart';

final _money = NumberFormat.decimalPattern('en_IN');
final _date = DateFormat('d MMM yyyy');
final _dateShort = DateFormat('d MMM');
final _iso = DateFormat('yyyy-MM-dd');

num toNum(Object? v) => v == null ? 0 : (v is num ? v : num.tryParse(v.toString()) ?? 0);

/// ₹12,345 (no paise unless present).
String rupees(Object? v) {
  final n = toNum(v);
  final s = n == n.roundToDouble() ? _money.format(n.round()) : _money.format(n);
  return '₹$s';
}

DateTime? toDate(Object? v) => v == null ? null : (v is DateTime ? v : DateTime.tryParse(v.toString()));
String fmtDate(Object? v) => toDate(v) == null ? '-' : _date.format(toDate(v)!);
String fmtDateShort(Object? v) => toDate(v) == null ? '-' : _dateShort.format(toDate(v)!);
String isoDate(DateTime d) => _iso.format(d);

/// Today's calendar date in India (the device is assumed to be in IST, but be safe).
DateTime todayIst() {
  final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
  return DateTime(now.year, now.month, now.day);
}

/// Keeps the last 10 digits of an Indian mobile number.
String normalizePhone(String phone) {
  final d = phone.replaceAll(RegExp(r'\D'), '');
  return d.length > 10 ? d.substring(d.length - 10) : d;
}
