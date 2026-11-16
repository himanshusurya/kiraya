import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

/// Move a tenant to another (empty) room. Dues and advance move with them.
/// Pops with the new tenancy id.
class ShiftScreen extends StatefulWidget {
  const ShiftScreen({super.key, required this.summary});
  final Json summary;

  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> {
  final _form = GlobalKey<FormState>();
  DateTime _date = todayIst();
  Json? _room;
  final _oldReading = TextEditingController();
  final _newReading = TextEditingController();
  final _rent = TextEditingController();

  Future<void> _save(List<Json> rooms) async {
    if (!_form.currentState!.validate() || _room == null) return;
    final id = await runBusy(
      context,
      () => KirayaApi.instance.shiftRoom(
        widget.summary['tenancy_id'] as String,
        _room!['room_id'] as String,
        _date,
        oldReading: _oldReading.text.trim().isEmpty ? null : toNum(_oldReading.text.trim()),
        newReading: _newReading.text.trim().isEmpty ? null : toNum(_newReading.text.trim()),
        newRent: _rent.text.trim().isEmpty ? null : toNum(_rent.text.trim()),
      ),
      success: tr('shifted'),
    );
    if (id != null && mounted) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('${tr('shift_room')} · ${tr('room_n', {'n': widget.summary['room_number']})}')),
        body: Loader<List<Json>>(
          load: KirayaApi.instance.roomBoard,
          builder: (context, rooms, _) {
            final old = rooms.where((r) => r['room_id'] == widget.summary['room_id']).firstOrNull;
            final empty = rooms.where((r) => r['tenancy_id'] == null && r['room_status'] == 'VACANT').toList();
            if (empty.isEmpty) return ListView(children: [EmptyState(text: tr('vacant'))]);
            return Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Text(tr('new_room'), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  for (final r in empty)
                    ChoiceChip(
                      label: Text('${r['number']}', style: const TextStyle(fontSize: 18)),
                      selected: _room?['room_id'] == r['room_id'],
                      onSelected: (_) => setState(() {
                        _room = r;
                        _newReading.text = r['last_reading'] == null ? '' : '${toNum(r['last_reading'])}';
                        _rent.text = r['default_rent'] == null ? '' : '${toNum(r['default_rent'])}';
                      }),
                    ),
                ]),
                const SizedBox(height: 16),
                DateField(label: tr('shift_date'), value: _date, onChanged: (d) => setState(() => _date = d)),
                const SizedBox(height: 12),
                NumberField(
                  controller: _oldReading,
                  label: tr('old_room_reading'),
                  decimal: true,
                  required: false,
                  helper: old?['last_reading'] == null ? null : '${tr('previous_reading')}: ${toNum(old!['last_reading'])}',
                ),
                const SizedBox(height: 12),
                NumberField(controller: _newReading, label: tr('new_room_reading'), decimal: true, required: false),
                const SizedBox(height: 12),
                NumberField(
                  controller: _rent,
                  label: tr('new_rent_optional'),
                  prefix: '₹ ',
                  required: false,
                  helper: '${tr('monthly_rent')}: ${rupees(widget.summary['monthly_rent'])}',
                ),
                const SizedBox(height: 20),
                BigButton(
                  label: tr('shift_room'),
                  icon: Icons.swap_horiz,
                  onPressed: _room == null ? null : () => _save(rooms),
                ),
              ]),
            );
          },
        ),
      );
}
