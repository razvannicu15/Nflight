import 'package:flutter/material.dart';

import '../core/airlines.dart';
import '../core/airports.dart';
import '../core/i18n.dart';
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
    for (final p in store.passes) {
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
            headerSliverBuilder: (c, _) => [SliverAppBar.medium(title: Text(tr('Statistici', 'Stats')))],
            body: MaxWidth(
              child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<_Period>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: _Period.all, label: Text(tr('Total', 'All time'))),
                        ButtonSegment(value: _Period.year, label: Text('${DateTime.now().year}')),
                        ButtonSegment(value: _Period.month, label: Text(_cap(monthName(DateTime.now().month)))),
                      ],
                      selected: {_period},
                      onSelectionChanged: (s) => setState(() => _period = s.first),
                    ),
                  ),
                ),
                if (f.isEmpty) _empty(context) else ..._stats(context, f),
              ]),
            ),
          ),
        );
      },
    );
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Widget _empty(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 96),
      child: Column(children: [
        Icon(Icons.insights_outlined, size: 56, color: cs.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(tr('Niciun zbor încheiat', 'No completed flights'),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
      ]),
    );
  }

  /// Top 3 of [keys], as table rows. The label is shown on the first row only.
  static List<(String, String, String?)> _top(
      String label, Iterable<String> keys, String Function(String) name, String Function(int) count) {
    final m = <String, int>{};
    for (final k in keys) {
      m[k] = (m[k] ?? 0) + 1;
    }
    final e = (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(3).toList();
    return [for (final (i, x) in e.indexed) (i == 0 ? label : '', name(x.key), count(x.value))];
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

    var window = 0, aisle = 0;
    for (final p in f) {
      final m = RegExp(r'([A-K])$').firstMatch(p.seat);
      if (m == null) continue;
      final l = m.group(1)!;
      if (l == 'A' || l == 'F' || l == 'K') window++;
      if (l == 'C' || l == 'D' || l == 'G' || l == 'H') aisle++;
    }

    String times(int n) => n == 1 ? tr('1 zbor', '1 flight') : tr('$n zboruri', '$n flights');
    String route(FlightPass p) => '${p.from} → ${p.to}';

    return [
      // Hero: the one number people look for, the rest in a hairline row.
      Card(
        elevation: 0,
        color: cs.primaryContainer,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text('${f.length}',
                  style: t.displayMedium?.copyWith(color: cs.onPrimaryContainer, fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              Text(f.length == 1 ? tr('zbor', 'flight') : tr('zboruri', 'flights'),
                  style: t.titleLarge?.copyWith(color: cs.onPrimaryContainer)),
            ]),
            const SizedBox(height: 18),
            CellRow([
              ('km', km(total)),
              (tr('În aer', 'In air'), durationText(air)),
              (tr('Aerop.', 'Airports'), '${airports.length}'),
              (tr('Țări', 'Countries'), '${countries.length}'),
            ], color: cs.onPrimaryContainer, big: false),
          ]),
        ),
      ),
      SectionTitle(tr('Recorduri', 'Records')),
      InfoTable([
        (tr('Cel mai lung', 'Longest'), route(byLen.last), '${km(dist(byLen.last))} km'),
        if (f.length > 1) (tr('Cel mai scurt', 'Shortest'), route(byLen.first), '${km(dist(byLen.first))} km'),
        if (window + aisle > 0)
          (
            tr('Loc preferat', 'Favourite seat'),
            window >= aisle ? tr('Geam', 'Window') : tr('Culoar', 'Aisle'),
            tr('$window geam · $aisle culoar', '$window window · $aisle aisle'),
          ),
      ]),
      SectionTitle(tr('Cele mai dese', 'Most frequent')),
      InfoTable([
        ..._top(tr('Rute', 'Routes'), f.map((p) => ([p.from, p.to]..sort()).join(' – ')), (k) => k, times),
        ..._top(tr('Companii', 'Airlines'), f.map((p) => p.carrier), Airlines.name, times),
        ..._top(tr('Aeroporturi', 'Airports'), f.expand((p) => [p.from, p.to]),
            (k) => '${Airports.city(k)} · $k', times),
      ]),
    ];
  }
}
