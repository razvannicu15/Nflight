import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/airports.dart';
import '../core/i18n.dart';
import '../models/pass.dart';
import 'status_api.dart';

/// One row of an airport departures / arrivals board.
class BoardFlight {
  BoardFlight({
    required this.number,
    required this.airline,
    required this.otherIata,
    required this.otherName,
    required this.scheduled,
    this.revised,
    this.terminal = '',
    this.gate = '',
    this.status = '',
  });

  final String number; // "W6 3141"
  final String airline;
  final String otherIata; // destination for departures, origin for arrivals
  final String otherName;
  final String scheduled; // "HH:mm" local
  final String? revised; // "HH:mm" local, when different
  final String terminal;
  final String gate;
  final String status; // raw AeroDataBox status, lower case

  bool get cancelled => status.startsWith('cancel');
  bool get delayed => revised != null && revised != scheduled;

  String get statusText => switch (status) {
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

  /// Next ~11 hours (plus the last one) at [iata]. Cached for 5 minutes.
  static Future<(Board?, String?)> load(String iata, {bool force = false}) async {
    final cached = _cache[iata];
    if (!force && cached != null && DateTime.now().difference(cached.fetchedAt).inMinutes < 5) {
      return (cached, null);
    }
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
      final b = Board(parse(j['departures']), parse(j['arrivals']), DateTime.now());
      _cache[iata] = b;
      return (b, null);
    } catch (_) {
      return (null, tr('Fără conexiune.', 'No connection.'));
    }
  }

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
      final rev = _local(m['revisedTime']) ?? _local(m['runwayTime']);
      final iata = (ap['iata'] ?? '').toString();
      out.add(BoardFlight(
        number: (e['number'] ?? '').toString(),
        airline: e['airline'] is Map ? ((e['airline'] as Map)['name'] ?? '').toString() : '',
        otherIata: iata,
        otherName: Airports.get(iata)?.label ?? (ap['name'] ?? iata).toString(),
        scheduled: sched,
        revised: rev,
        terminal: (m['terminal'] ?? '').toString(),
        gate: (m['gate'] ?? '').toString(),
        status: (e['status'] ?? '').toString().toLowerCase(),
      ));
    }
    out.sort((a, b) => a.scheduled.compareTo(b.scheduled));
    return out;
  }
}
