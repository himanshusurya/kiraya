import 'package:flutter_test/flutter_test.dart';
import 'package:kiraya_core/kiraya_core.dart';
import 'package:kiraya_tenant/strings.dart';
import 'package:kiraya_tenant/util.dart';

void main() {
  setUpAll(registerTenantStrings);

  test('every string has a Hindi version', () {
    expect(Lang.instance.missingHindi(), isEmpty);
    expect(tenantHi.keys.toSet(), tenantEn.keys.toSet());
  });

  group('pickTenancy', () {
    test('prefers the live tenancy over a newer closed one', () {
      final picked = pickTenancy([
        {'tenancy_id': 'old', 'status': 'SHIFTED', 'start_date': '2026-01-01'},
        {'tenancy_id': 'live', 'status': 'ON_NOTICE', 'start_date': '2025-06-01'},
        {'tenancy_id': 'newest-closed', 'status': 'CLOSED', 'start_date': '2026-08-01'},
      ]);
      expect(picked?['tenancy_id'], 'live');
    });

    test('falls back to the latest tenancy when none is live', () {
      final picked = pickTenancy([
        {'tenancy_id': 'a', 'status': 'SHIFTED', 'start_date': '2025-01-01'},
        {'tenancy_id': 'b', 'status': 'CLOSED', 'start_date': '2026-03-01'},
      ]);
      expect(picked?['tenancy_id'], 'b');
      expect(pickTenancy([]), isNull);
    });
  });

  test('noticeShortBy counts calendar days', () {
    final today = DateTime(2026, 11, 17);
    expect(noticeShortBy(30, today, DateTime(2026, 11, 27)), 20);
    expect(noticeShortBy(30, today, DateTime(2026, 12, 17)), 0);
    expect(noticeShortBy(30, today, DateTime(2027, 1, 30)), 0);
  });

  test('noticePeriodDays defaults to 30 and reads JSON strings', () {
    expect(noticePeriodDays({}), 30);
    expect(noticePeriodDays({'notice_period_days': '15'}), 15);
  });

  test('randomId is a unique UUID v4', () {
    final a = randomId(), b = randomId();
    expect(a, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(a, isNot(b));
  });
}
