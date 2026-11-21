import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/airlines.dart';
import '../core/airports.dart';
import '../models/pass.dart';
import '../services/notifier.dart';
import '../services/status_api.dart';
import '../services/store.dart';
import 'boarding_code_page.dart';
import 'compensation_sheet.dart';
import 'edit_pass_page.dart';
import 'widgets.dart';

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
        .showSnackBar(SnackBar(content: Text(err ?? 'Status actualizat')));
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
              .showSnackBar(const SnackBar(content: Text('Detaliile zborului au fost copiate')));
        }
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Ștergi biletul?'),
            content: Text('${p.flightCode} · ${p.route} · ${p.passenger}'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Anulează')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Șterge')),
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
              tooltip: 'Actualizează status',
              onPressed: _busy ? null : () => _refresh(p),
              icon: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
            ),
          PopupMenuButton<String>(
            onSelected: (v) => _menu(p, v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Editează'))),
              const PopupMenuItem(value: 'share', child: ListTile(leading: Icon(Icons.copy_outlined), title: Text('Copiază detaliile'))),
              PopupMenuItem(
                  value: 'archive',
                  child: ListTile(
                      leading: Icon(p.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
                      title: Text(p.archived ? 'Scoate din arhivă' : 'Arhivează'))),
              const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Șterge'))),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
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
                  const SizedBox(height: 14),
                  Text('Pleacă ${countdown(dep)}',
                      style: t.titleSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
                ],
                if (p.departure == null) ...[
                  const SizedBox(height: 14),
                  ActionChip(
                    avatar: const Icon(Icons.schedule, size: 18),
                    label: Text(StatusApi.enabled ? 'Ora plecării: actualizează status' : 'Adaugă ora plecării'),
                    onPressed: () => StatusApi.enabled
                        ? _refresh(p)
                        : Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => EditPassPage(existing: p))),
                  ),
                ],
                const SizedBox(height: 20),
                _grid([
                  InfoCell('Terminal', p.terminal, big: true),
                  InfoCell('Poarta', p.gate, big: true),
                  InfoCell('Îmbarcare', p.boarding ?? '', big: true),
                  InfoCell('Loc', p.seat, big: true),
                ]),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: p.barcode.isEmpty ? null : () => openBoardingCode(context, p),
                    icon: const Icon(Icons.qr_code_2),
                    label: Text(companions.isEmpty
                        ? 'Arată biletul'
                        : 'Arată biletele (${companions.length + 1} pasageri)'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  ),
                ),
              ]),
            ),
          ),
          const SectionTitle('Pasager'),
          _infoCard(context, [
            InfoCell('Nume', p.passenger),
            InfoCell('Rezervare (PNR)', p.pnr),
            InfoCell('Clasă', p.cabin),
            InfoCell('Secvență', p.sequence),
            if (p.frequentFlyer.isNotEmpty) InfoCell('Fidelitate', p.frequentFlyer),
            if (p.aircraft.isNotEmpty) InfoCell('Avion', p.aircraft),
          ]),
          if (companions.isNotEmpty) ...[
            const SectionTitle('Pe aceeași rezervare'),
            for (final c in companions)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(c.passenger),
                subtitle: Text(c.seat.isEmpty ? 'Fără loc' : 'Loc ${c.seat}'),
                onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => PassDetailPage(passId: c.id))),
              ),
          ],
          const SectionTitle('Aeroporturi'),
          _airport(context, p.from, 'Plecare'),
          _airport(context, p.to, 'Sosire'),
          if (dist > 0)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: const Icon(Icons.straighten),
              title: Text('${km(dist)} km'),
              subtitle: Text('Durată ${durationText(flightDuration(p))}'
                  '${p.departure != null && p.arrival != null ? '' : ' (estimată)'}'),
            ),
          const SectionTitle('Ajutor'),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: const Icon(Icons.euro),
            title: const Text('Compensație pentru întârziere sau anulare'),
            subtitle: const Text('Calcul orientativ după regulamentul UE 261/2004'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showCompensationSheet(context, p),
          ),
          if (p.note.isNotEmpty) ...[
            const SectionTitle('Notă'),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Text(p.note)),
          ],
          if (p.statusCheckedAt != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Text('Status verificat la ${hm(p.statusCheckedAt!)}',
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ),
        ]),
      ),
    );
  }

  Widget _grid(List<Widget> cells) => Row(children: [for (final c in cells) Expanded(child: c)]);

  Widget _infoCard(BuildContext context, List<Widget> cells) {
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 2) {
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(child: cells[i]),
          Expanded(child: i + 1 < cells.length ? cells[i + 1] : const SizedBox()),
        ]),
      ));
    }
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 10), child: Column(children: rows)),
    );
  }

  Widget _airport(BuildContext context, String iata, String role) {
    final a = Airports.get(iata);
    final now = Airports.nowAt(iata);
    final offset = Airports.location(iata) == null
        ? ''
        : _offsetText(now.timeZoneOffset - DateTime.now().timeZoneOffset);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: CircleAvatar(child: Text(a == null ? '✈' : flag(a.country))),
      title: Text(a == null ? iata : '${a.label} ($iata)'),
      subtitle: Text([
        role,
        if (a != null) a.name,
        if (a != null && a.tz.isNotEmpty) 'ora locală ${hm(now)}$offset',
      ].join(' · ')),
    );
  }

  String _offsetText(Duration d) {
    if (d.inMinutes == 0) return '';
    final sign = d.isNegative ? '−' : '+';
    final m = d.inMinutes.abs();
    return ' ($sign${m ~/ 60}${m % 60 == 0 ? '' : ':${two(m % 60)}'} h față de tine)';
  }
}

String shareText(FlightPass p) {
  final lines = [
    '${p.flightCode} ${Airlines.name(p.carrier)}',
    '${Airports.city(p.from)} (${p.from}) → ${Airports.city(p.to)} (${p.to})',
    [longDate(p.day), if (p.departure != null) 'plecare ${Notifier.hmOf(p)}', if (p.arrival != null) 'sosire ${p.arrival}']
        .join(', '),
    if (p.status != FlightStatus.unknown) 'Status: ${statusLabels[p.status]}',
    if (p.gate.isNotEmpty) 'Poarta ${p.gate}',
  ];
  return lines.join('\n');
}
