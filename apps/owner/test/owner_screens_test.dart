import 'package:flutter_test/flutter_test.dart';
import 'package:kiraya_core/kiraya_core.dart';
import 'package:kiraya_owner/screens/payment_screen.dart';
import 'package:kiraya_owner/screens/tenancy_dialogs.dart';
import 'package:kiraya_owner/screens2/strings2.dart';
import 'package:kiraya_owner/strings.dart';
import 'package:material_ui/material_ui.dart';

Widget _app(Widget home) => MaterialApp(theme: kirayaTheme(), home: home);

void main() {
  setUpAll(() {
    registerOwnerStrings();
    registerStrings2();
  });

  testWidgets('payment screen prefills balance and totals split payments', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const PaymentScreen(
      summary: {'tenancy_id': 't1', 'room_number': '101', 'balance': 2980},
    )));
    expect(find.text(tr('total')), findsOneWidget);
    expect(find.text(rupees(2980)), findsOneWidget);

    await tester.tap(find.text(tr('add_split')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), '500');
    await tester.pumpAndSettle();
    expect(find.text(rupees(3480)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('charge sheet quick chips fill name and amount', (tester) async {
    await tester.pumpWidget(_app(Builder(
      builder: (c) => Scaffold(body: TextButton(onPressed: () => showChargeDialog(c, 't1'), child: const Text('open'))),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fan'));
    await tester.pump();
    expect(find.widgetWithText(TextFormField, 'Fan'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '420'), findsOneWidget);
  });
}
