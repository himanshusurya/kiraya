import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiraya_core/kiraya_core.dart';
import 'package:kiraya_owner/screens2/people_screen.dart' show kKycKinds;
import 'package:kiraya_owner/screens2/person_form.dart';
import 'package:kiraya_owner/screens2/settings_screen.dart' show kRoomStatuses;
import 'package:kiraya_owner/screens2/strings2.dart';
import 'package:material_ui/material_ui.dart';

const _settingKeys = [
  'electricity_rate', 'cleaning_charge', 'default_advance', 'late_fee', 'due_after_bill_days', 'grace_days',
  'notice_period_days', 'meter_reading_day', 'upi_id', 'upi_name', 'owner_phone', 'reminder_en', 'reminder_hi',
  'auto_issue', 'language_default',
];

bool _has(String key) => tr(key) != key;

void main() {
  setUpAll(registerStrings2);

  test('every English string has a Hindi version', () {
    expect(Lang.instance.missingHindi().toList(), isEmpty);
  });

  test('every literal tr() key in screens2 exists', () {
    final keyRe = RegExp(r"""tr\(\s*'([A-Za-z0-9_]+)'""");
    final missing = <String>{};
    for (final f in Directory('lib/screens2').listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      for (final m in keyRe.allMatches(f.readAsStringSync())) {
        if (!_has(m.group(1)!)) missing.add('${m.group(1)} (${f.uri.pathSegments.last})');
      }
    }
    expect(missing, isEmpty);
  });

  test('dynamic key families exist', () {
    final keys = [
      for (final k in kPersonFields) 's2_f_$k',
      for (final g in kGenders) 's2_gender_$g',
      for (final i in kIdTypes) 's2_id_$i',
      for (final k in kKycKinds) 's2_kyc_$k',
      for (final s in kRoomStatuses) 's2_rstatus_$s',
      for (final s in _settingKeys) ...['s2_set_$s', 's2_set_${s}_help'],
      for (var m = 1; m <= 12; m++) 's2_month_$m',
      for (final s in ['stay', 'people', 'charges', 'review']) 's2_step_$s',
      for (final p in ['fan', 'cooler', 'tv', 'fridge', 'medicine', 'discount']) 's2_preset_$p',
    ];
    expect(keys.where((k) => !_has(k)).toList(), isEmpty);
  });

  Future<List<Json>> pumpForm(WidgetTester tester, {Json? initial}) async {
    final emitted = <Json>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: PersonForm(initial: initial, onChanged: emitted.add)),
      ),
    ));
    await tester.pump();
    return emitted;
  }

  testWidgets('PersonForm emits name and phone, omits empty fields', (tester) async {
    final emitted = await pumpForm(tester);
    await tester.enterText(find.byKey(const Key('pf_full_name')), 'Ramesh Kumar');
    await tester.enterText(find.byKey(const Key('pf_phone')), '9876543210');
    await tester.pump();

    final last = emitted.last;
    expect(last['full_name'], 'Ramesh Kumar');
    expect(last['phone'], '9876543210');
    expect(last.containsKey('father_name'), isFalse);
    expect(isPersonValid(last), isTrue);
  });

  testWidgets('PersonForm keeps initial values', (tester) async {
    final emitted = await pumpForm(tester, initial: {
      'full_name': 'Sita Devi',
      'phone': '9123456780',
      'caste': 'OBC',
      'gender': 'FEMALE',
    });
    expect(emitted, isNotEmpty);
    expect(emitted.last, containsPair('full_name', 'Sita Devi'));
    expect(emitted.last, containsPair('caste', 'OBC'));
    expect(emitted.last, containsPair('gender', 'FEMALE'));
    expect(find.text('Sita Devi'), findsOneWidget);
  });
}
