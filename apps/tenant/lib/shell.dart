import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

import 'screens/bills.dart';
import 'screens/hisaab.dart';
import 'screens/home.dart';
import 'screens/more.dart';
import 'util.dart';

/// What every tab needs: the login, its tenancies (from v_tenancy_summary) and settings.
class TenantData {
  TenantData({required this.me, required this.tenancies, required this.settings});
  final Json me;
  final List<Json> tenancies;
  final Json settings;

  String get userId => me['id'].toString();
  String? get tenantId => me['tenant_id']?.toString();
}

/// Syncs the chosen language to the server so the owner's reminders use it. Best effort.
void syncLanguage(String code) {
  KirayaApi.instance.setMyLanguage(code).catchError((_) {});
}

/// Signed-in app: loads the login + tenancies once and shows 4 bottom tabs.
class TenantShell extends StatefulWidget {
  const TenantShell({super.key, required this.onLogout});
  final Future<void> Function() onLogout;

  @override
  State<TenantShell> createState() => _TenantShellState();
}

class _TenantShellState extends State<TenantShell> {
  final _api = KirayaApi.instance;
  TenantData? _data;
  Object? _error;
  String? _tenancyId;
  int _tab = 0;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) promptUpdate(context, 'tenant');
    });
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final me = await KirayaAuth.me();
      if (me == null || me['role'] != 'TENANT' || me['active'] == false) {
        if (mounted) showMessage(context, tr('no_access'), error: true);
        await widget.onLogout();
        return;
      }
      final res = await Future.wait<Object>([
        _api.tenancySummaries(liveOnly: false),
        _api.settings().catchError((_) => <String, dynamic>{}),
      ]);
      final tenancies = res[0] as List<Json>;
      if (!mounted) return;
      setState(() {
        _data = TenantData(me: me, tenancies: tenancies, settings: res[1] as Json);
        if (!tenancies.any((t) => t['tenancy_id'] == _tenancyId)) {
          _tenancyId = pickTenancy(tenancies)?['tenancy_id']?.toString();
        }
        _gen++;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _select(String tenancyId) => setState(() {
        _tenancyId = tenancyId;
        _tab = 0;
        _gen++;
      });

  Future<void> _logout() async {
    if (await confirm(context, tr('logout_confirm'), yes: tr('logout'))) await widget.onLogout();
  }

  Widget _message(String text, IconData icon) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          EmptyState(text: text, icon: icon),
          BigButton(label: tr('retry'), icon: Icons.refresh, onPressed: _load),
          const SizedBox(height: 12),
          BigButton(label: tr('logout'), icon: Icons.logout, outlined: true, onPressed: widget.onLogout),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final appBar = AppBar(
      title: Text(tr('app_tenant')),
      actions: [LanguageButton(onChanged: syncLanguage)],
    );
    if (data == null) {
      return Scaffold(
        appBar: appBar,
        body: _error == null
            ? const Center(child: CircularProgressIndicator())
            : _message(friendlyError(_error!), Icons.cloud_off),
      );
    }
    final tenancy = data.tenancies.where((t) => t['tenancy_id'] == _tenancyId).firstOrNull;
    if (tenancy == null) {
      return Scaffold(appBar: appBar, body: _message(tr('no_room'), Icons.meeting_room_outlined));
    }
    final key = ValueKey('$_tenancyId/$_gen/$_tab');
    final body = switch (_tab) {
      0 => HomeTab(key: key, data: data, tenancy: tenancy),
      1 => BillsTab(key: key, tenancyId: _tenancyId!),
      2 => HisaabTab(key: key, tenancyId: _tenancyId!),
      _ => MoreTab(
          key: key,
          data: data,
          tenancy: tenancy,
          onChanged: _load,
          onSelectTenancy: _select,
          onLogout: _logout,
        ),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text('${tr('app_tenant')} · ${tr('room_n', {'n': tenancy['room_number']})}'),
        actions: [LanguageButton(onChanged: syncLanguage)],
      ),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: tr('home')),
          NavigationDestination(
              icon: const Icon(Icons.receipt_outlined), selectedIcon: const Icon(Icons.receipt), label: tr('bills')),
          NavigationDestination(
              icon: const Icon(Icons.menu_book_outlined), selectedIcon: const Icon(Icons.menu_book), label: tr('ledger')),
          NavigationDestination(icon: const Icon(Icons.more_horiz), label: tr('more')),
        ],
      ),
    );
  }
}
