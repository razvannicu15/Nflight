import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;

class Airport {
  const Airport(this.iata, this.icao, this.name, this.city, this.country, this.lat, this.lon, this.tz);
  final String iata;
  final String icao;
  final String name;
  final String city;
  final String country;
  final double lat;
  final double lon;
  final String tz;

  String get label => city.isNotEmpty ? city : name;
}

class Airports {
  static final Map<String, Airport> _map = {};
  static bool get loaded => _map.isNotEmpty;

  static Future<void> load() async {
    if (loaded) return;
    final data = await rootBundle.load('assets/airports.tsv.gz');
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final lines = utf8.decode(gzip.decode(bytes)).split('\n');
    for (final l in lines) {
      final p = l.split('\t');
      if (p.length < 8) continue;
      _map[p[0]] = Airport(p[0], p[1], p[2], p[3], p[4], double.tryParse(p[5]) ?? 0,
          double.tryParse(p[6]) ?? 0, p[7]);
    }
  }

  static Airport? get(String iata) => _map[iata.toUpperCase()];

  static Map<String, Airport>? _byIcao;
  static Airport? byIcao(String icao) {
    _byIcao ??= {for (final a in _map.values) if (a.icao.isNotEmpty) a.icao.toUpperCase(): a};
    return _byIcao![icao.toUpperCase()];
  }

  /// Closest airport to a point, within [maxKm].
  static Airport? nearest(double lat, double lon, {double maxKm = 30}) {
    Airport? best;
    var bestD = maxKm;
    for (final a in _map.values) {
      if ((a.lat - lat).abs() > 1 || (a.lon - lon).abs() > 1.5) continue;
      final d = _km(lat, lon, a.lat, a.lon);
      if (d < bestD) {
        bestD = d;
        best = a;
      }
    }
    return best;
  }

  static double _km(double la1, double lo1, double la2, double lo2) {
    const r = 6371.0;
    double rad(double d) => d * pi / 180;
    final dLat = rad(la2 - la1), dLon = rad(lo2 - lo1);
    final h = sin(dLat / 2) * sin(dLat / 2) + cos(rad(la1)) * cos(rad(la2)) * sin(dLon / 2) * sin(dLon / 2);
    return 2 * r * asin(min(1, sqrt(h)));
  }

  static String city(String iata) => get(iata)?.label ?? iata;

  static Iterable<Airport> search(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return const [];
    return _map.values.where((a) =>
        a.iata.toLowerCase() == s ||
        a.city.toLowerCase().startsWith(s) ||
        a.name.toLowerCase().contains(s));
  }

  /// Great-circle distance in km.
  static double distanceKm(String a, String b) {
    final x = get(a), y = get(b);
    if (x == null || y == null) return 0;
    const r = 6371.0;
    double rad(double d) => d * pi / 180;
    final dLat = rad(y.lat - x.lat), dLon = rad(y.lon - x.lon);
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(rad(x.lat)) * cos(rad(y.lat)) * sin(dLon / 2) * sin(dLon / 2);
    return 2 * r * asin(min(1, sqrt(h)));
  }

  /// Converts a wall-clock time at [iata] to an absolute instant.
  static DateTime toInstant(String iata, DateTime wall) {
    final loc = location(iata);
    if (loc == null) return wall;
    return tz.TZDateTime(loc, wall.year, wall.month, wall.day, wall.hour, wall.minute);
  }

  static tz.Location? location(String iata) {
    final name = get(iata)?.tz ?? '';
    if (name.isEmpty) return null;
    try {
      return tz.getLocation(name);
    } catch (_) {
      return null;
    }
  }

  /// Current local time at the airport.
  static DateTime nowAt(String iata) {
    final loc = location(iata);
    return loc == null ? DateTime.now() : tz.TZDateTime.now(loc);
  }
}

/// Country flag emoji from ISO 3166 alpha-2.
String flag(String cc) {
  if (cc.length != 2) return '';
  final u = cc.toUpperCase();
  return String.fromCharCodes([0x1F1E6 + u.codeUnitAt(0) - 65, 0x1F1E6 + u.codeUnitAt(1) - 65]);
}
