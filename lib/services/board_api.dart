import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:timezone/timezone.dart' as tz;

import '../core/airports.dart';
import '../core/i18n.dart';
import '../models/pass.dart';
import 'status_api.dart';
import 'store.dart';

/// One row of an airport departures / arrivals board.
class BoardFlight {
  BoardFlight({
    required this.number,
    required this.airline,
    required this.otherIata,
    required this.otherName,
    required this.scheduled,
    this.day = '',
    this.revised,
    this.terminal = '',
    this.gate = '',
    this.status = '',
    this.label,
    this.cancelledFlag = false,
    this.callsign = '',
    this.icao24 = '',
  });

  final String callsign;
  final String icao24;

  final String number; // "W6 3141"
  final String airline;
  final String otherIata; // destination for departures, origin for arrivals
  final String otherName;
  final String scheduled; // "HH:mm" local
  final String day; // "yyyy-MM-dd" local, for ordering and day headers
  final String? revised; // "HH:mm" local, when different
  final String terminal;
  final String gate;
  final String status; // raw AeroDataBox status, lower case

  /// Ready-made status text from the airport itself (Cluj), already translated.
  final String? label;
  final bool cancelledFlag;

  bool get cancelled => cancelledFlag || status.startsWith('cancel');
  bool get delayed => revised != null && revised != scheduled;

  String get statusText => label ?? switch (status) {
        'canceled' || 'cancelled' || 'canceleduncertain' => tr('Anulat', 'Cancelled'),
        'boarding' => tr('Îmbarcare', 'Boarding'),
        'gateclosed' => tr('Poarta închisă', 'Gate closed'),
        'departed' || 'enroute' => tr('A decolat', 'Departed'),
        'approaching' => tr('În apropiere', 'Approaching'),
        'arrived' => tr('A aterizat', 'Landed'),
        'diverted' => tr('Deviat', 'Diverted'),
        'delayed' => tr('Întârziat', 'Delayed'),
        'checkin' => 'Check-in',
        _ => delayed ? tr('Întârziat', 'Delayed') : '',
      };

  bool matches(FlightPass p) =>
      number.replaceAll(' ', '').toUpperCase() == '${p.carrier}${p.flightNumber}'.toUpperCase();
}

class Board {
  Board(this.departures, this.arrivals, this.fetchedAt);
  final List<BoardFlight> departures;
  final List<BoardFlight> arrivals;
  final DateTime fetchedAt;
}

class BoardApi {
  static final Map<String, Board> _cache = {};

  /// Airports that publish their own board (free, with gates). Backup only:
  /// it fills what the API lacks, or stands in when the API is unavailable.
  static bool hasOwnSource(String iata) => iata == 'CLJ';

  /// Next ~11 hours (plus the last one) at [iata]. Cached for 3 minutes.
  static Future<(Board?, String?)> load(String iata, {bool force = false}) async {
    final cached = _cache[iata];
    if (!force && cached != null && DateTime.now().difference(cached.fetchedAt).inMinutes < 3) {
      return (cached, null);
    }
    final (api, err) = await _loadApi(iata);
    if (!hasOwnSource(iata)) {
      if (api != null) _cache[iata] = api;
      return (api, err);
    }
    final (own, _) = await _loadCluj();
    final apiEmpty = api == null || (api.departures.isEmpty && api.arrivals.isEmpty);
    final b = apiEmpty ? (own ?? api) : (own == null ? api : _merge(api, own));
    if (b != null) _cache[iata] = b;
    return (b, b == null ? err : null);
  }

  /// API rows win; the airport feed adds missing gate / belt / status.
  static Board _merge(Board api, Board own) {
    String norm(String n) => n.replaceAll(' ', '').toUpperCase();
    List<BoardFlight> mix(List<BoardFlight> a, List<BoardFlight> o, bool departures) {
      final byNo = {for (final f in o) '${norm(f.number)}|${f.day}': f};
      return [
        for (final f in a)
          () {
            final x = byNo['${norm(f.number)}|${f.day}'];
            if (x == null) return f;
            return BoardFlight(
              number: f.number,
              airline: f.airline,
              otherIata: f.otherIata,
              otherName: f.otherName,
              scheduled: f.scheduled,
              day: f.day,
              revised: f.revised ?? x.revised,
              terminal: f.terminal.isNotEmpty ? f.terminal : x.terminal,
              gate: f.gate.isNotEmpty ? f.gate : x.gate,
              status: f.status,
              label: f.statusText.isNotEmpty ? null : x.label,
              cancelledFlag: f.cancelled || x.cancelled,
              callsign: f.callsign,
              icao24: f.icao24,
            );
          }(),
      ];
    }

    return Board(mix(api.departures, own.departures, true), mix(api.arrivals, own.arrivals, false), DateTime.now());
  }

