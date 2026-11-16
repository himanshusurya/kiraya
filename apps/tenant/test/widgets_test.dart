import 'package:flutter_test/flutter_test.dart';
import 'package:kiraya_core/kiraya_core.dart';
import 'package:kiraya_tenant/main.dart';
import 'package:kiraya_tenant/screens/give_notice.dart';
import 'package:kiraya_tenant/screens/home.dart';
import 'package:kiraya_tenant/screens/pay_claim.dart';
import 'package:kiraya_tenant/strings.dart';
import 'package:kiraya_tenant/theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(Widget body) => MaterialApp(
      theme: tenantTheme(),
      builder: (context, child) => RelabelOnLangChange(child: child!),
      home: Scaffold(body: body),
    );

void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

class _HomeLabel extends StatelessWidget {
  const _HomeLabel();
  @override
  Widget build(BuildContext context) => Text(tr('home'));
}

void main() {
  setUpAll(registerTenantStrings);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Lang.instance.set('en');
  });

  group('HomeView', () {
    final pending = {
      'status': 'PENDING_CONFIRM',
      'amount': 3500,
      'paid_on': '2026-11-16',
      'payment_split': [
        {'mode': 'PHONEPE', 'amount': 3500, 'ref': 'T123'},
      ],
    };
    final bill = {
      'status': 'ISSUED',
      'cycle_start': '2026-11-01',
      'cycle_end': '2026-11-30',
      'due_date': '2026-11-05',
      'total': 3500,
      'bill_line': [
        {'kind': 'RENT', 'label': 'Rent', 'amount': 3000, 'sort': 0},
        {'kind': 'ELECTRICITY', 'label': 'Light', 'qty': 40, 'rate': 12.5, 'amount': 500, 'sort': 1},
      ],
    };

    testWidgets('live tenancy shows balance, actions, pending claim and latest bill', (tester) async {
      _tallScreen(tester);
      var claims = 0;
      await tester.pumpWidget(_app(HomeView(
        summary: const {
          'tenancy_id': 't1',
          'room_number': '101',
          'status': 'ON_NOTICE',
          'leave_on': '2026-12-31',
          'balance': 3500,
          'advance_held': 5000,
          'monthly_rent': 3000,
          'next_bill_date': '2026-12-01',
        },
        settings: const {'owner_phone': '9876543210', 'upi_id': 'owner@upi'},
        pendingClaims: [pending],
        latestBill: bill,
        onPay: () {},
        onClaim: () => claims++,
        onCall: () {},
        onWhatsApp: () {},
      )));

      expect(find.text('Room 101'), findsOneWidget);
      expect(find.text('Leaving on 31 Dec 2026'), findsOneWidget);
      expect(find.text('To pay ₹3,500'), findsOneWidget);
      expect(find.text('₹5,000'), findsOneWidget);
      expect(find.text('Pay now (UPI)'), findsOneWidget);
      expect(find.text('Waiting for owner to confirm'), findsOneWidget);
      expect(find.text('Waiting'), findsOneWidget);
      expect(find.text('Ref: T123'), findsOneWidget);
      expect(find.text('Call owner'), findsOneWidget);
      expect(find.text('Latest bill'), findsOneWidget);
      expect(find.text('Not paid'), findsOneWidget);

      await tester.tap(find.text('I have paid'));
      expect(claims, 1);
    });

    testWidgets('closed tenancy shows settlement and no pay buttons', (tester) async {
      _tallScreen(tester);
      await tester.pumpWidget(_app(const HomeView(
        summary: {'tenancy_id': 't0', 'room_number': '102', 'status': 'CLOSED', 'balance': 0, 'advance_held': 0},
        settings: {},
        settlement: {
          'leave_date': '2026-10-31',
          'advance_applied': 2000,
          'refund_amount': 3000,
          'written_off': 0,
          'balance_after': 0,
          'outcome': 'REFUNDED',
        },
      )));
      expect(find.text('All paid'), findsOneWidget);
      expect(find.text('Left'), findsOneWidget);
      expect(find.text('Advance returned'), findsOneWidget);
      expect(find.text('₹3,000'), findsOneWidget);
      expect(find.text('Pay now (UPI)'), findsNothing);
      expect(find.text('Call owner'), findsNothing);
    });
  });

  group('PayClaimForm', () {
    testWidgets('prefills the balance and sends one idempotency key per form', (tester) async {
      _tallScreen(tester);
      final sent = <PayClaim>[];
      await tester.pumpWidget(_app(PayClaimForm(
        balance: 3500,
        today: DateTime(2026, 11, 17),
        onSubmit: (c) async => sent.add(c),
      )));

      expect(find.widgetWithText(TextFormField, '3500'), findsOneWidget);
      await tester.tap(find.text('GPay'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextFormField, 'UPI ref / transaction ID (optional)'), 'UTR99');
      await tester.tap(find.text('Send to owner'));
      await tester.pump();
      await tester.tap(find.text('Send to owner'));
      await tester.pump();

      expect(sent, hasLength(2));
      expect(sent.first.amount, 3500);
      expect(sent.first.mode, 'GPAY');
      expect(sent.first.ref, 'UTR99');
      expect(sent.first.paidOn, DateTime(2026, 11, 17));
      expect(sent.first.idempotencyKey, isNotEmpty);
      expect(sent.last.idempotencyKey, sent.first.idempotencyKey);
    });

    testWidgets('cash hides the UPI ref and empty amount is rejected', (tester) async {
      _tallScreen(tester);
      final sent = <PayClaim>[];
      await tester.pumpWidget(_app(PayClaimForm(balance: 0, today: DateTime(2026, 11, 17), onSubmit: (c) async => sent.add(c))));

      await tester.tap(find.text('Cash'));
      await tester.pump();
      expect(find.text('UPI ref / transaction ID (optional)'), findsNothing);
      await tester.tap(find.text('Send to owner'));
      await tester.pump();
      expect(find.text('Please fill this'), findsOneWidget);
      expect(sent, isEmpty);
    });
  });

  testWidgets('GiveNoticeForm warns when notice is short', (tester) async {
    _tallScreen(tester);
    final today = DateTime(2026, 11, 17);
    await tester.pumpWidget(_app(GiveNoticeForm(
      periodDays: 30,
      today: today,
      initialLeaveOn: DateTime(2026, 11, 27),
      onSubmit: (_, _) async {},
    )));
    expect(find.text('Notice period: 30 days'), findsOneWidget);
    expect(find.text('Notice is 20 days short; owner may charge for it'), findsOneWidget);

    await tester.pumpWidget(_app(GiveNoticeForm(key: UniqueKey(), periodDays: 30, today: today, onSubmit: (_, _) async {})));
    expect(find.text('Notice period is complete'), findsOneWidget);
  });

  testWidgets('switching language relabels const widgets instantly', (tester) async {
    await tester.pumpWidget(_app(const _HomeLabel()));
    expect(find.text('Home'), findsOneWidget);
    await tester.runAsync(() => Lang.instance.set('hi'));
    await tester.pump();
    expect(find.text('होम'), findsOneWidget);
    await tester.runAsync(() => Lang.instance.set('en'));
    await tester.pump();
    expect(find.text('Home'), findsOneWidget);
  });
}
