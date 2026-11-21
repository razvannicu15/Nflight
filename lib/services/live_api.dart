import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../core/airports.dart';

/// A plane's position from OpenSky Network (free ADS-B data, non-commercial use).
class LiveState {
  LiveState({
    required this.lat,
    required this.lon,
    required this.altitudeM,
    required this.speedKmh,
    required this.track,
    required this.onGround,
    required this.seen,
    this.icao24 = '',
    this.path = const [],
  });
  final String icao24;

  /// Flown path so far as (lat, lon) pairs, when OpenSky has it.
  final List<(double, double)> path;

  LiveState withPath(List<(double, double)> p) => LiveState(
      lat: lat, lon: lon, altitudeM: altitudeM, speedKmh: speedKmh, track: track,
      onGround: onGround, seen: seen, icao24: icao24, path: p);
  final double lat;
  final double lon;
  final double altitudeM;
  final double speedKmh;
  final double track; // degrees, 0 = north
  final bool onGround;
  final DateTime seen;
}

class LiveApi {
  static const _base = 'opensky-network.org';

  /// Finds the plane by transponder hex (exact) or by callsign in the box
  /// spanning both airports. Returns null when it is not airborne/visible.
  static Future<LiveState?> find({String icao24 = '', String callsign = '', required String from, required String to}) async {
    try {
      if (icao24.isNotEmpty) {
        final s = await _query({'icao24': icao24.toLowerCase()});
        if (s.isNotEmpty) return _state(s.first);
      }
      if (callsign.isEmpty) return null;
      final a = Airports.get(from), b = Airports.get(to);
      if (a == null || b == null) return null;
      const pad = 3.0;
      final states = await _query({
        'lamin': '${max(-90.0, min(a.lat, b.lat) - pad)}',
        'lamax': '${min(90.0, max(a.lat, b.lat) + pad)}',
        'lomin': '${max(-180.0, min(a.lon, b.lon) - pad)}',
        'lomax': '${min(180.0, max(a.lon, b.lon) + pad)}',
      });
      final want = callsign.toUpperCase();
      for (final s in states) {
        if ((s[1] ?? '').toString().trim().toUpperCase() == want) return _state(s);
      }
    } catch (_) {}
    return null;
  }

  static Future<List<List>> _query(Map<String, String> q) async {
    final r = await http.get(Uri.https(_base, '/api/states/all', q)).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return [];
    final j = jsonDecode(r.body);
    final list = j is Map ? j['states'] : null;
    return list is List ? list.whereType<List>().toList() : [];
  }

  static LiveState? _state(List s) {
    final lon = (s[5] as num?)?.toDouble(), lat = (s[6] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    final contact = (s[4] as num?)?.toInt();
    return LiveState(
      lat: lat,
      lon: lon,
      altitudeM: ((s[13] ?? s[7]) as num?)?.toDouble() ?? 0,
      speedKmh: (((s[9] as num?)?.toDouble() ?? 0) * 3.6),
      track: (s[10] as num?)?.toDouble() ?? 0,
      onGround: s[8] == true,
      seen: contact == null ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(contact * 1000),
      icao24: (s[0] ?? '').toString(),
    );
  }

  /// The plane's actual track so far (OpenSky experimental endpoint); empty if unavailable.
  static Future<List<(double, double)>> path(String icao24) async {
    if (icao24.isEmpty) return const [];
    try {
      final r = await http
          .get(Uri.https(_base, '/api/tracks/all', {'icao24': icao24.toLowerCase(), 'time': '0'}))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return const [];
      final j = jsonDecode(r.body);
      final pts = j is Map ? j['path'] : null;
      if (pts is! List) return const [];
      return [
        for (final p in pts)
          if (p is List && p.length > 2 && p[1] is num && p[2] is num) ((p[1] as num).toDouble(), (p[2] as num).toDouble()),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Great-circle distance in km between a position and an airport.
  static double kmTo(LiveState s, String iata) {
    final a = Airports.get(iata);
    if (a == null) return 0;
    const r = 6371.0;
    double rad(double d) => d * pi / 180;
    final dLat = rad(a.lat - s.lat), dLon = rad(a.lon - s.lon);
    final h = sin(dLat / 2) * sin(dLat / 2) + cos(rad(s.lat)) * cos(rad(a.lat)) * sin(dLon / 2) * sin(dLon / 2);
    return 2 * r * asin(min(1, sqrt(h)));
  }
}
