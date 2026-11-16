import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

/// Meter readings for all rooms on one day (D: one common reading day).
class ReadingsScreen extends StatefulWidget {
  const ReadingsScreen({super.key});

  @override
  State<ReadingsScreen> createState() => _ReadingsScreenState();
}

class _ReadingsScreenState extends State<ReadingsScreen> {
  final _form = GlobalKey<FormState>();
  final _loader = GlobalKey<LoaderState<List<Json>>>();
  final Map<String, TextEditingController> _values = {};
  DateTime _date = todayIst();

  TextEditingController _ctl(String roomId) => _values.putIfAbsent(roomId, TextEditingController.new);

  Future<void> _save(List<Json> rooms) async {
    if (!_form.currentState!.validate()) return;
    final items = [
      for (final r in rooms)
        if (_ctl(r['room_id'] as String).text.trim().isNotEmpty)
          {'room_id': r['room_id'], 'value': toNum(_ctl(r['room_id'] as String).text.trim())},
    ];
    if (items.isEmpty) {
      showMessage(context, tr('enter_one_reading'), error: true);
      return;
    }
    final lower = [
      for (final r in rooms)
        if (r['last_reading'] != null &&
            _ctl(r['room_id'] as String).text.trim().isNotEmpty &&
            toNum(_ctl(r['room_id'] as String).text.trim()) < toNum(r['last_reading']))
          '${r['number']}',
    ];
    var force = false;
    if (lower.isNotEmpty) {
      force = await confirm(context, tr('reading_lower', {'msg': tr('reading_lower_rooms', {'rooms': lower.join(', ')})}));
      if (!force || !mounted) return;
    }
    final n = await runBusy(context, () => KirayaApi.instance.addReadings(_date, items, force: force));
    if (n == null || !mounted) return;
    showMessage(context, tr('readings_saved', {'n': n}));
    for (final c in _values.values) {
      c.clear();
    }
    await _loader.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('tab_readings'))),
        body: Loader<List<Json>>(
          key: _loader,
          load: () async => (await KirayaApi.instance.roomBoard()).where((r) => r['has_meter'] != false).toList(),
          builder: (context, rooms, _) {
            if (rooms.isEmpty) return ListView(children: [EmptyState(text: tr('no_rooms'))]);
            return Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                DateField(label: tr('readings_date'), value: _date, last: todayIst(), onChanged: (d) => setState(() => _date = d)),
                const SizedBox(height: 8),
                Text(tr('readings_help'), style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                for (final r in rooms) _RoomReading(room: r, controller: _ctl(r['room_id'] as String)),
                const SizedBox(height: 20),
                BigButton(label: tr('save_readings'), icon: Icons.check, onPressed: () => _save(rooms)),
                const SizedBox(height: 24),
              ]),
            );
          },
        ),
      );
}

class _RoomReading extends StatefulWidget {
  const _RoomReading({required this.room, required this.controller});
  final Json room;
  final TextEditingController controller;

  @override
  State<_RoomReading> createState() => _RoomReadingState();
}

class _RoomReadingState extends State<_RoomReading> {
  @override
  Widget build(BuildContext context) {
    final r = widget.room;
    final last = r['last_reading'] == null ? null : toNum(r['last_reading']);
    final now = num.tryParse(widget.controller.text.trim());
    final used = (last != null && now != null) ? now - last : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 92,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('room_n', {'n': r['number']}),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              if (r['primary_name'] != null)
                Text('${r['primary_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            ]),
          ),
          Expanded(
            child: NumberField(
              controller: widget.controller,
              label: tr('reading_now'),
              decimal: true,
              required: false,
              helper: last == null
                  ? tr('no_previous_reading')
                  : '${tr('previous_reading')}: $last (${fmtDateShort(r['last_reading_date'])})',
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (used != null)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 14),
              child: Text(tr('units_used', {'u': used}),
                  style: TextStyle(fontWeight: FontWeight.bold, color: used < 0 ? kBad : kGood)),
            ),
        ]),
      ),
    );
  }
}
