import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'home.dart';
import 'screens2/strings2.dart';
import 'strings.dart';

Future<void> main() async {
  registerOwnerStrings();
  registerStrings2();
  final ok = await initKiraya();
  runApp(ok ? const OwnerApp() : const NotConfiguredApp());
}

class OwnerApp extends StatelessWidget {
  const OwnerApp({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Lang.instance,
        builder: (context, _) => MaterialApp(
          title: tr('app_owner'),
          debugShowCheckedModeBanner: false,
          theme: kirayaTheme(),
          home: const AuthGate(),
        ),
      );
}

/// Login when signed out; owner check when signed in.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Future<void> _login(String phone, String pin) async {
    await KirayaAuth.signIn(phone, pin);
    final me = await KirayaAuth.me();
    if (me == null || me['role'] != 'OWNER') {
      await KirayaAuth.signOut();
      throw Exception(tr('not_owner'));
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, _) => KirayaAuth.session == null
            ? LoginScreen(title: tr('app_owner'), onSubmit: _login)
            : const HomeShell(),
      );
}
