import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../core/airports.dart';
import '../core/i18n.dart';
import 'quota.dart';

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
    this.verticalRate = 0,
    this.callsign = '',
    this.country = '',
    this.departedAt,
  });
  final String icao24;

  /// m/s, positive when climbing.
  final double verticalRate;
  final String callsign;
  final String country; // country of registration
  final DateTime? departedAt;

  /// Flown path so far as (lat, lon) pairs, when OpenSky has it.
  final List<(double, double)> path;

  LiveState withPath(List<(double, double)> p, DateTime? start) => LiveState(
      lat: lat, lon: lon, altitudeM: altitudeM, speedKmh: speedKmh, track: track,
      onGround: onGround, seen: seen, icao24: icao24, path: p, verticalRate: verticalRate,
      callsign: callsign, country: country, departedAt: start ?? departedAt);
  final double lat;
  final double lon;
  final double altitudeM;
  final double speedKmh;
  final double track; // degrees, 0 = north
  final bool onGround;
  final DateTime seen;
}

class AircraftInfo {
  AircraftInfo({this.registration = '', this.model = '', this.typecode = '', this.operator = ''});
  final String registration;
  final String model;
  final String typecode;
  final String operator;
}

class LiveApi {
  static const _base = 'opensky-network.org';

  // Free OpenSky account (OAuth2 client credentials, CI secrets): 4000 credits/day instead of 400.
  static const _clientId = String.fromEnvironment('OPENSKY_CLIENT_ID');
  static const _clientSecret = String.fromEnvironment('OPENSKY_CLIENT_SECRET');
  static bool get authed => _clientId.isNotEmpty && _clientSecret.isNotEmpty;
  static String? _token;
  static DateTime? _tokenExp;

  /// Set when the account login is rejected (wrong client id / secret).
  static String? authError;

  static Future<Map<String, String>> _headers() async {
    if (!authed) return const {};
    if (_token == null || _tokenExp == null || DateTime.now().isAfter(_tokenExp!)) {
      try {
        final r = await http.post(
          Uri.parse('https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token'),
          body: {'grant_type': 'client_credentials', 'client_id': _clientId, 'client_secret': _clientSecret},
        ).timeout(const Duration(seconds: 15));
        final j = jsonDecode(r.body);
        authError = r.statusCode == 200 ? null : 'HTTP ${r.statusCode}';
        if (r.statusCode == 200 && j is Map && j['access_token'] is String) {
          _token = j['access_token'] as String;
          final exp = (j['expires_in'] as num?)?.toInt() ?? 1800;
          _tokenExp = DateTime.now().add(Duration(seconds: exp - 60));
        }
      } catch (_) {
        authError ??= tr('fără conexiune', 'no connection');
      }
    }
    return _token == null ? const {} : {'Authorization': 'Bearer $_token'};
  }

  static void _quota(http.Response r) =>
      Quota.fromHeaders(Quota.opensky, r.headers, status: r.statusCode, defaultLimit: authed ? 4000 : 400);

  /// Finds the plane by transponder hex (exact) or by callsign in the box
  /// spanning both airports. Returns null when it is not airborne/visible.
  static Future<LiveState?> find(
      {String icao24 = '', String callsign = '', String prefix = '', required String from, required String to}) async {
    try {
      if (icao24.isNotEmpty) {
        final s = await _query({'icao24': icao24.toLowerCase()});
        if (s.isNotEmpty) return _state(s.first);
      }
      if (callsign.isEmpty && prefix.isEmpty) return null;
      final a = Airports.get(from) ?? Airports.get(to), b = Airports.get(to) ?? Airports.get(from);
      if (a == null || b == null) return null;
      final pad = a == b ? 6.0 : 3.0;
      final states = await _query({
        'lamin': '${max(-90.0, min(a.lat, b.lat) - pad)}',
        'lamax': '${min(90.0, max(a.lat, b.lat) + pad)}',
        'lomin': '${max(-180.0, min(a.lon, b.lon) - pad)}',
        'lomax': '${min(180.0, max(a.lon, b.lon) + pad)}',
      });
      final want = callsign.toUpperCase();
      for (final s in states) {
        if (want.isNotEmpty && (s[1] ?? '').toString().trim().toUpperCase() == want) return _state(s);
      }
      // Airlines often fly under alphanumeric callsigns (WZZ6DB, RYR59BU): take the plane of that
      // airline that is airborne, close to the route and heading to the destination.
      if (prefix.isEmpty) return null;
      LiveState? best;
      var bestScore = 1e9;
      for (final s in states) {
        final cs = (s[1] ?? '').toString().trim().toUpperCase();
        if (!cs.startsWith(prefix.toUpperCase())) continue;
        final st = _state(s);
        if (st == null || st.onGround) continue;
        final off = a == b ? 0.0 : _offRoute(st.lat, st.lon, a, b);
        final brg = _bearing(st.lat, st.lon, b.lat, b.lon);
        final turn = ((st.track - brg + 540) % 360 - 180).abs();
        if (off > 80 || turn > 60) continue;
        final score = off + turn;
        if (score < bestScore) {
          bestScore = score;
          best = st;
        }
      }
      return best;
    } catch (_) {}
    return null;
  }

