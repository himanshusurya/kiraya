import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../shell.dart';
import '../util.dart';
import 'charges.dart';
import 'complaints.dart';
import 'give_notice.dart';
import 'notices.dart';
import 'profile.dart';

final _packageInfo = PackageInfo.fromPlatform();

class MoreTab extends StatelessWidget {
  const MoreTab({
    super.key,
    required this.data,
    required this.tenancy,
    required this.onChanged,
    required this.onSelectTenancy,
    required this.onLogout,
  });
  final TenantData data;
  final Json tenancy;
  final Future<void> Function() onChanged;
  final ValueChanged<String> onSelectTenancy;
  final VoidCallback onLogout;

  String get _id => tenancy['tenancy_id'].toString();

  void _open(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));

  Future<void> _pickRoom(BuildContext context) async {
    final rows = [...data.tenancies]
      ..sort((a, b) => (toDate(b['start_date']) ?? DateTime(1970)).compareTo(toDate(a['start_date']) ?? DateTime(1970)));
    final id = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          SectionTitle(tr('my_rooms')),
          for (final t in rows)
            ListTile(
              leading: Icon(t['tenancy_id'] == _id ? Icons.radio_button_checked : Icons.radio_button_off),
              title: Text(tr('room_n', {'n': t['room_number']})),
              subtitle: Text('${tenancyStatusText(t)} · ${tr('from_date', {'d': fmtDate(t['start_date'])})}'),
              onTap: () => Navigator.pop(c, t['tenancy_id'].toString()),
            ),
        ]),
      ),
    );
    if (id != null && id != _id) onSelectTenancy(id);
  }

  Future<void> _checkUpdate(BuildContext context) async {
    final u = await runBusy(context, () => checkForUpdate('tenant'));
    if (!context.mounted) return;
    if (u == null) {
      showMessage(context, tr('latest_version'));
    } else {
      await promptUpdate(context, 'tenant');
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = isLive(tenancy);
    final onNotice = tenancy['status'] == 'ON_NOTICE';
    Widget tile(IconData icon, String title, VoidCallback onTap, {String? subtitle}) => ListTile(
          leading: Icon(icon, size: 30, color: Theme.of(context).colorScheme.primary),
          title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        );

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        tile(Icons.report_problem_outlined, tr('complaints'),
            () => _open(context, ComplaintsScreen(tenancy: tenancy, userId: data.userId))),
        tile(Icons.campaign_outlined, tr('notices_owner'), () => _open(context, const NoticesScreen())),
        if (live)
          tile(
            Icons.logout,
            onNotice ? tr('change_leave_date') : tr('give_notice'),
            () => _open(
              context,
              GiveNoticeScreen(tenancyId: _id, settings: data.settings, currentLeaveOn: toDate(tenancy['leave_on']), onDone: onChanged),
            ),
            subtitle: onNotice ? tenancyStatusText(tenancy) : tr('notice_period', {'n': noticePeriodDays(data.settings)}),
          ),
        tile(Icons.playlist_add, tr('my_charges'), () => _open(context, ChargesScreen(tenancyId: _id))),
        tile(Icons.savings_outlined, tr('advance_title'), () => _open(context, AdvanceScreen(tenancyId: _id)),
            subtitle: rupees(tenancy['advance_held'])),
        tile(Icons.person_outline, tr('my_profile'),
            () => _open(context, ProfileScreen(data: data, tenancy: tenancy))),
        if (data.tenancies.length > 1)
          tile(Icons.swap_horiz, tr('my_rooms'), () => _pickRoom(context),
              subtitle: '${tr('current')}: ${tr('room_n', {'n': tenancy['room_number']})}'),
        const Divider(),
        ListTile(
          leading: Icon(Icons.translate, size: 30, color: Theme.of(context).colorScheme.primary),
          title: Text(tr('language'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'en', label: Text(tr('english'), style: const TextStyle(fontSize: 17))),
                ButtonSegment(value: 'hi', label: Text(tr('hindi'), style: const TextStyle(fontSize: 17))),
              ],
              selected: {Lang.instance.code},
              onSelectionChanged: (s) async {
                await Lang.instance.set(s.first);
                syncLanguage(s.first);
              },
            ),
          ),
        ),
        ListTile(
          leading: Icon(Icons.system_update, size: 30, color: Theme.of(context).colorScheme.primary),
          title: Text(tr('check_update'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
          subtitle: FutureBuilder<PackageInfo>(
            future: _packageInfo,
            builder: (context, snap) => Text(tr('app_version', {'v': snap.data?.version ?? '…'})),
          ),
          onTap: () => _checkUpdate(context),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: BigButton(label: tr('logout'), icon: Icons.logout, outlined: true, onPressed: onLogout),
        ),
      ],
    );
  }
}
