import 'package:image_picker/image_picker.dart';
import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

import 'person_form.dart';

const kKycKinds = ['AADHAAR', 'PAN', 'DL', 'PHOTO', 'OTHER'];

/// Everyone staying in one tenancy (main tenant first).
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key, required this.tenancyId});
  final String tenancyId;

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  final _loader = GlobalKey<LoaderState<List<Json>>>();
  final _api = KirayaApi.instance;

  Future<void> _reload() async => _loader.currentState?.reload();

  Future<void> _add() async {
    final added = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => _AddPersonPage(tenancyId: widget.tenancyId)));
    if (added == true) await _reload();
  }

  Future<void> _open(String tenantId) async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => PersonDetailScreen(tenantId: tenantId)));
    await _reload();
  }

  Future<void> _setAccess(String tenantId, bool v) async {
    final ok = await runBusy(context, () async {
      await _api.setAppAccess(widget.tenancyId, tenantId, v);
      return true;
    }, success: v ? tr('s2_app_on') : tr('s2_app_off'));
    if (ok == true) await _reload();
  }

  Future<void> _remove(Json person) async {
    if (!await confirm(context, tr('s2_remove_person_q', {'name': person['full_name']}), yes: tr('remove'))) return;
    if (!mounted) return;
    final ok = await runBusy(context, () async {
      await _api.removeOccupant(widget.tenancyId, person['id'] as String);
      return true;
    }, success: tr('s2_removed'));
    if (ok == true) await _reload();
  }

  Widget _card(Json o) {
    final p = Json.from((o['tenant'] as Map?) ?? const {});
    final primary = o['is_primary'] == true;
    final phone = (p['phone'] ?? '').toString();
    return Card(
      child: InkWell(
        onTap: () => _open(o['tenant_id'] as String),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const CircleAvatar(radius: 24, child: Icon(Icons.person)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${p['full_name'] ?? '-'}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  if (phone.isNotEmpty) Text(phone),
                ]),
              ),
              if (primary) StatusChip(tr('s2_main_tenant'), color: kGood),
              const Icon(Icons.chevron_right),
            ]),
            if (phone.isNotEmpty)
              Wrap(spacing: 4, children: [
                TextButton.icon(
                    onPressed: () => openUri(callUri(phone)), icon: const Icon(Icons.call), label: Text(tr('s2_call'))),
                TextButton.icon(
                    onPressed: () => openUri(whatsappUri(phone, '')),
                    icon: const Icon(Icons.chat),
                    label: Text(tr('s2_whatsapp'))),
              ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('s2_app_access')),
              subtitle: Text(tr('s2_app_access_help')),
              value: o['app_access'] == true,
              onChanged: (v) => _setAccess(o['tenant_id'] as String, v),
            ),
            if (!primary)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: kBad),
                onPressed: () => _remove({...p, 'id': o['tenant_id']}),
                icon: const Icon(Icons.person_remove),
                label: Text(tr('s2_remove_person')),
              ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('s2_people'))),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          icon: const Icon(Icons.person_add),
          label: Text(tr('s2_add_person')),
        ),
        body: Loader<List<Json>>(
          key: _loader,
          load: () => _api.occupants(widget.tenancyId),
          builder: (context, rows, _) {
            final staying = rows.where((o) => o['left_on'] == null).toList();
            final left = rows.where((o) => o['left_on'] != null).toList();
            if (rows.isEmpty) return ListView(children: const [EmptyState(icon: Icons.people_outline)]);
            return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
              for (final o in staying) _card(o),
              if (left.isNotEmpty) SectionTitle(tr('s2_left_earlier')),
              for (final o in left)
                ListTile(
                  leading: const Icon(Icons.person_outline, color: Colors.grey),
                  title: Text('${(o['tenant'] as Map?)?['full_name'] ?? '-'}'),
                  subtitle: Text(tr('s2_left_on', {'d': fmtDate(o['left_on'])})),
                  onTap: () => _open(o['tenant_id'] as String),
                ),
            ]);
          },
        ),
      );
}

class _AddPersonPage extends StatefulWidget {
  const _AddPersonPage({required this.tenancyId});
  final String tenancyId;

  @override
  State<_AddPersonPage> createState() => _AddPersonPageState();
}