  /// Backup API key (aviationstack, 100 calls/month): only when AeroDataBox fails.
  static const avKey = String.fromEnvironment('AVIATIONSTACK_KEY');

  static Future<(Board?, String?)> _loadApi(String iata) async {
    final (b, err) = await _loadAeroDataBox(iata);
    if (b != null || avKey.isEmpty) return (b, err);
    final (b2, err2) = await _loadAviationstack(iata);
    return (b2, b2 == null ? err : err2);
  }

  // ---- aviationstack (backup) -----------------------------------------------------------------

  static Future<(Board?, String?)> _loadAviationstack(String iata) async {
    final now = Airports.nowAt(iata);
    final from = now.subtract(const Duration(hours: 1)), to = now.add(const Duration(hours: 12));
    final lo = '${ymd(from)} ${hm(from)}', hi = '${ymd(to)} ${hm(to)}';
    final lists = <List<BoardFlight>>[];
    try {
      for (final side in ['dep_iata', 'arr_iata']) {
        final uri = Uri.https('api.aviationstack.com', '/v1/flights', {'access_key': avKey, side: iata, 'limit': '100'});
        final r = await http.get(uri).timeout(const Duration(seconds: 25));
        if (r.statusCode != 200) return (null, tr('Eroare server (${r.statusCode}).', 'Server error (${r.statusCode}).'));
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        if (j is! Map || j['data'] is! List) return (null, tr('Limita lunară a fost atinsă.', 'Monthly limit reached.'));
        final dep = side == 'dep_iata';
        final out = <BoardFlight>[];
        for (final e in j['data'] as List) {
          if (e is! Map) continue;
          final here = (dep ? e['departure'] : e['arrival']);
          final there = (dep ? e['arrival'] : e['departure']);
          if (here is! Map || there is! Map) continue;
          // aviationstack gives airport-local times (despite the +00:00 suffix).
          final s = (here['scheduled'] ?? '').toString();
          if (s.length < 16) continue;
          final day = s.substring(0, 10), sched = s.substring(11, 16);
          final key = '$day $sched';
          if (key.compareTo(lo) < 0 || key.compareTo(hi) > 0) continue;
          final est = (here['estimated'] ?? '').toString();
          final rev = est.length >= 16 ? est.substring(11, 16) : null;
          final fl = e['flight'] is Map ? e['flight'] as Map : const {};
          final al = e['airline'] is Map ? e['airline'] as Map : const {};
          final code = (al['iata'] ?? '').toString();
          final other = (there['iata'] ?? '').toString();
          final st = (e['flight_status'] ?? '').toString().toLowerCase();
          out.add(BoardFlight(
            number: '$code ${fl['number'] ?? ''}'.trim(),
            airline: (al['name'] ?? '').toString(),
            otherIata: other,
            otherName: Airports.get(other)?.label ?? (there['airport'] ?? other).toString(),
            scheduled: sched,
            day: day,
            revised: rev != null && rev != sched ? rev : null,
            terminal: dep ? (here['terminal'] ?? '').toString() : (here['baggage'] ?? '').toString(),
            gate: dep ? (here['gate'] ?? '').toString() : '',
            status: switch (st) {
              'cancelled' => 'cancelled',
              'active' => dep ? 'departed' : 'approaching',
              'landed' => dep ? 'departed' : 'arrived',
              'diverted' => 'diverted',
              _ => '',
            },
          ));
        }
        // Codeshares repeat the same physical flight: keep one row per time + destination.
        final seen = <String>{};
        out.sort((a, b) => '${a.day} ${a.scheduled}'.compareTo('${b.day} ${b.scheduled}'));
        lists.add(out.where((f) => seen.add('${f.day}${f.scheduled}${f.otherIata}')).toList());
      }
    } catch (_) {
      return (null, tr('Fără conexiune.', 'No connection.'));
    }
    return (Board(lists[0], lists[1], DateTime.now()), null);
  }

  // ---- AeroDataBox (main) ---------------------------------------------------------------------

