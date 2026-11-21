import 'dart:async';

import 'package:flutter/material.dart';

import '../core/airports.dart';
import '../core/i18n.dart';
import '../models/pass.dart';
import '../services/board_api.dart';
import '../services/status_api.dart';
import '../services/store.dart';
import '../core/airlines.dart';
import 'live_card.dart';
import 'widgets.dart';

/// Airport tab: departures / arrivals board for a saved airport.
class BoardPage extends StatefulWidget {
  const BoardPage({super.key, this.active = true, this.preview});

  /// Only the visible tab talks to the network.
  final bool active;

  /// Ready data (screenshot tests); skips the network.
  final Board? preview;

  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage> {
  Board? _board;
  String? _error;
  bool _loading = false;
  String? _shown;
  Timer? _timer;

  String get _iata => store.boardAirport;

  @override
  void initState() {
    super.initState();
    if (widget.preview != null) {
      _board = widget.preview;
      _shown = _iata;
    } else if (widget.active) {
      _start();
    }
  }

  @override
  void didUpdateWidget(BoardPage old) {
    super.didUpdateWidget(old);
    if (widget.preview != null) return;
    if (widget.active && !old.active) _start();
    if (!widget.active && old.active) _timer?.cancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Load now and keep the board fresh while the tab is open.
  void _start() {
    _load();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 3), (_) => _load());
  }

  Future<void> _load({bool force = false}) async {
    final iata = _iata;
    setState(() {
      _loading = _board == null || _shown != iata;
      if (_shown != iata) _board = null;
    });
    final (b, err) = await BoardApi.load(iata, force: force);
    if (!mounted || iata != _iata) return;
    setState(() {
      _loading = false;
      _shown = iata;
      if (b != null) _board = b;
      _error = err;
    });
  }

  void _select(String iata) {
    if (iata == _iata) return;
    store.boardAirport = iata;
    store.save();
    if (widget.preview == null) _load();
  }

  void _remove(String iata) {
    if (store.boardAirports.length <= 1) return;
    store.boardAirports.remove(iata);
    if (store.boardAirport == iata) store.boardAirport = store.boardAirports.first;
    store.save();
    if (widget.preview == null) _load();
  }

