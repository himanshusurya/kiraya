import 'package:flutter_test/flutter_test.dart';
import 'package:kiraya_core/kiraya_core.dart';

void main() {
  test('every English string has a Hindi version', () {
    expect(Lang.instance.missingHindi().toList(), isEmpty);
  });

  test('rupees uses Indian grouping', () {
    expect(rupees(123456), '₹1,23,456');
    expect(rupees('2500.00'), '₹2,500');
  });

  test('phone login email matches the edge function', () {
    expect(KirayaAuth.phoneToEmail('+91 98765-43210'), 'p9876543210@login.kiraya.app');
  });

  test('whatsapp and upi links', () {
    expect(whatsappUri('9876543210', 'Hi Ram').toString(), 'https://wa.me/919876543210?text=Hi%20Ram');
    final u = upiUri(upiId: 'owner@ybl', name: 'Owner', amount: 2980, note: 'Room 101');
    expect(u.scheme, 'upi');
    expect(u.queryParameters['am'], '2980.00');
    expect(u.queryParameters['pa'], 'owner@ybl');
  });

  test('version compare', () {
    expect(compareVersions('v1.2.0', '1.1.9') > 0, isTrue);
    expect(compareVersions('1.0.0', '1.0.0'), 0);
    expect(compareVersions('0.9.0', '1.0.0') < 0, isTrue);
  });

  test('template fill', () {
    expect(fillTemplate('Hi {name}, room {room} due {due}', {'name': 'Ram', 'room': '101', 'due': '₹500'}),
        'Hi Ram, room 101 due ₹500');
  });

  test('theme builds with scaled text (no debug assertion)', () {
    final t = kirayaTheme();
    expect(t.textTheme.bodyMedium!.fontSize, closeTo(14 * 1.12, 0.01));
  });
}
