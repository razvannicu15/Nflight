import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/airports.dart';
import '../models/pass.dart';
import '../services/notifier.dart';
import '../services/status_api.dart';
import '../services/store.dart';
import 'widgets.dart';
import '../core/i18n.dart';

/// Add a flight by hand or correct an imported one.
class EditPassPage extends StatefulWidget {
  const EditPassPage({super.key, this.existing});
  final FlightPass? existing;
  @override
  State<EditPassPage> createState() => _EditPassPageState();
}

class _EditPassPageState extends State<EditPassPage> {
  final _form = GlobalKey<FormState>();
  late final FlightPass? e = widget.existing;
  late final _from = TextEditingController(text: e?.from ?? '');
  late final _to = TextEditingController(text: e?.to ?? '');
  late final _carrier = TextEditingController(text: e?.carrier ?? '');
  late final _number = TextEditingController(text: e?.flightNumber ?? '');
  late final _pax = TextEditingController(text: e?.passenger ?? '');
  late final _pnr = TextEditingController(text: e?.pnr ?? '');
  late final _seat = TextEditingController(text: e?.seat ?? '');
  late final _gate = TextEditingController(text: e?.gate ?? '');
  late final _terminal = TextEditingController(text: e?.terminal ?? '');
  late final _note = TextEditingController(text: e?.note ?? '');
  late DateTime _date = e?.day ?? DateTime.now();
  late String? _dep = e?.departure;
  late String? _arr = e?.arrival;
  late String? _boarding = e?.boarding;

  @override
  void dispose() {
    for (final c in [_from, _to, _carrier, _number, _pax, _pnr, _seat, _gate, _terminal, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickTime(String? current, void Function(String?) set) async {
    final p = current?.split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: p == null ? const TimeOfDay(hour: 12, minute: 0) : TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])),
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t != null) setState(() => set('${two(t.hour)}:${two(t.minute)}'));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final p = e ?? FlightPass(from: '', to: '', carrier: '', flightNumber: '', date: ymd(_date));
    p
      ..from = _from.text.trim().toUpperCase()
      ..to = _to.text.trim().toUpperCase()
      ..carrier = _carrier.text.trim().toUpperCase()
      ..flightNumber = _number.text.trim().toUpperCase()
      ..date = ymd(_date)
      ..departure = _dep
      ..arrival = _arr
      ..boarding = _boarding
      ..passenger = _pax.text.trim()
      ..pnr = _pnr.text.trim().toUpperCase()
      ..seat = _seat.text.trim().toUpperCase()
      ..gate = _gate.text.trim()
      ..terminal = _terminal.text.trim()
      ..note = _note.text.trim();
    if (e == null) {
      store.upsert(p);
    } else {
      store.save();
    }
    await Notifier.schedule(p);
    if (e == null && StatusApi.enabled && !Store.isPast(p)) StatusApi.refresh(p);
    if (mounted) Navigator.pop(context);
  }

  String? _iata(String? v) {
    final s = (v ?? '').trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(s)) return tr('Cod de 3 litere', '3-letter code');
    if (Airports.get(s) == null) return tr('Aeroport necunoscut', 'Unknown airport');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    const gap = SizedBox(height: 12, width: 12);
    final upper = [UpperCaseFormatter()];
    return Scaffold(
      appBar: AppBar(
        title: Text(e == null ? tr('Zbor nou', 'New flight') : tr('Editează zborul', 'Edit flight')),
        actions: [TextButton(onPressed: _save, child: Text(tr('Salvează', 'Save')))],
      ),
      body: MaxWidth(
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            Text(tr('Zbor', 'Flight'), style: t.titleSmall?.copyWith(color: cs.primary)),
            gap,
            Row(children: [
              Expanded(child: _airportField(_from, tr('De la', 'From'), upper)),
              gap,
              Expanded(child: _airportField(_to, tr('Spre', 'To'), upper)),
            ]),
            gap,
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _carrier,
                  decoration: InputDecoration(labelText: tr('Companie', 'Airline'), hintText: 'W6'),
                  inputFormatters: [...upper, LengthLimitingTextInputFormatter(3)],
                  validator: (v) => (v ?? '').trim().length < 2 ? tr('Ex: W6, RO, FR', 'E.g. W6, RO, FR') : null,
                ),
              ),
              gap,
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _number,
                  decoration: InputDecoration(labelText: tr('Număr zbor', 'Flight number'), hintText: '3141'),
                  inputFormatters: [...upper, LengthLimitingTextInputFormatter(5)],
                  validator: (v) => (v ?? '').trim().isEmpty ? tr('Obligatoriu', 'Required') : null,
                ),
              ),
            ]),
            gap,
            _tile(Icons.event, tr('Data', 'Date'), longDate(_date), () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 400)),
              );
              if (d != null) setState(() => _date = d);
            }),
            Row(children: [
              Expanded(child: _tile(Icons.flight_takeoff, tr('Plecare', 'Departure'), _dep ?? '—', () => _pickTime(_dep, (v) => _dep = v))),
              Expanded(child: _tile(Icons.flight_land, tr('Sosire', 'Arrival'), _arr ?? '—', () => _pickTime(_arr, (v) => _arr = v))),
            ]),
            _tile(Icons.door_front_door_outlined, tr('Îmbarcare', 'Boarding'), _boarding ?? '—',
                () => _pickTime(_boarding, (v) => _boarding = v)),
            Text(tr('Orele sunt cele locale ale fiecărui aeroport, ca pe bilet.', 'Times are local to each airport, as on the pass.'),
                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 20),
            Text(tr('Bilet', 'Pass'), style: t.titleSmall?.copyWith(color: cs.primary)),
            gap,
            TextFormField(controller: _pax, decoration: InputDecoration(labelText: tr('Pasager', 'Passenger'))),
            gap,
            Row(children: [
              Expanded(child: TextFormField(controller: _pnr, inputFormatters: upper, decoration: InputDecoration(labelText: tr('Rezervare (PNR)', 'Booking (PNR)')))),
              gap,
              Expanded(child: TextFormField(controller: _seat, inputFormatters: upper, decoration: InputDecoration(labelText: tr('Loc', 'Seat')))),
            ]),
            gap,
            Row(children: [
              Expanded(child: TextFormField(controller: _terminal, decoration: const InputDecoration(labelText: 'Terminal'))),
              gap,
              Expanded(child: TextFormField(controller: _gate, decoration: InputDecoration(labelText: tr('Poarta', 'Gate')))),
            ]),
            gap,
            TextFormField(controller: _note, maxLines: 3, minLines: 1, decoration: InputDecoration(labelText: tr('Notă', 'Note'))),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: Text(tr('Salvează', 'Save')),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _airportField(TextEditingController c, String label, List<TextInputFormatter> f) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: c,
        builder: (_, v, __) {
          final a = Airports.get(v.text.trim());
          return TextFormField(
            controller: c,
            decoration: InputDecoration(labelText: label, hintText: 'OTP', helperText: a?.label ?? ' '),
            inputFormatters: [...f, LengthLimitingTextInputFormatter(3)],
            validator: _iata,
          );
        },
      );

  Widget _tile(IconData icon, String label, String value, VoidCallback onTap) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        onTap: onTap,
      );
}

class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
