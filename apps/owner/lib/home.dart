import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'screens/bills_screen.dart';
import 'screens/claims_screen.dart';
import 'screens/readings_screen.dart';
import 'screens/rooms_screen.dart';
import 'screens/tenancy_screen.dart';
import 'screens2/complaints_screen.dart';
import 'screens2/logins_screen.dart';
import 'screens2/notices_screen.dart';
import 'screens2/reports_screen.dart';
import 'screens2/settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => promptUpdate(context, 'owner'));
  }

  @override
  Widget build(BuildContext context) {
    final pages = [const RoomsScreen(), const BillsScreen(), const ReadingsScreen(), const MoreScreen()];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.meeting_room_outlined), label: tr('tab_rooms')),
          NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), label: tr('tab_bills')),
          NavigationDestination(icon: const Icon(Icons.electric_meter_outlined), label: tr('tab_readings')),
          NavigationDestination(icon: const Icon(Icons.menu), label: tr('tab_more')),
        ],
      ),
    );
  }
}

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  void _push(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String key, Widget page) =>
        ListTile(leading: Icon(icon, size: 30), title: Text(tr(key)), onTap: () => _push(context, page),
            trailing: const Icon(Icons.chevron_right));
    return Scaffold(
      appBar: AppBar(title: Text(tr('more')), actions: const [LanguageButton()]),
      body: ListView(children: [
        item(Icons.verified_outlined, 'claims', const ClaimsScreen()),
        item(Icons.report_problem_outlined, 'complaints', const ComplaintsScreen()),
        item(Icons.campaign_outlined, 'notices', const NoticesScreen()),
        item(Icons.bar_chart, 'reports', ReportsScreen(onOpenTenancy: (id) => _push(context, TenancyScreen(tenancyId: id)))),
        item(Icons.history, 'all_tenants', const AllTenanciesScreen()),
        item(Icons.key_outlined, 'logins', const LoginsScreen()),
        item(Icons.settings_outlined, 'settings', const SettingsScreen()),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.system_update, size: 30),
          title: Text(tr('check_update')),
          subtitle: FutureBuilder(
            future: PackageInfo.fromPlatform(),
            builder: (_, s) => Text(s.hasData ? tr('version', {'v': s.data!.version}) : ''),
          ),
          onTap: () => promptUpdate(context, 'owner'),
        ),
        ListTile(
          leading: const Icon(Icons.logout, size: 30),
          title: Text(tr('logout')),
          onTap: () async {
            if (await confirm(context, tr('logout'))) await KirayaAuth.signOut();
          },
        ),
      ]),
    );
  }
}

/// Every tenancy ever, including those who left (search by name / room).
class AllTenanciesScreen extends StatefulWidget {
  const AllTenanciesScreen({super.key});

  @override
  State<AllTenanciesScreen> createState() => _AllTenanciesScreenState();
}

class _AllTenanciesScreenState extends State<AllTenanciesScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('all_tenants'))),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), labelText: tr('search')),
              onChanged: (v) => setState(() => _q = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: Loader<List<Json>>(
              load: () => KirayaApi.instance.tenancySummaries(liveOnly: false),
              builder: (context, rows, _) {
                final list = rows
                    .where((r) => _q.isEmpty ||
                        '${r['primary_name']} ${r['room_number']} ${r['primary_phone']}'.toLowerCase().contains(_q))
                    .toList()
                  ..sort((a, b) => (b['start_date'] as String).compareTo(a['start_date'] as String));
                if (list.isEmpty) return ListView(children: const [EmptyState()]);
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final r = list[i];
                    return ListTile(
                      leading: CircleAvatar(child: Text('${r['room_number']}', style: const TextStyle(fontSize: 12))),
                      title: Text('${r['primary_name'] ?? '-'}'),
                      subtitle: Text('${tr('tstatus_${r['status']}')} · ${tr('since', {'d': fmtDate(r['start_date'])})}'),
                      trailing: BalanceText(r['balance']),
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute<void>(builder: (_) => TenancyScreen(tenancyId: r['tenancy_id'] as String))),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      );
}