class _AddPersonPageState extends State<_AddPersonPage> {
  final _form = GlobalKey<FormState>();
  Json _person = {};
  bool _app = false;
  DateTime _joined = todayIst();

  Future<void> _save() async {
    if (!_form.currentState!.validate() || !isPersonValid(_person)) return;
    final id = await runBusy(
      context,
      () => KirayaApi.instance.addOccupant(widget.tenancyId, {..._person, 'app_access': _app}, _joined),
      success: tr('s2_person_added'),
    );
    if (id != null && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('s2_add_person'))),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            PersonForm(onChanged: (v) => _person = v),
            DateField(label: tr('s2_joined_on'), value: _joined, onChanged: (d) => setState(() => _joined = d)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('s2_give_app_login')),
              subtitle: Text(tr('s2_give_app_login_help')),
              value: _app,
              onChanged: (v) => setState(() => _app = v),
            ),
          ]),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: BigButton(label: tr('save'), icon: Icons.check, onPressed: _save),
          ),
        ),
      );
}

/// One person: all renter-form details, edit, and ID photos (KYC).
class PersonDetailScreen extends StatefulWidget {
  const PersonDetailScreen({super.key, required this.tenantId});
  final String tenantId;

  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

typedef _PersonData = ({Json person, List<Json> docs});

class _PersonDetailScreenState extends State<PersonDetailScreen> {
  final _loader = GlobalKey<LoaderState<_PersonData>>();
  final _api = KirayaApi.instance;

  Future<_PersonData> _load() async {
    final r = await Future.wait([_api.tenant(widget.tenantId), _api.kycDocs(widget.tenantId)]);
    return (person: r[0] as Json, docs: r[1] as List<Json>);
  }

  Future<void> _reload() async => _loader.currentState?.reload();

  Future<void> _edit(Json person) async {
    final saved = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => _EditPersonPage(tenantId: widget.tenantId, initial: person)));
    if (saved == true) await _reload();
  }

  Future<void> _addPhoto() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text(tr('s2_which_photo'), style: Theme.of(c).textTheme.titleMedium)),
          for (final k in kKycKinds)
            ListTile(
              leading: Icon(k == 'PHOTO' ? Icons.face : Icons.badge_outlined),
              title: Text(tr('s2_kyc_$k')),
              onTap: () => Navigator.pop(c, k),
            ),
        ]),
      ),
    );
    if (kind == null || !mounted) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera, size: 32),
            title: Text(tr('s2_take_photo')),
            onTap: () => Navigator.pop(c, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, size: 32),
            title: Text(tr('s2_from_gallery')),
            onTap: () => Navigator.pop(c, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null || !mounted) return;
    XFile? file;
    try {
      file = await ImagePicker().pickImage(source: source, imageQuality: 70, maxWidth: 1600);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
      return;
    }
    if (file == null || !mounted) return;
    final picked = file;
    final ok = await runBusy(context, () async {
      final bytes = await picked.readAsBytes();
      final path = 'kyc/${widget.tenantId}/$kind-${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _api.upload(path, bytes);
      await _api.addKycDoc(widget.tenantId, kind, path);
      if (kind == 'PHOTO') await _api.updateTenant(widget.tenantId, {'photo_path': path});
      return true;
    }, success: tr('s2_photo_saved'));
    if (ok == true) await _reload();
  }

  Widget _field(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('s2_person_details'))),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addPhoto,
          icon: const Icon(Icons.add_a_photo),
          label: Text(tr('s2_add_id_photo')),
        ),
        body: Loader<_PersonData>(
          key: _loader,
          load: _load,
          builder: (context, data, _) {
            final p = data.person;
            final phone = (p['phone'] ?? '').toString();
            final photo = (p['photo_path'] ?? '').toString();
            final shown = kPersonFields.where((k) => k != 'full_name' && (p[k]?.toString() ?? '').isNotEmpty);
            return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
              const SizedBox(height: 16),
              Center(
                child: photo.isEmpty
                    ? const CircleAvatar(radius: 44, child: Icon(Icons.person, size: 48))
                    : ClipOval(child: SignedImage(path: photo, width: 96, height: 96)),
              ),
              const SizedBox(height: 8),
              Text('${p['full_name'] ?? '-'}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              if (phone.isNotEmpty)
                Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
                  TextButton.icon(
                      onPressed: () => openUri(callUri(phone)), icon: const Icon(Icons.call), label: Text(phone)),
                  TextButton.icon(
                      onPressed: () => openUri(whatsappUri(phone, '')),
                      icon: const Icon(Icons.chat),
                      label: Text(tr('s2_whatsapp'))),
                ]),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: BigButton(label: tr('s2_edit_details'), icon: Icons.edit, outlined: true, onPressed: () => _edit(p)),
              ),
              SectionTitle(tr('s2_details')),
              if (shown.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(tr('s2_no_details'))),
              for (final k in shown) _field(personFieldLabel(k), personFieldValue(k, p[k])),
              SectionTitle(tr('s2_id_photos')),
              if (data.docs.isEmpty)
                Padding(padding: const EdgeInsets.all(16), child: Text(tr('s2_no_id_photos')))
              else
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.8,
                  children: [
                    for (final d in data.docs)
                      Column(children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SignedImage(
                              path: d['storage_path'] as String,
                              title: tr('s2_kyc_${d['kind']}'),
                              width: double.infinity,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(tr('s2_kyc_${d['kind']}'), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ]),
                  ],
                ),
            ]);
          },
        ),
      );
}