  Future<void> _add() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AirportSearch(),
    );
    if (picked == null) return;
    if (!store.boardAirports.contains(picked)) store.boardAirports.add(picked);
    _select(picked);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final a = Airports.get(_iata);
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            body: NestedScrollView(
              headerSliverBuilder: (c, _) => [
                SliverAppBar.medium(
                  title: Text(a?.label ?? _iata),
                  pinned: true,
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(104),
                    child: Column(children: [
                      SizedBox(height: 56, child: _chips()),
                      TabBar(tabs: [
                        Tab(text: tr('Plecări', 'Departures')),
                        Tab(text: tr('Sosiri', 'Arrivals')),
                      ]),
                    ]),
                  ),
                ),
              ],
              body: !StatusApi.enabled && BoardApi.avKey.isEmpty && !BoardApi.hasOwnSource(_iata) && widget.preview == null
                  ? _message(tr('Status live inactiv', 'Live status is off'), retry: false)
                  : _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _board == null
                          ? _message(_error ?? '')
                          : TabBarView(children: [
                              _list(_board!.departures, departures: true),
                              _list(_board!.arrivals, departures: false),
                            ]),
            ),
          ),
        );
      },
    );
  }

  Widget _chips() {
    final list = store.boardAirports;
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        for (final code in list)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InputChip(
              label: Text(code),
              selected: code == _iata,
              showCheckmark: false,
              onSelected: (_) => _select(code),
              onDeleted: code == _iata && list.length > 1 ? () => _remove(code) : null,
            ),
          ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 18),
          label: Text(tr('Adaugă', 'Add')),
          onPressed: _add,
        ),
      ],
    );
  }

  Widget _message(String text, {bool retry = true}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            if (retry) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: () => _load(force: true), child: Text(tr('Reîncearcă', 'Retry'))),
            ],
          ]),
        ),
      );

  Widget _list(List<BoardFlight> list, {required bool departures}) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
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
    // Columns without any data (e.g. no gates at CLJ) are left out.
    final place = (BoardFlight f) => departures ? f.gate : f.terminal;
    final showPlace = list.any((f) => place(f).isNotEmpty);
    final showStatus = list.any((f) => f.statusText.isNotEmpty);
    final today = ymd(Airports.nowAt(store.boardAirport));

    // Rows plus a day header whenever the date changes after today.
    final rows = <Object>[];
    String? lastDay;
    for (final f in list) {
      if (f.day.isNotEmpty && f.day != lastDay) {
        if (lastDay != null || f.day != today) rows.add(f.day);
        lastDay = f.day;
      }
      rows.add(f);
    }

    Widget headerRow() => Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(children: [
            SizedBox(width: 62, child: Text(tr('ORA', 'TIME'), style: header)),
            const SizedBox(width: 34),
            Expanded(child: Text(departures ? tr('SPRE', 'TO') : tr('DIN', 'FROM'), style: header)),
            if (showStatus || showPlace) SizedBox(width: 96, child: Text('STATUS', textAlign: TextAlign.end, style: header)),
          ]),
        );

    Widget dayRow(String day) {
      final d = DateTime.tryParse(day);
      final tomorrow = d != null && DateTime.tryParse(today) != null &&
          d.difference(DateTime.parse(today)).inDays == 1;
      return Container(
        width: double.infinity,
        color: cs.surfaceContainerHigh,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Text(
          tomorrow ? tr('Mâine', 'Tomorrow') : (d == null ? day : longDate(d)),
          style: t.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
        ),
      );
    }

    Widget flightRow(BoardFlight f) {
      final mine = store.upcoming.any(f.matches);
      final late = f.delayed && !f.cancelled;
      final statusColor = f.cancelled
          ? cs.error
          : late
              ? const Color(0xFFE65100)
              : cs.onSurfaceVariant;
      final parts = f.number.split(' ');
      final target = LiveTarget(
        from: departures ? store.boardAirport : f.otherIata,
        to: departures ? f.otherIata : store.boardAirport,
        callsign: f.callsign.isNotEmpty
            ? f.callsign
            : (parts.length == 2 ? guessCallsign(parts[0], parts[1]) ?? '' : ''),
        icao24: f.icao24,
        title: f.number,
        carrier: parts.isNotEmpty ? parts[0] : '',
        aircraft: f.aircraft,
        schedDep: departures ? f.scheduled : null,
        schedArr: departures ? null : f.scheduled,
        date: f.day,
      );
      final canTrack = target.from.isNotEmpty && target.to.isNotEmpty && target.from != target.to;
      return InkWell(
        onTap: canTrack ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LivePage(target: target))) : null,
        child: Container(
        color: mine ? cs.primaryContainer.withValues(alpha: 0.55) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 62,
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
          Padding(
            padding: const EdgeInsets.only(right: 10, top: 2),
            child: AirlineBadge(parts.isNotEmpty ? parts[0] : '', size: 24),
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
          if (showStatus || showPlace)
            SizedBox(
              width: 96,
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(f.statusText,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(color: statusColor, fontWeight: FontWeight.w600)),
                if (place(f).isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: departures ? tr('Poarta ', 'Gate ') : (BoardApi.hasOwnSource(_iata) ? tr('Banda ', 'Belt ') : 'Term. '),
                          style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                      TextSpan(text: place(f), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tab)),
                    ]),
                    textAlign: TextAlign.end,
                  ),
                ],
              ]),
            ),
        ]),
        ),
      );
    }

    final divider = Divider(height: 1, thickness: 0.6, indent: 16, endIndent: 16, color: cs.outlineVariant.withValues(alpha: 0.6));
    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: MaxWidth(
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 32),
          itemCount: rows.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) return headerRow();
            final r = rows[i - 1];
            if (r is String) return dayRow(r);
            final next = i < rows.length ? rows[i] : null;
            return Column(mainAxisSize: MainAxisSize.min, children: [
              flightRow(r as BoardFlight),
              if (next is BoardFlight) divider,
            ]);
          },
        ),
      ),
    );
  }
}

/// Type a code or city; pick from matches.
class _AirportSearch extends StatefulWidget {
  const _AirportSearch();
  @override
  State<_AirportSearch> createState() => _AirportSearchState();
}

class _AirportSearchState extends State<_AirportSearch> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final results = Airports.search(_q).take(30).toList();
    final exact = results.where((a) => a.iata.toLowerCase() == _q.trim().toLowerCase());
    final ordered = [...exact, ...results.where((a) => !exact.contains(a))];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: tr('Cod sau oraș', 'Code or city'),
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Expanded(
            child: ListView(children: [
              for (final a in ordered)
                ListTile(
                  leading: CircleAvatar(child: Text(a.iata, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                  title: Text(a.label),
                  subtitle: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(context, a.iata),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
