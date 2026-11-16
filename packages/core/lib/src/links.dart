import 'package:url_launcher/url_launcher.dart';

import 'format.dart';

/// Free WhatsApp: opens WhatsApp with a ready message (the owner taps Send). No API cost.
Uri whatsappUri(String phone, String text) {
  final p = normalizePhone(phone);
  return Uri.parse('https://wa.me/${p.length == 10 ? '91$p' : p}?text=${Uri.encodeComponent(text)}');
}

/// UPI deep link (PhonePe / GPay / Paytm all handle it). No gateway, no commission.
Uri upiUri({required String upiId, required String name, num? amount, String? note}) => Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: {
        'pa': upiId,
        'pn': name,
        if (amount != null && amount > 0) 'am': amount.toStringAsFixed(2),
        'cu': 'INR',
        if (note != null && note.isNotEmpty) 'tn': note,
      },
    );

Uri callUri(String phone) => Uri(scheme: 'tel', path: normalizePhone(phone));

Future<bool> openUri(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// Fills {name} {room} {due} {date} placeholders of the reminder templates in Settings.
String fillTemplate(String template, Map<String, String> values) {
  var s = template;
  values.forEach((k, v) => s = s.replaceAll('{$k}', v));
  return s;
}
