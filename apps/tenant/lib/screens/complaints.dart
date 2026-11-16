import 'dart:typed_data';

import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

import '../photo.dart';
import '../util.dart';

const complaintCategories = ['WATER', 'LIGHT', 'CLEANING', 'REPAIR', 'OTHER'];

class ComplaintsScreen extends StatefulWidget {
  const ComplaintsScreen({super.key, required this.tenancy, required this.userId});
  final Json tenancy;
  final String userId;

  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends State<ComplaintsScreen> {
  final _loader = GlobalKey<LoaderState<List<Json>>>();

  Future<void> _new() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => NewComplaintScreen(tenancy: widget.tenancy, userId: widget.userId)),
    );
    if (ok == true && mounted) {
      showMessage(context, tr('complaint_sent'));
      await _loader.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('complaints'))),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _new,
          icon: const Icon(Icons.add),
          label: Text(tr('raise_complaint'), style: const TextStyle(fontSize: 17)),
        ),
        body: Loader<List<Json>>(
          key: _loader,
          load: () => KirayaApi.instance.complaints(),
          builder: (context, rows, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 8, bottom: 96),
            children: rows.isEmpty
                ? [EmptyState(text: tr('no_complaints'), icon: Icons.handyman_outlined)]
                : [for (final c in rows) ComplaintCard(complaint: c)],
          ),
        ),
      );
}

class ComplaintCard extends StatelessWidget {
  const ComplaintCard({super.key, required this.complaint});
  final Json complaint;

  @override
  Widget build(BuildContext context) {
    final status = complaint['status']?.toString() ?? 'OPEN';
    final color = switch (status) { 'RESOLVED' => kGood, 'IN_PROGRESS' => kWarn, _ => kBad };
    final ownerNote = complaint['owner_note']?.toString() ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(tr('cat_${complaint['category']}'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ),
            StatusChip(tr('cstatus_$status'), color: color),
          ]),
          const SizedBox(height: 6),
          Text(complaint['text']?.toString() ?? '', style: const TextStyle(fontSize: 17)),
          const SizedBox(height: 6),
          Text(fmtDate(complaint['created_at']), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          if (ownerNote.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(tr('owner_says', {'t': ownerNote}), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
        ]),
      ),
    );
  }
}

class NewComplaintScreen extends StatelessWidget {
  const NewComplaintScreen({super.key, required this.tenancy, required this.userId});
  final Json tenancy;
  final String userId;

  Future<void> _send(BuildContext context, String category, String text, Uint8List? photo) async {
    final api = KirayaApi.instance;
    final tenancyId = tenancy['tenancy_id'].toString();
    final done = await runBusy(context, () async {
      String? path;
      // Storage policy only lets tenants write under proof/<tenancy_id>/.
      if (photo != null) path = await api.upload('proof/$tenancyId/complaint-${randomId()}.jpg', photo);
      await api.addComplaint({
        'property_id': tenancy['property_id'],
        'tenancy_id': tenancyId,
        'room_id': tenancy['room_id'],
        'category': category,
        'text': text,
        'photo_path': ?path,
        'raised_by': userId,
      });
      return true;
    });
    if (done == true && context.mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('raise_complaint'))),
        body: ComplaintForm(
          pickImage: () => pickPhoto(context, askSource: true),
          onSubmit: (cat, text, photo) => _send(context, cat, text, photo),
        ),
      );
}

/// Presentational complaint form: category chips, text and an optional photo.
class ComplaintForm extends StatefulWidget {
  const ComplaintForm({super.key, required this.onSubmit, this.pickImage});
  final Future<void> Function(String category, String text, Uint8List? photo) onSubmit;
  final Future<Uint8List?> Function()? pickImage;

  @override
  State<ComplaintForm> createState() => _ComplaintFormState();
}

class _ComplaintFormState extends State<ComplaintForm> {
  final _form = GlobalKey<FormState>();
  final _text = TextEditingController();
  String _category = complaintCategories.first;
  Uint8List? _photo;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await widget.onSubmit(_category, _text.text.trim(), _photo);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(tr('what_problem'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in complaintCategories)
                ChoiceChip(
                  label: Text(tr('cat_$c'), style: const TextStyle(fontSize: 17)),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                ),
            ]),
            const SizedBox(height: 16),
            TextFormField(
              controller: _text,
              maxLines: 4,
              decoration: InputDecoration(labelText: tr('complaint_text')),
              validator: (v) => (v ?? '').trim().isEmpty ? tr('required') : null,
            ),
            const SizedBox(height: 16),
            PhotoPickButton(
              label: tr('add_photo'),
              addedLabel: tr('photo_added'),
              hasPhoto: _photo != null,
              onPick: widget.pickImage == null
                  ? null
                  : () async {
                      final b = await widget.pickImage!();
                      if (b != null && mounted) setState(() => _photo = b);
                    },
              onRemove: () => setState(() => _photo = null),
            ),
            const SizedBox(height: 24),
            BigButton(label: tr('send'), icon: Icons.send, onPressed: _busy ? null : _submit),
          ],
        ),
      );
}
