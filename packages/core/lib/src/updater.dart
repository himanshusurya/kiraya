import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'config.dart';
import 'i18n.dart';
import 'links.dart';

class UpdateInfo {
  UpdateInfo(this.version, this.url);
  final String version;
  final Uri url;
}

/// Compares "1.2.3" style versions. Returns >0 if a is newer than b.
int compareVersions(String a, String b) {
  List<int> parts(String v) =>
      v.replaceFirst(RegExp(r'^[^0-9]*'), '').split(RegExp(r'[.+-]')).take(3).map((p) => int.tryParse(p) ?? 0).toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// Checks the GitHub "latest release" for a newer APK whose file name contains [apkTag]
/// (e.g. "owner" or "tenant"). Free alternative to the Play Store update flow.
Future<UpdateInfo?> checkForUpdate(String apkTag) async {
  if (AppConfig.githubRepo.isEmpty) return null;
  try {
    final res = await http
        .get(Uri.parse('https://api.github.com/repos/${AppConfig.githubRepo}/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = j['tag_name']?.toString() ?? '';
    final info = await PackageInfo.fromPlatform();
    if (compareVersions(tag, info.version) <= 0) return null;
    final assets = (j['assets'] as List? ?? const []).cast<Map<String, dynamic>>();
    final apk = assets.where((a) => a['name'].toString().contains(apkTag) && a['name'].toString().endsWith('.apk'));
    final url = apk.isNotEmpty ? apk.first['browser_download_url'].toString() : j['html_url'].toString();
    return UpdateInfo(tag.replaceFirst('v', ''), Uri.parse(url));
  } catch (_) {
    return null;
  }
}

Future<void> promptUpdate(BuildContext context, String apkTag) async {
  final u = await checkForUpdate(apkTag);
  if (u == null || !context.mounted) return;
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('update_available', {'v': u.version})),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('later'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('update_now'))),
      ],
    ),
  );
  if (go == true) await openUri(u.url);
}
