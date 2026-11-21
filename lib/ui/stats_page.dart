import 'package:flutter/material.dart';

import '../core/airlines.dart';
import '../core/airports.dart';
import '../models/pass.dart';
import '../services/store.dart';
import 'widgets.dart';

enum _Period { all, year, month }

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});
  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  _Period _period = _Period.all;

  /// Flights taken (one per physical flight, not per passenger).
  List<FlightPass> _flights() {
    final now = DateTime.now();
    final seen = <String>{};
    final out = <FlightPass>[];
    final sorted = [...store.passes]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final p in sorted) {
      if (!Store.isPast(p) || p.status == FlightStatus.cancelled) continue;
      if (_period == _Period.year && p.day.year != now.year) continue;
      if (_period == _Period.month && (p.day.year != now.year || p.day.month != now.month)) continue;
      if (seen.add('${p.carrier}${p.flightNumber}${p.date}${p.from}')) out.add(p);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final f = _flights();
        return Scaffold(
          body: NestedScrollView(
            headerSliverBuilder: (c, _) => [const SliverAppBar.medium(title: Text('Statistici'))],
            body: MaxWidth(
              child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: SegmentedButton<_Period>(
                    segments: const [
                      ButtonSegment(value: _Period.all, label: Text('Total')),
                      ButtonSegment(value: _Period.year, label: Text('Anul ăsta')),
                      ButtonSegment(value: _Period.month, label: Text('Luna asta')),
                    ],
                    selected: {_period},
                    onSelectionChanged: (s) => setState(() => _period = s.first),
                  ),
                ),
                if (f.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Statisticile apar după primul zbor încheiat.', textAlign: TextAlign.center),
                  )
                else
                  ..._stats(context, f),
              ]),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _stats(BuildContext context, List<FlightPass> f) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    double dist(FlightPass p) => Airports.distanceKm(p.from, p.to);
    final total = f.fold<double>(0, (s, p) => s + dist(p));
    final air = f.fold<Duration>(Duration.zero, (s, p) => s + flightDuration(p));
    final airports = {for (final p in f) ...[p.from, p.to]};
    final countries = {for (final a in airports) Airports.get(a)?.country}..remove(null);
    final byLen = [...f]..sort((a, b) => dist(a).compareTo(dist(b)));

    Map<String, int> count(Iterable<String> keys) {
      final m = <String, int>{};
      for (final k in keys) {
        m[k] = (m[k] ?? 0) + 1;
      }
      return Map.fromEntries(m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
    }

    final routes = count(f.map((p) => ([p.from, p.to]..sort()).join(' ⇄ ')));
    final airlines = count(f.map((p) => p.carrier));
    final ports = count(f.expand((p) => [p.from, p.to]));

    var window = 0, aisle = 0;
    for (final p in f) {
      final m = RegExp(r'([A-K])$').firstMatch(p.seat);
      if (m == null) continue;
      final l = m.group(1)!;
      if (l == 'A' || l == 'F' || l == 'K') window++;
      if (l == 'C' || l == 'D' || l == 'G' || l == 'H') aisle++;
    }

    Widget big(String value, String label, IconData icon) => Expanded(
          child: Card(
            elevation: 0,
            color: cs.surfaceContainerLow,
            margin: const EdgeInsets.all(5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, color: cs.primary),
                const SizedBox(height: 10),
                Text(value, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                Text(label, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
          ),
        );

    Widget ranking(String title, Map<String, int> m, String Function(String) label, {Widget Function(String)? lead}) {
      final top = m.entries.take(5).toList();
      if (top.isEmpty) return const SizedBox.shrink();
      final max = top.first.value;
      return Column(children: [
        SectionTitle(title),
        for (final e in top)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(children: [
              if (lead != null) ...[lead(e.key), const SizedBox(width: 12)],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(label(e.key), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: e.value / max, minHeight: 6),
                  ),
                ]),
              ),
            ]),
          ),
      ]);
    }

    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11),
        child: Column(children: [
          Row(children: [
            big('${f.length}', f.length == 1 ? 'zbor' : 'zboruri', Icons.flight),
            big(km(total), 'kilometri', Icons.public),
          ]),
          Row(children: [
            big(durationText(air), 'în aer', Icons.schedule),
            big('${airports.length}', 'aeroporturi · ${countries.length} țări', Icons.place_outlined),
          ]),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Text(
          'Echivalentul a ${(total / 40075).toStringAsFixed(2)} ocoluri ale Pământului'
          '${total > 384400 ? ' sau ${(total / 384400).toStringAsFixed(1)} drumuri până la Lună' : ''}.',
          style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      ),
      const SectionTitle('Recorduri'),
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        leading: const Icon(Icons.trending_up),
        title: Text('Cel mai lung: ${byLen.last.from} → ${byLen.last.to}'),
        subtitle: Text('${km(dist(byLen.last))} km · ${shortDate(byLen.last.day)} ${byLen.last.day.year}'),
      ),
      if (f.length > 1)
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.trending_down),
          title: Text('Cel mai scurt: ${byLen.first.from} → ${byLen.first.to}'),
          subtitle: Text('${km(dist(byLen.first))} km · ${shortDate(byLen.first.day)} ${byLen.first.day.year}'),
        ),
      if (window + aisle > 0)
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.event_seat_outlined),
          title: Text(window >= aisle ? 'Preferi geamul' : 'Preferi culoarul'),
          subtitle: Text('$window la geam · $aisle la culoar'),
        ),
      ranking('Rute', routes, (k) => k),
      ranking('Companii', airlines, Airlines.name, lead: (k) => AirlineBadge(k, size: 28)),
      ranking('Aeroporturi', ports, (k) => '${Airports.city(k)} ($k)',
          lead: (k) => Text(flag(Airports.get(k)?.country ?? ''), style: const TextStyle(fontSize: 20))),
    ];
  }
}