  static Future<(Board?, String?)> _loadAeroDataBox(String iata) async {
    if (!StatusApi.enabled) return (null, tr('Status live inactiv.', 'Live status is off.'));
    final now = Airports.nowAt(iata);
    String f(DateTime d) => '${ymd(d)}T${hm(d)}';
    final from = now.subtract(const Duration(hours: 1));
    final to = now.add(const Duration(hours: 11));
    final uri = Uri.https(StatusApi.host, '/flights/airports/iata/$iata/${f(from)}/${f(to)}', {
      'withLeg': 'false',
      'direction': 'Both',
      'withCancelled': 'true',
      'withCodeshared': 'false',
      'withCargo': 'false',
      'withPrivate': 'false',
      'withLocation': 'false',
    });
    try {
      final r = await http.get(uri, headers: {
        'X-RapidAPI-Key': StatusApi.key,
        'X-RapidAPI-Host': StatusApi.host,
      }).timeout(const Duration(seconds: 25));
      if (r.statusCode == 429) return (null, tr('Limita lunară a fost atinsă.', 'Monthly limit reached.'));
      if (r.statusCode == 204 || r.body.trim().isEmpty) return (Board([], [], DateTime.now()), null);
      if (r.statusCode != 200) return (null, tr('Eroare server (${r.statusCode}).', 'Server error (${r.statusCode}).'));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      return (Board(parse(j['departures']), parse(j['arrivals']), DateTime.now()), null);
    } catch (_) {
      return (null, tr('Fără conexiune.', 'No connection.'));
    }
  }

  /// Your flights leaving an airport with its own board in the next 24 h get the gate from it.
  static Future<void> fillGates() async {
    final now = DateTime.now();
    final soon = store.upcoming.where((p) =>
        hasOwnSource(p.from) && Store.departureOf(p).difference(now).inHours < 24);
    for (final p in soon) {
      final (b, _) = await load(p.from);
      if (b == null) continue;
      for (final f in b.departures) {
        if (!f.matches(p) || f.day != p.date) continue;
        var changed = false;
        if (f.gate.isNotEmpty && f.gate != p.gate) {
          p.gate = f.gate;
          changed = true;
        }
        if (f.cancelled && p.status != FlightStatus.cancelled) {
          p.status = FlightStatus.cancelled;
          changed = true;
        }
        if (changed) {
          for (final c in [p, ...store.companions(p)]) {
            c.gate = p.gate;
            if (f.cancelled) c.status = FlightStatus.cancelled;
          }
          await store.save();
        }
      }
    }
  }

  // ---- Cluj airport (www.airportcluj.ro) -------------------------------------------------

  static const _clujUrl = 'https://www.airportcluj.ro/wp-json/airportcluj-flights/v1/flights';

  static Future<(Board?, String?)> _loadCluj() async {
    final now = Airports.nowAt('CLJ');
    final days = {ymd(now), ymd(now.add(const Duration(hours: 12)))};
    final dep = <BoardFlight>[], arr = <BoardFlight>[];
    try {
      for (final type in ['departure', 'arrival']) {
        for (final day in days) {
          final r = await http
              .get(Uri.parse('$_clujUrl?type=$type&date=$day'), headers: {'Accept': 'application/json'})
              .timeout(const Duration(seconds: 20));
          if (r.statusCode != 200) return (null, tr('Eroare server (${r.statusCode}).', 'Server error (${r.statusCode}).'));
          final j = jsonDecode(utf8.decode(r.bodyBytes));
          final list = j is Map ? j['flights'] : null;
          if (list is List) (type == 'departure' ? dep : arr).addAll(_parseCluj(list, type == 'departure'));
        }
      }
    } catch (_) {
      return (null, tr('Fără conexiune.', 'No connection.'));
    }
    final from = now.subtract(const Duration(hours: 1)), to = now.add(const Duration(hours: 12));
    String key(BoardFlight f) => '${f.day} ${f.scheduled}';
    bool inWindow(BoardFlight f) =>
        key(f).compareTo('${ymd(from)} ${hm(from)}') >= 0 && key(f).compareTo('${ymd(to)} ${hm(to)}') <= 0;
    List<BoardFlight> clean(List<BoardFlight> l) {
      final seen = <String>{};
      final out = l.where((f) => inWindow(f) && seen.add('${f.number}${key(f)}')).toList()
        ..sort((a, b) => key(a).compareTo(key(b)));
      return out;
    }
    return (Board(clean(dep), clean(arr), DateTime.now()), null);
  }

