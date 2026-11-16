import 'package:supabase_flutter/supabase_flutter.dart';

import 'format.dart';

/// Phone + 6-digit PIN login. Accounts are created by the owner app through the
/// `manage-login` edge function using the same synthetic e-mail scheme.
class KirayaAuth {
  static String phoneToEmail(String phone) => 'p${normalizePhone(phone)}@login.kiraya.app';

  static SupabaseClient get _sb => Supabase.instance.client;

  static Session? get session => _sb.auth.currentSession;

  static Future<void> signIn(String phone, String pin) async {
    await _sb.auth.signInWithPassword(email: phoneToEmail(phone), password: pin);
  }

  static Future<void> signOut() => _sb.auth.signOut();

  /// The app_user row for the signed-in login (role, language, tenant_id ...).
  static Future<Map<String, dynamic>?> me() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;
    return await _sb.from('app_user').select().eq('id', uid).maybeSingle();
  }
}
