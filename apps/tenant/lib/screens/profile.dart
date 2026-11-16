import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

import '../shell.dart';
import '../util.dart';

const _profileFields = [
  'full_name',
  'phone',
  'alt_phone',
  'email',
  'father_name',
  'dob',
  'age',
  'gender',
  'occupation',
  'workplace',
  'permanent_address',
  'id_type',
  'id_number',
  'vehicle_number',
  'emergency_name',
  'emergency_phone',
];

/// Own tenant record (read-only) plus room details.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.data, required this.tenancy});
  final TenantData data;
  final Json tenancy;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('my_profile'))),
        body: Loader<Json?>(
          load: () async => data.tenantId == null ? null : KirayaApi.instance.tenant(data.tenantId!),
          builder: (context, tenant, _) => ProfileView(tenant: tenant ?? const {}, tenancy: tenancy, me: data.me),
        ),
      );
}

class ProfileView extends StatelessWidget {
  const ProfileView({super.key, required this.tenant, required this.tenancy, required this.me});
  final Json tenant, tenancy, me;

  static String _value(String field, Object? v) {
    final s = v.toString();
    if (field == 'dob') return fmtDate(v);
    if (field == 'id_number' && s.length > 4) return '${'•' * (s.length - 4)}${s.substring(s.length - 4)}';
    return s;
  }

  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                for (final f in _profileFields)
                  if (tenant[f] != null && tenant[f].toString().trim().isNotEmpty) _Field(tr('f_$f'), _value(f, tenant[f])),
                if (me['phone'] != null) _Field(tr('login_phone'), me['phone'].toString()),
              ]),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                InfoRow(tr('room'), tenancy['room_number']?.toString() ?? '-', bold: true),
                InfoRow(tr('status'), tenancyStatusText(tenancy)),
                InfoRow(tr('staying_since'), fmtDate(tenancy['start_date'])),
                if (tenancy['monthly_rent'] != null) InfoRow(tr('monthly_rent'), rupees(tenancy['monthly_rent'])),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(tr('profile_note'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ],
      );
}


/// Label above value, so long values (addresses) wrap instead of overflowing.
class _Field extends StatelessWidget {
  const _Field(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: SizedBox(
          width: double.infinity,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}