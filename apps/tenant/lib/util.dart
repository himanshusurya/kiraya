import 'dart:math';

import 'package:kiraya_core/kiraya_core.dart';

const liveStatuses = {'ACTIVE', 'ON_NOTICE'};

bool isLive(Json tenancy) => liveStatuses.contains(tenancy['status']);

DateTime _startOf(Json t) => toDate(t['start_date']) ?? DateTime(1970);

/// The tenancy to show by default: the newest live one (ACTIVE / ON_NOTICE),
/// otherwise the newest of any status (e.g. CLOSED after moving out).
Json? pickTenancy(List<Json> rows) {
  if (rows.isEmpty) return null;
  int newestFirst(Json a, Json b) => _startOf(b).compareTo(_startOf(a));
  final live = rows.where(isLive).toList()..sort(newestFirst);
  if (live.isNotEmpty) return live.first;
  return ([...rows]..sort(newestFirst)).first;
}

/// Setting values come back as JSON (string or number); empty string when missing.
String settingText(Json settings, String key) {
  final v = settings[key];
  return v == null ? '' : v.toString().trim();
}

int noticePeriodDays(Json settings) {
  final n = toNum(settings['notice_period_days']).round();
  return n > 0 ? n : 30;
}

int daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// How many days short of the notice period a leaving date is (0 = enough notice).
int noticeShortBy(int periodDays, DateTime today, DateTime leaveOn) => max(periodDays - daysBetween(today, leaveOn), 0);

/// Random UUID v4 – used for idempotency keys and upload file names.
String randomId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Plain number for an input box: 3500 or 3500.50.
String amountText(num n) => n == n.roundToDouble() ? n.round().toString() : n.toStringAsFixed(2);

/// Status line for a tenancy: "Staying", "Leaving on 30 Nov 2026", "Left", ...
String tenancyStatusText(Json t) {
  final status = t['status']?.toString() ?? '';
  if (status == 'ON_NOTICE' && t['leave_on'] != null) return tr('leaving_on', {'d': fmtDate(t['leave_on'])});
  return tr('tstatus_$status');
}
