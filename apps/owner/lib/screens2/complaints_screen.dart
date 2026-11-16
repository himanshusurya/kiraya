import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

import 'people_screen.dart' show SignedImage;

Color complaintColor(String? s) => switch (s) {
      'RESOLVED' => kGood,
      'IN_PROGRESS' => kWarn,
      _ => kBad,
    };

/// Tenant complaints: Open / All, with status updates and an owner note.
class ComplaintsScreen extends StatefulWidget {
  const ComplaintsScreen({super.key});

  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends State<ComplaintsScreen> {
  bool _openOnly = true;
  final _loader = GlobalKey<LoaderState<List<Json>>>();

  Future<void> _update(Json c, String status) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _NoteDialog(
        title: tr('s2_mark_as', {'s': tr('cstatus_$status')}),
        complaint: '${c['text'] ?? ''}',
        initial: '${c['owner_note'] ?? ''}',
      ),
    );
    if (text == null || !mounted) return;
    final ok = await runBusy(context, () async {
      await KirayaApi.instance.updateComplaint(c['id'] as String, {
        'status': status,
        'owner_note': text.isEmpty ? null : text,
        'resolved_at': status == 'RESOLVED' ? DateTime.now().toUtc().toIso8601String() : null,
      });
      return true;
    }, success: tr('saved'));
    if (ok == true) await _loader.currentState?.reload();
  }

  void _filter(bool openOnly) {
    if (openOnly == _openOnly) return;
    setState(() => _openOnly = openOnly);
    // The load closure reads _openOnly when called, so reloading picks up the new filter.
    _loader.currentState?.reload();
  }

  Widget _card(Json c) {
    final status = (c['status'] ?? 'OPEN') as String;
    final room = (c['room'] as Map?)?['number'];
    final photo = (c['photo_path'] ?? '').toString();
    final note = (c['owner_note'] ?? '').toString();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(room == null ? tr('s2_building') : tr('room_n', {'n': room}),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ),
            StatusChip(tr('cstatus_$status'), color: complaintColor(status)),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            StatusChip(tr('cat_${c['category'] ?? 'OTHER'}'), color: Colors.blueGrey),
            Text(fmtDate(c['created_at'])),
          ]),
          const SizedBox(height: 8),
          Text('${c['text'] ?? ''}', style: Theme.of(context).textTheme.bodyLarge),
          if (photo.isNotEmpty) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SignedImage(path: photo, height: 160, width: double.infinity, title: tr('complaint')),
            ),
          ],
          if (note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('${tr('s2_owner_note')}: $note', style: const TextStyle(fontStyle: FontStyle.italic)),
          ],
          if (status == 'RESOLVED' && c['resolved_at'] != null)
            Text(tr('s2_fixed_on', {'d': fmtDate(DateTime.tryParse('${c['resolved_at']}')?.toLocal())}),
                style: const TextStyle(color: kGood)),
          Wrap(spacing: 8, alignment: WrapAlignment.end, children: [
            if (status == 'OPEN')
              TextButton.icon(
                onPressed: () => _update(c, 'IN_PROGRESS'),
                icon: const Icon(Icons.build_outlined),
                label: Text(tr('s2_start_work')),
              ),
            if (status != 'RESOLVED')
              FilledButton.icon(
                onPressed: () => _update(c, 'RESOLVED'),
                icon: const Icon(Icons.check),
                label: Text(tr('s2_mark_fixed')),
              )
            else
              TextButton.icon(
                onPressed: () => _update(c, 'OPEN'),
                icon: const Icon(Icons.undo),
                label: Text(tr('s2_reopen')),
              ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('complaints'))),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Wrap(spacing: 8, children: [
              ChoiceChip(
                  label: Text(tr('s2_open_only')),
                  selected: _openOnly,
                  onSelected: (_) => _filter(true)),
              ChoiceChip(label: Text(tr('s2_all')), selected: !_openOnly, onSelected: (_) => _filter(false)),
            ]),
          ),
          Expanded(
            child: Loader<List<Json>>(
              key: _loader,
              load: () => KirayaApi.instance.complaints(openOnly: _openOnly),
              builder: (context, rows, _) {
                if (rows.isEmpty) {
                  return ListView(children: [
                    EmptyState(
                        text: _openOnly ? tr('s2_no_open_complaints') : null, icon: Icons.sentiment_satisfied_alt),
                  ]);
                }
                return ListView(padding: const EdgeInsets.only(bottom: 24), children: [for (final c in rows) _card(c)]);
              },
            ),
          ),
        ]),
      );
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.title, required this.complaint, required this.initial});
  final String title, complaint, initial;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _note = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.complaint, maxLines: 4, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: tr('s2_owner_note'), helperText: tr('s2_owner_note_help')),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, _note.text.trim()), child: Text(tr('save'))),
        ],
      );
}
