import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'i18n.dart';
import 'theme.dart';

/// Common start-up for both apps. Returns false when the build has no backend config.
Future<bool> initKiraya() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Lang.instance.load();
  await initializeDateFormatting('en_IN');
  if (!AppConfig.isConfigured) return false;
  await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
  return true;
}

/// Shown when the APK was built without SUPABASE_URL / SUPABASE_ANON_KEY.
class NotConfiguredApp extends StatelessWidget {
  const NotConfiguredApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: kirayaTheme(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(tr('not_configured'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
            ),
          ),
        ),
      );
}

/// Phone + PIN login form shared by both apps. [onLoggedIn] validates the role.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.title, required this.onSubmit});
  final String title;
  final Future<void> Function(String phone, String pin) onSubmit;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _pin = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;

  Future<void> _go() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_phone.text.trim(), _pin.text.trim());
    } catch (e) {
      if (mounted) setState(() => _error = e is AuthException ? tr('wrong_login') : e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _form,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Lang.instance.set(Lang.instance.isHindi ? 'en' : 'hi'),
                      child: Text(Lang.instance.isHindi ? 'English' : 'हिंदी'),
                    ),
                  ),
                  Icon(Icons.home_work_rounded, size: 72, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 8),
                  Text(widget.title, style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(labelText: tr('phone'), prefixText: '+91 '),
                    validator: (v) => (v ?? '').replaceAll(RegExp(r'\D'), '').length < 10 ? tr('required') : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _pin,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 6,
                    decoration: InputDecoration(labelText: tr('pin'), helperText: tr('pin_hint')),
                    validator: (v) => RegExp(r'^\d{6}$').hasMatch(v ?? '') ? null : tr('required'),
                    onFieldSubmitted: (_) => _go(),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!, style: const TextStyle(color: kBad)),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _go,
                      child: _busy ? const CircularProgressIndicator() : Text(tr('login')),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}