class _EditPersonPage extends StatefulWidget {
  const _EditPersonPage({required this.tenantId, required this.initial});
  final String tenantId;
  final Json initial;

  @override
  State<_EditPersonPage> createState() => _EditPersonPageState();
}

class _EditPersonPageState extends State<_EditPersonPage> {
  final _form = GlobalKey<FormState>();
  late Json _person = Json.from(widget.initial);

  Future<void> _save() async {
    if (!_form.currentState!.validate() || !isPersonValid(_person)) return;
    // Send every form column so that cleared fields are cleared in the database too.
    final values = {for (final k in kPersonFields) k: _person[k]};
    final ok = await runBusy(context, () async {
      await KirayaApi.instance.updateTenant(widget.tenantId, values);
      return true;
    }, success: tr('saved'));
    if (ok == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('s2_edit_details'))),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            PersonForm(initial: widget.initial, onChanged: (v) => _person = v),
          ]),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: BigButton(label: tr('save'), icon: Icons.check, onPressed: _save),
          ),
        ),
      );
}

/// Image from the private bucket (signed URL); tap opens it full screen.
class SignedImage extends StatefulWidget {
  const SignedImage({super.key, required this.path, this.width, this.height, this.title});
  final String path;
  final double? width, height;
  final String? title;

  @override
  State<SignedImage> createState() => _SignedImageState();
}

class _SignedImageState extends State<SignedImage> {
  late Future<String> _url = KirayaApi.instance.signedUrl(widget.path);

  @override
  void didUpdateWidget(SignedImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _url = KirayaApi.instance.signedUrl(widget.path);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.width,
        height: widget.height,
        child: FutureBuilder<String>(
          future: _url,
          builder: (context, snap) {
            if (snap.hasError) return const ColoredBox(color: Colors.black12, child: Icon(Icons.broken_image));
            if (!snap.hasData) return const ColoredBox(color: Colors.black12, child: Center(child: CircularProgressIndicator()));
            final url = snap.data!;
            return InkWell(
              onTap: () => Navigator.push(
                  context, MaterialPageRoute<void>(builder: (_) => ImageViewScreen(url: url, title: widget.title))),
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black12, child: Icon(Icons.broken_image)),
              ),
            );
          },
        ),
      );
}

/// Full-screen, pinch-to-zoom image.
class ImageViewScreen extends StatelessWidget {
  const ImageViewScreen({super.key, required this.url, this.title});
  final String url;
  final String? title;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: Text(title ?? ''), backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: Center(
          child: InteractiveViewer(
            maxScale: 6,
            child: Image.network(
              url,
              loadingBuilder: (_, child, p) =>
                  p == null ? child : const Center(child: CircularProgressIndicator(color: Colors.white)),
              errorBuilder: (_, _, _) => const Icon(Icons.broken_image, color: Colors.white, size: 64),
            ),
          ),
        ),
      );
}
