import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/pass.dart';
import 'notifier.dart';
import 'quota.dart';
import 'store.dart';
import '../core/airports.dart';
import '../core/i18n.dart';

/// Live flight status through AeroDataBox (RapidAPI). The user brings their
/// own free key in Settings; without a key nothing is requested.
class StatusApi {
  static const host = 'aerodatabox.p.rapidapi.com';

  /// Family build key, injected by CI from the RAPIDAPI_KEY secret (never in the repo).
  static const builtInKey = String.fromEnvironment('RAPIDAPI_KEY');

  static String get key => builtInKey;
  static bool get enabled => key.isNotEmpty;

  /// Updates [p] in place. Returns an error message, or null on success.
  static Future<String?> refresh(FlightPass p, {bool notify = false}) async {
    if (!enabled) return tr('Adaugă cheia API în Setări pentru status live.', 'Add an API key in Settings for live status.');
    final number = '${p.carrier}${p.flightNumber}';
    final uri = Uri.https(host, '/flights/number/$number/${p.date}',
        {'withAircraftImage': 'false', 'withLocation': 'false'});
    try {
      final r = await http.get(uri, headers: {
        'X-RapidAPI-Key': key,
        'X-RapidAPI-Host': host,
      }).timeout(const Duration(seconds: 20));
      Quota.fromHeaders(Quota.aerodatabox, r.headers, status: r.statusCode);
      if (r.statusCode == 204 || r.body.trim().isEmpty) {
        _markTried(p);
        return tr('Zborul nu a fost găsit.', 'Flight not found.');
      }
      if (r.statusCode == 401 || r.statusCode == 403) return tr('Cheie API invalidă.', 'Invalid API key.');
      if (r.statusCode == 429) return tr('Limita lunară a cheii API a fost atinsă.', 'Monthly API key limit reached.');
      if (r.statusCode != 200) return tr('Eroare server (${r.statusCode}).', 'Server error (${r.statusCode}).');
      final list = jsonDecode(r.body);
      if (list is! List || list.isEmpty) {
        _markTried(p);
        return tr('Zborul nu a fost găsit.', 'Flight not found.');
      }
      Map<String, dynamic> f = Map<String, dynamic>.from(list.first as Map);
      for (final e in list) {
        final m = Map<String, dynamic>.from(e as Map);
        if (_iata(m['departure']) == p.from) {
          f = m;
          break;
        }
      }
      final before = (p.status, p.delayMinutes, p.gate, p.departure);
      apply(p, f);
      p.statusCheckedAt = DateTime.now();
      final after = (p.status, p.delayMinutes, p.gate, p.departure);
      // Same flight, same booking: the family's passes get the same live info.
      for (final c in store.companions(p)) {
        c
          ..status = p.status
          ..delayMinutes = p.delayMinutes
          ..arrivalDelayMinutes = p.arrivalDelayMinutes
          ..gate = p.gate
          ..terminal = p.terminal
          ..departure = p.departure
          ..arrival = p.arrival
          ..aircraft = p.aircraft
          ..callsign = p.callsign
          ..icao24 = p.icao24
          ..statusCheckedAt = p.statusCheckedAt;
      }
      if (notify && before != after) {
        await Notifier.showNow(p, '${p.flightCode}: ${statusLabel(p.status)}', changeText(p));
      }
      store.upsert(p);
      await Notifier.schedule(p);
      return null;
    } catch (e) {
      return tr('Fără conexiune la serviciul de status.', 'Cannot reach the status service.');
    }
  }

  static void _markTried(FlightPass p) {
    if (!Store.isPast(p)) return;
    p.statusCheckedAt = DateTime.now();
    store.save();
  }

  /// Callsign, transponder hex and airports of a flight (for the live map). One request.
  static Future<Map<String, String>?> ids(String number, String date) async {
    if (!enabled || number.isEmpty || date.isEmpty) return null;
    try {
      final r = await http.get(Uri.https(host, '/flights/number/${number.replaceAll(' ', '')}/$date',
          {'withAircraftImage': 'false', 'withLocation': 'false'}), headers: {
        'X-RapidAPI-Key': key,
        'X-RapidAPI-Host': host,
      }).timeout(const Duration(seconds: 20));
      Quota.fromHeaders(Quota.aerodatabox, r.headers, status: r.statusCode);
      if (r.statusCode != 200) return null;
      final list = jsonDecode(r.body);
      if (list is! List || list.isEmpty) return null;
      // Prefer the leg that is in the air now.
      Map f = list.first as Map;
      for (final e in list) {
        final s = (e is Map ? e['status'] : '').toString().toLowerCase();
        if (s == 'enroute' || s == 'departed' || s == 'approaching') {
          f = e as Map;
          break;
        }
      }
      final ac = f['aircraft'] is Map ? f['aircraft'] as Map : const {};
      String side(String k) {
        final m = f[k];
        if (m is! Map || m['airport'] is! Map) return '';
        final a = m['airport'] as Map;
        final i = (a['iata'] ?? '').toString();
        return i.isNotEmpty ? i : (Airports.byIcao((a['icao'] ?? '').toString())?.iata ?? '');
      }
      return {
        'cs': (f['callSign'] ?? '').toString().replaceAll(' ', ''),
        'hex': (ac['modeS'] ?? '').toString().toLowerCase(),
        'from': side('departure'),
        'to': side('arrival'),
      };
    } catch (_) {
      return null;
    }
  }

