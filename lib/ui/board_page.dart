import 'package:flutter/material.dart';

import '../core/airports.dart';
import '../core/i18n.dart';
import '../models/pass.dart';
import '../services/board_api.dart';
import 'widgets.dart';

/// Airport departures / arrivals, like the screens in the terminal.
class BoardPage extends StatefulWidget {
  const BoardPage({super.key, required this.iata, this.arrivals = false, this.highlight, this.preview});
  final String iata;
  final bool arrivals;

  /// The user's flight, marked in the list.
  final FlightPass? highlight;

  /// Ready data (screenshot tests); skips the network.
  final Board? preview;

  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage> {
  Board? _board;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.preview != null) {
      _board = widget.preview;
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load({bool force = false}) async {
    setState(() => _loading = _board == null);
    final (b, err) = await BoardApi.load(widget.iata, force: force);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (b != null) _board = b;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = Airports.get(widget.iata);
    return DefaultTabController(
      length: 2,
      initialIndex: widget.arrivals ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(
          title: Text(a == null ? widget.iata : '${a.label} · ${widget.iata}'),
          bottom: TabBar(tabs: [
            Tab(text: tr('Plecări', 'Departures')),
            Tab(text: tr('Sosiri', 'Arrivals')),
          ]),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _board == null
                ? _message(_error ?? '')
                : TabBarView(children: [
                    _list(_board!.departures, departures: true),
                    _list(_board!.arrivals, departures: false),
                  ]),
      ),
    );
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: () => _load(force: true), child: Text(tr('Reîncearcă', 'Retry'))),
          ]),
        ),
      );

  Widget _list(List<BoardFlight> list, {required bool departures}) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final hl = widget.highlight;
    if (list.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: ListView(children: [
          const SizedBox(height: 120),
          Center(child: Text(tr('Niciun zbor în următoarele ore', 'No flights in the next hours'),
              style: t.bodyLarge?.copyWith(color: cs.onSurfaceVariant))),
        ]),
      );
    }
    const tab = [FontFeature.tabularFigures()];
    final header = t.labelSmall?.copyWith(color: cs.onSurfaceVariant, letterSpacing: 0.8);
    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: MaxWidth(
        child: ListView.separated(
          padding: const EdgeInsets.only(bottom: 32),
          itemCount: list.length + 1,
          separatorBuilder: (_, i) =>
              Divider(height: 1, thickness: 0.6, indent: 16, endIndent: 16, color: cs.outlineVariant.withValues(alpha: 0.6)),
          itemBuilder: (_, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(children: [
                  SizedBox(width: 58, child: Text(tr('ORA', 'TIME'), style: header)),
                  Expanded(child: Text(departures ? tr('SPRE', 'TO') : tr('DIN', 'FROM'), style: header)),
                  SizedBox(width: 52, child: Text(departures ? tr('POARTA', 'GATE') : 'TERM.', style: header)),
                  SizedBox(width: 92, child: Text('STATUS', textAlign: TextAlign.end, style: header)),
                ]),
              );
            }
            final f = list[i - 1];
            final mine = hl != null && f.matches(hl);
            final late = f.delayed && !f.cancelled;
            final statusColor = f.cancelled
                ? cs.error
                : late
                    ? const Color(0xFFE65100)
                    : cs.onSurfaceVariant;
            return Container(
              color: mine ? cs.primaryContainer.withValues(alpha: 0.55) : null,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 58,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(late ? f.revised! : f.scheduled,
                        style: t.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700, fontFeatures: tab, color: late ? statusColor : null)),
                    if (late)
                      Text(f.scheduled,
                          style: t.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant, decoration: TextDecoration.lineThrough, fontFeatures: tab)),
                  ]),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(f.otherName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyLarge?.copyWith(fontWeight: mine ? FontWeight.w800 : FontWeight.w600)),
                    Text('${f.number} · ${f.airline}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                ),
                SizedBox(
                  width: 52,
                  child: Text((departures ? f.gate : f.terminal).isEmpty ? '—' : (departures ? f.gate : f.terminal),
                      style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: tab)),
                ),
                SizedBox(
                  width: 92,
                  child: Text(f.statusText,
                      textAlign: TextAlign.end,
                      maxLines: 2,
                      style: t.bodySmall?.copyWith(color: statusColor, fontWeight: FontWeight.w600)),
                ),
              ]),
            );
          },
        ),
      ),
    );
  }
}
