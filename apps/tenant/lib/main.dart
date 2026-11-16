import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

import 'shell.dart';
import 'strings.dart';
import 'theme.dart';

Future<void> main() async {
  registerTenantStrings();
  final ok = await initKiraya();
  runApp(ok ? const TenantApp() : const NotConfiguredApp());
}

class TenantApp extends StatelessWidget {
  const TenantApp({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Lang.instance,
        builder: (context, _) => MaterialApp(
          title: tr('app_tenant'),
          debugShowCheckedModeBanner: false,
          theme: tenantTheme(),
          builder: (context, child) => RelabelOnLangChange(child: child ?? const SizedBox()),
          home: const AuthGate(),
        ),
      );
}

/// Rebuilds every widget below it (including pushed routes) when the language changes,
/// so const widgets that call tr() switch language instantly without losing state.
class RelabelOnLangChange extends StatefulWidget {
  const RelabelOnLangChange({super.key, required this.child});
  final Widget child;

  @override
  State<RelabelOnLangChange> createState() => _RelabelOnLangChangeState();
}

class _RelabelOnLangChangeState extends State<RelabelOnLangChange> {
  @override
  void initState() {
    super.initState();
    Lang.instance.addListener(_relabel);
  }

  @override
  void dispose() {
    Lang.instance.removeListener(_relabel);
    super.dispose();
  }

  void _relabel() {
    if (!mounted) return;
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    (context as Element).visitChildren(mark);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Login when signed out; straight to the app when a saved session exists.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _signedIn = KirayaAuth.session != null;

  Future<void> _login(String phone, String pin) async {
    await KirayaAuth.signIn(phone, pin);
    final me = await KirayaAuth.me();
    if (me == null || me['role'] != 'TENANT' || me['active'] == false) {
      await KirayaAuth.signOut();
      throw Exception(tr('no_access'));
    }
    final lang = me['language']?.toString();
    if (lang != null && lang != Lang.instance.code) await Lang.instance.set(lang);
    if (mounted) setState(() => _signedIn = true);
  }

  Future<void> _logout() async {
    try {
      await KirayaAuth.signOut();
    } catch (_) {}
    if (mounted) setState(() => _signedIn = false);
  }

  @override
  Widget build(BuildContext context) =>
      _signedIn ? TenantShell(onLogout: _logout) : LoginScreen(title: tr('app_tenant'), onSubmit: _login);
}