  static List<BoardFlight> _parseCluj(List list, bool departures) {
    final loc = Airports.location('CLJ');
    DateTime? local(dynamic v) {
      final d = DateTime.tryParse((v ?? '').toString());
      if (d == null) return null;
      return loc == null ? d.toLocal() : tz.TZDateTime.from(d, loc);
    }

    final out = <BoardFlight>[];
    for (final e in list) {
      if (e is! Map) continue;
      final sched = local(e['scheduled'] ?? e['flight_time']);
      if (sched == null) continue;
      final est = local(e['estimated']);
      final other = (departures ? e['destination'] : e['origin']);
      final o = other is Map ? other : const {};
      final iata = (o['iata'] ?? '').toString();
      final al = e['airline'] is Map ? e['airline'] as Map : const {};
      final code = (al['code'] ?? '').toString();
      var no = (e['flight_number'] ?? '').toString();
      if (code.isNotEmpty && no.startsWith(code)) no = '$code ${no.substring(code.length)}';
      final statusCode = (e['status_code'] ?? '').toString().toUpperCase();
      var label = (isEn ? e['status_api'] : e['status'])?.toString().trim() ?? '';
      if (label == '—' || label == '-') label = '';
      if (isEn && label.isNotEmpty) label = label[0] + label.substring(1).toLowerCase();
      final belts = e['baggage_claim'];
      final belt = belts is List ? belts.map((b) => b.toString()).where((b) => b.isNotEmpty).join(', ') : '';
      out.add(BoardFlight(
        number: no,
        airline: (al['name'] ?? '').toString(),
        otherIata: iata,
        otherName: (isEn ? o['name_api'] : o['name_ro'])?.toString() ?? Airports.city(iata),
        scheduled: hm(sched),
        day: ymd(sched),
        revised: est != null && hm(est) != hm(sched) ? hm(est) : null,
        gate: departures ? (e['gate'] ?? '').toString() : '',
        terminal: departures ? '' : belt,
        status: statusCode.toLowerCase(),
        label: label,
        cancelledFlag: statusCode.startsWith('CNL') || statusCode.startsWith('CAN') ||
            label.toLowerCase().contains('anulat') || label.toLowerCase().contains('cancel'),
      ));
    }
    return out;
  }

  // ---- AeroDataBox --------------------------------------------------------------------------

  static String? _local(dynamic t) {
    if (t is! Map) return null;
    final s = t['local']?.toString();
    return (s == null || s.length < 16) ? null : s.substring(11, 16);
  }

  static List<BoardFlight> parse(dynamic list) {
    if (list is! List) return [];
    final out = <BoardFlight>[];
    for (final e in list) {
      if (e is! Map) continue;
      final m = e['movement'] is Map ? e['movement'] as Map : const {};
      final ap = m['airport'] is Map ? m['airport'] as Map : const {};
      final sched = _local(m['scheduledTime']);
      if (sched == null) continue;
      final rev = _local(m['runwayTime']) ?? _local(m['revisedTime']) ?? _local(m['predictedTime']);
      final st = m['scheduledTime'];
      final day = st is Map ? (st['local'] ?? '').toString() : '';
      final iata = (ap['iata'] ?? '').toString();
      final ac = e['aircraft'] is Map ? e['aircraft'] as Map : const {};
      out.add(BoardFlight(
        callsign: (e['callSign'] ?? '').toString().replaceAll(' ', ''),
        icao24: (ac['modeS'] ?? '').toString().toLowerCase(),
        number: (e['number'] ?? '').toString(),
        airline: e['airline'] is Map ? ((e['airline'] as Map)['name'] ?? '').toString() : '',
        otherIata: iata,
        otherName: Airports.get(iata)?.label ?? (ap['name'] ?? iata).toString(),
        scheduled: sched,
        day: day.length >= 10 ? day.substring(0, 10) : '',
        revised: rev,
        terminal: (m['terminal'] ?? '').toString(),
        gate: (m['gate'] ?? '').toString(),
        status: (e['status'] ?? '').toString().toLowerCase(),
      ));
    }
    out.sort((a, b) => '${a.day} ${a.scheduled}'.compareTo('${b.day} ${b.scheduled}'));
    return out;
  }
}
