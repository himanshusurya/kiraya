import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

import 'settings_screen.dart' show ownerPropertyId;

/// Opens WhatsApp with the text and lets the owner pick whom to send it to (free).
Future<void> shareOnWhatsApp(BuildContext context, String text) async {
  final ok = await openUri(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'));
  if (!ok && context.mounted) showMessage(context, tr('s2_whatsapp_missing'), error: true);
}

String noticeText(Json n) => '*${n['title'] ?? ''}*\n${n['body'] ?? ''}';

/// Notices shown in the tenant app (everyone or one room).
class NoticesScreen extends StatefulWidget {
  const NoticesScreen({super.key});

  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> {
  final _loader = GlobalKey<LoaderState<List<Json>>>();

  Future<void> _add() async {
    final saved = await Navigator.push<Json>(context, MaterialPageRoute(builder: (_) => const _AddNoticePage()));
    if (saved == null || !mounted) return;
    await _loader.currentState?.reload();
    if (!mounted) return;
    if (await confirm(context, tr('s2_send_whatsapp_too'), title: tr('s2_notice_saved'), yes: tr('s2_send_whatsapp')) &&
        mounted) {
      await shareOnWhatsApp(context, noticeText(saved));
    }
  }

  Future<void> _delete(Json n) async {
    if (!await confirm(context, tr('s2_delete_notice_q', {'t': n['title']}), yes: tr('delete'))) return;
    if (!mounted) return;
    final ok = await runBusy(context, () async {
      await KirayaApi.instance.deleteNotice(n['id'] as String);
      return true;
    }, success: tr('s2_deleted'));
    if (ok == true) await _loader.currentState?.reload();
  }

  Widget _card(Json n) {
    final room = (n['room'] as Map?)?['number'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${n['title'] ?? ''}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('${n['body'] ?? ''}', style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            StatusChip(room == null ? tr('s2_everyone') : tr('room_n', {'n': room}),
                color: room == null ? Colors.indigo : Colors.teal),
            Text(fmtDate(DateTime.tryParse('${n['created_at']}')?.toLocal())),
          ]),
          Wrap(alignment: WrapAlignment.end, spacing: 4, children: [
            TextButton.icon(
              onPressed: () => shareOnWhatsApp(context, noticeText(n)),
              icon: const Icon(Icons.chat),
              label: Text(tr('s2_send_whatsapp')),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: kBad),
              onPressed: () => _delete(n),
              icon: const Icon(Icons.delete_outline),
              label: Text(tr('delete')),
            ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('notices'))),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: Text(tr('s2_new_notice')),
        ),
        body: Loader<List<Json>>(
          key: _loader,
          load: KirayaApi.instance.notices,
          builder: (context, rows, _) {
            if (rows.isEmpty) return ListView(children: [EmptyState(text: tr('s2_no_notices'), icon: Icons.campaign_outlined)]);
            return ListView(padding: const EdgeInsets.only(bottom: 96), children: [for (final n in rows) _card(n)]);
          },
        ),
      );
}

class _AddNoticePage extends StatefulWidget {
  const _AddNoticePage();

  @override
  State<_AddNoticePage> createState() => _AddNoticePageState();
}

class _AddNoticePageState extends State<_AddNoticePage> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  String? _roomId;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final values = {'title': _title.text.trim(), 'body': _body.text.trim(), 'room_id': _roomId};
    final ok = await runBusy(context, () async {
      await KirayaApi.instance.addNotice({...values, 'property_id': await ownerPropertyId()});
      return true;
    });
    if (ok == true && mounted) Navigator.pop(context, values);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('s2_new_notice'))),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: tr('s2_notice_title'), hintText: tr('s2_notice_title_hint')),
              validator: (v) => (v ?? '').trim().isEmpty ? tr('required') : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _body,
              minLines: 4,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: tr('s2_notice_body'), alignLabelWithHint: true),
              validator: (v) => (v ?? '').trim().isEmpty ? tr('required') : null,
            ),
            const SizedBox(height: 16),
            Text(tr('s2_notice_for'), style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 8),
            Loader<List<Json>>(
              load: KirayaApi.instance.rooms,
              builder: (context, rooms, _) => Wrap(spacing: 8, runSpacing: 4, children: [
                ChoiceChip(
                  label: Text(tr('s2_everyone')),
                  selected: _roomId == null,
                  onSelected: (_) => setState(() => _roomId = null),
                ),
                for (final r in rooms)
                  ChoiceChip(
                    label: Text('${r['number']}'),
                    selected: _roomId == r['id'],
                    onSelected: (_) => setState(() => _roomId = r['id'] as String),
                  ),
              ]),
            ),
          ]),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: BigButton(label: tr('s2_save_notice'), icon: Icons.check, onPressed: _save),
          ),
        ),
      );
}