  static String? _iata(dynamic side) {
    if (side is! Map) return null;
    final a = side['airport'];
    return a is Map ? a['iata']?.toString() : null;
  }

  /// "2026-11-21 14:35+02:00" -> "14:35"
  static String? _local(dynamic t) {
    if (t is! Map) return null;
    final s = t['local']?.toString();
    if (s == null || s.length < 16) return null;
    return s.substring(11, 16);
  }

  static DateTime? _utc(dynamic t) {
    if (t is! Map) return null;
    final s = t['utc']?.toString();
    if (s == null) return null;
    return DateTime.tryParse(s.replaceFirst(' ', 'T').replaceFirst('Z', ':00Z')) ??
        DateTime.tryParse(s);
  }

  static void apply(FlightPass p, Map<String, dynamic> f) {
    final dep = Map<String, dynamic>.from((f['departure'] as Map?) ?? {});
    final arr = Map<String, dynamic>.from((f['arrival'] as Map?) ?? {});
    p.departure = _local(dep['scheduledTime']) ?? p.departure;
    p.arrival = _local(arr['scheduledTime']) ?? p.arrival;
    final t = dep['terminal']?.toString() ?? '';
    final g = dep['gate']?.toString() ?? '';
    if (t.isNotEmpty) p.terminal = t;
    if (g.isNotEmpty) p.gate = g;
    final ac = f['aircraft'];
    if (ac is Map && (ac['model'] ?? '').toString().isNotEmpty) p.aircraft = ac['model'].toString();
    if (ac is Map && (ac['modeS'] ?? '').toString().isNotEmpty) p.icao24 = ac['modeS'].toString().toLowerCase();
    final cs = (f['callSign'] ?? '').toString().replaceAll(' ', '');
    if (cs.isNotEmpty) p.callsign = cs;

    final sched = _utc(dep['scheduledTime']);
    final best = _utc(dep['runwayTime']) ?? _utc(dep['revisedTime']);
    p.delayMinutes = (sched != null && best != null) ? best.difference(sched).inMinutes.clamp(0, 6000) : 0;
    final aSched = _utc(arr['scheduledTime']);
    final aBest = _utc(arr['runwayTime']) ?? _utc(arr['revisedTime']);
    p.arrivalDelayMinutes =
        (aSched != null && aBest != null) ? aBest.difference(aSched).inMinutes.clamp(0, 6000) : 0;

    final s = (f['status'] ?? '').toString().toLowerCase();
    p.status = switch (s) {
      'canceled' || 'cancelled' || 'canceleduncertain' => FlightStatus.cancelled,
      'boarding' || 'gateclosed' => FlightStatus.boarding,
      'departed' || 'enroute' || 'approaching' => FlightStatus.departed,
      'arrived' => FlightStatus.landed,
      'diverted' => FlightStatus.diverted,
      'delayed' => FlightStatus.delayed,
      'expected' || 'checkin' || 'unknown' || '' => p.delayMinutes >= 15 ? FlightStatus.delayed : FlightStatus.scheduled,
      _ => p.delayMinutes >= 15 ? FlightStatus.delayed : FlightStatus.scheduled,
    };
  }

  static String changeText(FlightPass p) => [
        if (p.delayMinutes >= 5) tr('Întârziere ${p.delayMinutes} min · pleacă la ${Notifier.hmOf(p)}', 'Delayed ${p.delayMinutes} min · departs ${Notifier.hmOf(p)}'),
        if (p.gate.isNotEmpty) '${tr('Poarta', 'Gate')} ${p.gate}',
      ].join(' · ');

  /// Past flights get one lookup ever (real times, final status, delay).
  /// A few per launch, newest first, so old imports fill in over time.
  static Future<void> backfillPast() async {
    if (!enabled) return;
    final cutoff = DateTime.now().subtract(const Duration(days: 365));
    final todo = store.history
        .where((p) => p.statusCheckedAt == null && p.day.isAfter(cutoff))
        .take(5)
        .toList();
    for (final p in todo) {
      await refresh(p);
    }
  }

  /// Refreshes flights departing in the next 36 hours (saves API calls).
  static Future<void> refreshSoon() async {
    if (!enabled) return;
    final now = DateTime.now();
    for (final p in store.upcoming) {
      final dep = Store.departureOf(p);
      final h = dep.difference(now).inHours;
      if (h > 36 || h < -12) continue;
      final last = p.statusCheckedAt;
      final minGap = h < 4 ? 10 : 60; // minutes
      if (last != null && now.difference(last).inMinutes < minGap) continue;
      await refresh(p, notify: true);
    }
  }
}
