import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

import '../screens2/onboard_screen.dart';
import 'claims_screen.dart';
import 'tenancy_screen.dart';

/// Home: every room at a glance with who stays there and how much is due.
class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  final _loader = GlobalKey<LoaderState<List<Json>>>();

  Future<void> _reload() async => _loader.currentState?.reload();

  Future<void> _open(Json room) async {
    if (room['tenancy_id'] != null) {
      await Navigator.push(context,
          MaterialPageRoute<void>(builder: (_) => TenancyScreen(tenancyId: room['tenancy_id'] as String)));
    } else if (room['room_status'] == 'VACANT' || room['room_status'] == 'OCCUPIED') {
      final id = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => OnboardScreen(room: room)));
      if (id != null && mounted) {
        await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TenancyScreen(tenancyId: id)));
      }
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('app_owner')), actions: [LanguageButton(onChanged: (_) => _reload())]),
        body: Loader<List<Json>>(
          key: _loader,
          load: KirayaApi.instance.roomBoard,
          builder: (context, rooms, reload) {
            final occupied = rooms.where((r) => r['tenancy_id'] != null).length;
            final due = rooms.fold<num>(0, (s, r) => s + (toNum(r['balance']) > 0 ? toNum(r['balance']) : 0));
            final claims = rooms.fold<num>(0, (s, r) => s + toNum(r['pending_claims']));
            return CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
              SliverToBoxAdapter(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('total_due'), style: Theme.of(context).textTheme.titleMedium),
                      Text(rupees(due),
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold, color: due > 0 ? kBad : kGood)),
                      const SizedBox(height: 4),
                      Text(tr('rooms_summary', {'o': occupied, 'v': rooms.length - occupied})),
                    ]),
                  ),
                ),
              ),
              if (claims > 0)
                SliverToBoxAdapter(
                  child: Card(
                    color: kWarn.withValues(alpha: 0.15),
                    child: ListTile(
                      leading: const Icon(Icons.notifications_active, color: kWarn, size: 32),
                      title: Text(tr('claims_waiting', {'n': claims})),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ClaimsScreen()));
                        await reload();
                      },
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220, mainAxisExtent: 128, crossAxisSpacing: 4, mainAxisSpacing: 4),
                  delegate: SliverChildBuilderDelegate((_, i) => RoomTile(room: rooms[i], onTap: () => _open(rooms[i])),
                      childCount: rooms.length),
                ),
              ),
            ]);
          },
        ),
      );
}

class RoomTile extends StatelessWidget {
  const RoomTile({super.key, required this.room, required this.onTap});
  final Json room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final occupied = room['tenancy_id'] != null;
    final bal = toNum(room['balance']);
    final roomStatus = room['room_status'] as String? ?? 'VACANT';
    final color = !occupied
        ? Colors.grey
        : room['tenancy_status'] == 'ON_NOTICE'
            ? kWarn
            : (bal > 0 ? kBad : kGood);
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12), side: BorderSide(color: color.withValues(alpha: 0.7), width: 2)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('${room['number']}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              if (toNum(room['pending_claims']) > 0) const Icon(Icons.notifications_active, color: kWarn, size: 20),
              if (room['tenancy_status'] == 'ON_NOTICE') const Icon(Icons.logout, color: kWarn, size: 20),
            ]),
            if (occupied) ...[
              Text('${room['primary_name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
              const Spacer(),
              Text(bal > 0 ? rupees(bal) : (bal < 0 ? '+${rupees(-bal)}' : '✓ ${tr('paid')}'),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color)),
            ] else ...[
              const Spacer(),
              Text(
                switch (roomStatus) {
                  'OWNER_USE' => tr('owner_use'),
                  'MAINTENANCE' => tr('maintenance'),
                  _ => tr('vacant'),
                },
                style: const TextStyle(color: Colors.grey, fontSize: 16),
              ),
              if (roomStatus == 'VACANT') Text(tr('add_tenant'), style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            ],
          ]),
        ),
      ),
    );
  }
}
