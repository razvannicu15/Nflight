import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/airlines.dart';
import '../core/airports.dart';
import '../models/pass.dart';
import '../services/notifier.dart';
import '../services/status_api.dart';
import '../services/store.dart';
import 'board_page.dart';
import 'boarding_code_page.dart';
import 'compensation_sheet.dart';
import 'edit_pass_page.dart';
import 'widgets.dart';
import '../core/i18n.dart';

class PassDetailPage extends StatefulWidget {
  const PassDetailPage({super.key, required this.passId});
  final String passId;
  @override
  State<PassDetailPage> createState() => _PassDetailPageState();
}

class _PassDetailPageState extends State<PassDetailPage> {
  bool _busy = false;

  Future<void> _refresh(FlightPass p) async {
    setState(() => _busy = true);
    final err = await StatusApi.refresh(p);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(err ?? tr('Status actualizat', 'Status updated'))));
  }

  Future<void> _menu(FlightPass p, String v) async {
    switch (v) {
      case 'edit':
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => EditPassPage(existing: p)));
      case 'archive':
        p.archived = !p.archived;
        store.upsert(p);
        if (p.archived) {
          await Notifier.cancel(p);
        } else {
          await Notifier.schedule(p);
        }
      case 'share':
        await Clipboard.setData(ClipboardData(text: shareText(p)));
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(tr('Detaliile zborului au fost copiate', 'Flight details copied'))));
        }
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(tr('Ștergi biletul?', 'Delete this pass?')),
            content: Text('${p.flightCode} · ${p.route} · ${p.passenger}'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Anulează', 'Cancel'))),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Șterge', 'Delete'))),
            ],
          ),
        );
        if (ok == true) {
          await Notifier.cancel(p);
          store.remove(p);
          if (mounted) Navigator.pop(context);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final p = store.byId(widget.passId);
        if (p == null) return const Scaffold(body: SizedBox.shrink());
        return _page(context, p);
      },
    );
  }

  Widget _page(BuildContext context, FlightPass p) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final companions = store.companions(p);
    final dep = Store.departureOf(p).add(Duration(minutes: p.delayMinutes));
    final upcoming = !Store.isPast(p);
    final dist = Airports.distanceKm(p.from, p.to);

    return Scaffold(
      appBar: AppBar(
        title: Text(p.flightCode),
        actions: [
          if (StatusApi.enabled)
            IconButton(
              tooltip: tr('Actualizează status', 'Refresh status'),
              onPressed: _busy ? null : () => _refresh(p),
              icon: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
            ),
          PopupMenuButton<String>(
            onSelected: (v) => _menu(p, v),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit', child: ListTile(leading: const Icon(Icons.edit_outlined), title: Text(tr('Editează', 'Edit')))),
              PopupMenuItem(value: 'share', child: ListTile(leading: const Icon(Icons.copy_outlined), title: Text(tr('Copiază detaliile', 'Copy details')))),
              PopupMenuItem(
                  value: 'archive',
                  child: ListTile(
                      leading: Icon(p.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
                      title: Text(p.archived ? tr('Scoate din arhivă', 'Unarchive') : tr('Arhivează', 'Archive')))),
              PopupMenuItem(value: 'delete', child: ListTile(leading: const Icon(Icons.delete_outline), title: Text(tr('Șterge', 'Delete')))),
            ],
          ),
        ],
      ),
      body: MaxWidth(
        child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          Card(
            elevation: 0,
            color: cs.surfaceContainerLow,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    AirlineBadge(p.carrier, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(Airlines.name(p.carrier), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        Text(longDate(p.day), style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                      ]),
                    ),
                    StatusChip(p),
                  ]),
                  const SizedBox(height: 20),
                  RouteHeader(p, large: true),
                  if (upcoming && p.departure != null) ...[
                    const SizedBox(height: 12),
                    Text(tr('Pleacă ${countdown(dep)}', 'Departs ${countdown(dep)}'),
                        style: t.titleSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
                  ],
                  if (p.departure == null) ...[
                    const SizedBox(height: 12),
                    ActionChip(
                      avatar: const Icon(Icons.schedule, size: 18),
                      label: Text(tr('Adaugă ora plecării', 'Add departure time')),
                      onPressed: () => StatusApi.enabled
                          ? _refresh(p)
                          : Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => EditPassPage(existing: p))),
                    ),
                  ],
                ]),
              ),
              const TicketDivider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                child: Column(children: [
                  CellRow([
                    ('Terminal', p.terminal),
                    (tr('Poarta', 'Gate'), p.gate),
                    (tr('Îmbarcare', 'Boarding'), p.boarding ?? ''),
                    (tr('Loc', 'Seat'), p.seat),
                  ]),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: p.barcode.isEmpty ? null : () => openBoardingCode(context, p),
                      icon: const Icon(Icons.qr_code_2),
                      label: Text(companions.isEmpty
                          ? tr('Arată biletul', 'Show pass')
                          : tr('Arată biletele (${companions.length + 1})', 'Show passes (${companions.length + 1})')),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
          SectionTitle(tr('Bilet', 'Pass')),
          InfoTable([
            (tr('Pasager', 'Passenger'), p.passenger, null),
            (tr('Rezervare', 'Booking'), p.pnr, null),
            (tr('Clasă', 'Cabin'), p.cabin, null),
            (tr('Secvență', 'Sequence'), p.sequence, null),
            (tr('Fidelitate', 'Frequent flyer'), p.frequentFlyer, null),
            (tr('Avion', 'Aircraft'), p.aircraft, null),
            (tr('Notă', 'Note'), p.note, null),
          ]),
          if (companions.isNotEmpty) ...[
            SectionTitle(tr('Aceeași rezervare', 'Same booking')),
            for (final c in companions)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(c.passenger),
                trailing: Text(c.seat, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => PassDetailPage(passId: c.id))),
              ),
          ],
          SectionTitle(tr('Zbor', 'Flight')),
          InfoTable([
            _airportRow(tr('Plecare', 'From'), p.from),
            _airportRow(tr('Sosire', 'To'), p.to),
            if (dist > 0)
              (tr('Distanță', 'Distance'), '${km(dist)} km · ${durationText(flightDuration(p))}', null),
          ]),
          if (StatusApi.enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => BoardPage(iata: p.from, highlight: p))),
                    icon: const Icon(Icons.flight_takeoff, size: 18),
                    label: Text('${tr('Plecări', 'Departures')} ${p.from}'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => BoardPage(iata: p.to, arrivals: true, highlight: p))),
                    icon: const Icon(Icons.flight_land, size: 18),
                    label: Text('${tr('Sosiri', 'Arrivals')} ${p.to}'),
                  ),
                ),
              ]),
            ),
          if (p.status == FlightStatus.cancelled || p.delayMinutes >= 120 || p.arrivalDelayMinutes >= 120 || !upcoming)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: OutlinedButton.icon(
                onPressed: () => showCompensationSheet(context, p),
                icon: const Icon(Icons.euro),
                label: Text(tr('Compensație UE 261', 'EU 261 compensation')),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ),
        ]),
      ),
    );
  }

  (String, String, String?) _airportRow(String role, String iata) {
    final a = Airports.get(iata);
    if (a == null) return (role, iata, null);
    final now = Airports.nowAt(iata);
    final offset = a.tz.isEmpty ? '' : _offsetText(now.timeZoneOffset - DateTime.now().timeZoneOffset);
    return (
      role,
      '${a.label} · $iata',
      a.tz.isEmpty ? null : '${tr('ora locală', 'local time')} ${hm(now)}$offset',
    );
  }

  String _offsetText(Duration d) {
    if (d.inMinutes == 0) return '';
    final sign = d.isNegative ? '−' : '+';
    final m = d.inMinutes.abs();
    return ' ($sign${m ~/ 60}${m % 60 == 0 ? '' : ':${two(m % 60)}'} h)';
  }
}

String shareText(FlightPass p) {
  final lines = [
    '${p.flightCode} ${Airlines.name(p.carrier)}',
    '${Airports.city(p.from)} (${p.from}) → ${Airports.city(p.to)} (${p.to})',
    [longDate(p.day), if (p.departure != null) '${tr('plecare', 'departs')} ${Notifier.hmOf(p)}', if (p.arrival != null) '${tr('sosire', 'arrives')} ${p.arrival}']
        .join(', '),
    if (p.status != FlightStatus.unknown) 'Status: ${statusLabel(p.status)}',
    if (p.gate.isNotEmpty) '${tr('Poarta', 'Gate')} ${p.gate}',
  ];
  return lines.join('\n');
}
