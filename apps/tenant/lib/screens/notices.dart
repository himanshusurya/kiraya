import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

/// Notices from the owner: for everyone, or just for this room.
class NoticesScreen extends StatelessWidget {
  const NoticesScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('notices_owner'))),
        body: Loader<List<Json>>(
          load: () => KirayaApi.instance.notices(),
          builder: (context, rows, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: rows.isEmpty
                ? [EmptyState(text: tr('no_notices'), icon: Icons.campaign_outlined)]
                : [for (final n in rows) NoticeCard(notice: n)],
          ),
        ),
      );
}

class NoticeCard extends StatelessWidget {
  const NoticeCard({super.key, required this.notice});
  final Json notice;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(notice['title']?.toString() ?? '',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(notice['body']?.toString() ?? '', style: const TextStyle(fontSize: 17)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Text(fmtDate(notice['created_at']),
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              if (notice['room_id'] != null) StatusChip(tr('for_your_room'), color: kWarn),
            ]),
          ]),
        ),
      );
}
