import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiraya_core/kiraya_core.dart';
import 'package:kiraya_owner/screens2/strings2.dart';
import 'package:kiraya_owner/strings.dart';

void main() {
  setUpAll(() {
    registerOwnerStrings();
    registerStrings2();
  });

  test('every English string has a Hindi version', () {
    expect(Lang.instance.missingHindi().toList(), isEmpty);
  });

  test('every tr() key used in the owner app exists', () {
    final used = <String>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      used.addAll(RegExp(r"""tr\('([a-zA-Z0-9_]+)'""").allMatches(f.readAsStringSync()).map((m) => m.group(1)!));
    }
    final missing = used.where((k) => Lang.instance.t(k) == k).toList()..sort();
    expect(missing, isEmpty);
  });

  test('Hindi strings keep the same {placeholders}', () async {
    final ph = RegExp(r'\{(\w+)\}');
    Set<String> names(String s) => ph.allMatches(s).map((m) => m.group(1)!).toSet();
    final en = <String, String>{}, hi = <String, String>{};
    final keys = Lang.instance.allKeys();
    for (final k in keys) {
      en[k] = Lang.instance.raw('en', k)!;
      hi[k] = Lang.instance.raw('hi', k) ?? '';
    }
    final bad = keys.where((k) => names(en[k]!).difference(names(hi[k]!)).isNotEmpty).toList();
    expect(bad, isEmpty);
  });
}