  static double _bearing(double la1, double lo1, double la2, double lo2) {
    double rad(double d) => d * pi / 180;
    final y = sin(rad(lo2 - lo1)) * cos(rad(la2));
    final x = cos(rad(la1)) * sin(rad(la2)) - sin(rad(la1)) * cos(rad(la2)) * cos(rad(lo2 - lo1));
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  /// Approximate distance (km) from a point to the great circle between two airports.
  static double _offRoute(double lat, double lon, Airport a, Airport b) {
    const r = 6371.0;
    double rad(double d) => d * pi / 180;
    double dist(double la1, double lo1, double la2, double lo2) {
      final dLat = rad(la2 - la1), dLon = rad(lo2 - lo1);
      final h = sin(dLat / 2) * sin(dLat / 2) + cos(rad(la1)) * cos(rad(la2)) * sin(dLon / 2) * sin(dLon / 2);
      return 2 * asin(min(1, sqrt(h)));
    }
    final d13 = dist(a.lat, a.lon, lat, lon);
    final t13 = rad(_bearing(a.lat, a.lon, lat, lon)), t12 = rad(_bearing(a.lat, a.lon, b.lat, b.lon));
    return (asin(sin(d13) * sin(t13 - t12)) * r).abs();
  }

  static Future<List<List>> _query(Map<String, String> q) async {
    final r = await http.get(Uri.https(_base, '/api/states/all', q), headers: await _headers()).timeout(const Duration(seconds: 15));
    _quota(r);
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
      callsign: (s[1] ?? '').toString().trim(),
      country: (s[2] ?? '').toString(),
      verticalRate: (s[11] as num?)?.toDouble() ?? 0,
    );
  }

  static final Map<String, AircraftInfo?> _aircraft = {};

  /// Registration and type from OpenSky's aircraft database (cached).
  static Future<AircraftInfo?> aircraft(String icao24) async {
    final k = icao24.toLowerCase();
    if (k.isEmpty) return null;
    if (_aircraft.containsKey(k)) return _aircraft[k];
    AircraftInfo? info;
    try {
      final r = await http
          .get(Uri.https(_base, '/api/metadata/aircraft/icao/$k'), headers: await _headers())
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body);
        if (j is Map) {
          String f(String key) => (j[key] ?? '').toString().trim();
          final maker = f('manufacturerName');
          var model = f('model');
          if (model.isNotEmpty && maker.isNotEmpty && !model.toLowerCase().contains(maker.split(' ').first.toLowerCase())) {
            model = '${maker.split(' ').first} $model';
          }
          info = AircraftInfo(registration: f('registration'), model: model, typecode: f('typecode'), operator: f('operator'));
        }
      }
    } catch (_) {}
    _aircraft[k] = info;
    return info;
  }

  /// The plane's actual track so far (OpenSky experimental endpoint); empty if unavailable.
  static Future<(List<(double, double)>, DateTime?)> path(String icao24) async {
    if (icao24.isEmpty) return (const <(double, double)>[], null);
    try {
      final r = await http
          .get(Uri.https(_base, '/api/tracks/all', {'icao24': icao24.toLowerCase(), 'time': '0'}), headers: await _headers())
          .timeout(const Duration(seconds: 15));
      _quota(r);
      if (r.statusCode != 200) return (const <(double, double)>[], null);
      final j = jsonDecode(r.body);
      final pts = j is Map ? j['path'] : null;
      if (pts is! List) return (const <(double, double)>[], null);
      final st = j is Map ? (j['startTime'] as num?)?.toInt() : null;
      return (
        [
          for (final p in pts)
            if (p is List && p.length > 2 && p[1] is num && p[2] is num) ((p[1] as num).toDouble(), (p[2] as num).toDouble()),
        ],
        st == null ? null : DateTime.fromMillisecondsSinceEpoch(st * 1000),
      );
    } catch (_) {
      return (const <(double, double)>[], null);
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
