import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/pass.dart';
import 'notifier.dart';
import 'store.dart';

/// Live flight status through AeroDataBox (RapidAPI). The user brings their
/// own free key in Settings; without a key nothing is requested.
class StatusApi {
  static const host = 'aerodatabox.p.rapidapi.com';

  static bool get enabled => store.apiKey.trim().isNotEmpty;

  /// Updates [p] in place. Returns an error message, or null on success.
  static Future<String?> refresh(FlightPass p, {bool notify = false}) async {
    if (!enabled) return 'Adaugă cheia API în Setări pentru status live.';
    final number = '${p.carrier}${p.flightNumber}';
    final uri = Uri.https(host, '/flights/number/$number/${p.date}',
        {'withAircraftImage': 'false', 'withLocation': 'false'});
    try {
      final r = await http.get(uri, headers: {
        'X-RapidAPI-Key': store.apiKey.trim(),
        'X-RapidAPI-Host': host,
      }).timeout(const Duration(seconds: 20));
      if (r.statusCode == 204 || r.body.trim().isEmpty) return 'Zborul nu a fost găsit încă.';
      if (r.statusCode == 401 || r.statusCode == 403) return 'Cheie API invalidă.';
      if (r.statusCode == 429) return 'Limita lunară a cheii API a fost atinsă.';
      if (r.statusCode != 200) return 'Eroare server (${r.statusCode}).';
      final list = jsonDecode(r.body);
      if (list is! List || list.isEmpty) return 'Zborul nu a fost găsit încă.';
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
      if (notify && before != after) {
        await Notifier.showNow(p, '${p.flightCode}: ${statusLabels[p.status]}', changeText(p));
      }
      store.upsert(p);
      await Notifier.schedule(p);
      return null;
    } catch (e) {
      return 'Fără conexiune la serviciul de status.';
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

    final sched = _utc(dep['scheduledTime']);
    final best = _utc(dep['runwayTime']) ?? _utc(dep['revisedTime']);
    p.delayMinutes = (sched != null && best != null) ? best.difference(sched).inMinutes.clamp(0, 6000) : 0;

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
        if (p.delayMinutes >= 5) 'Întârziere ${p.delayMinutes} min · pleacă la ${Notifier.hmOf(p)}',
        if (p.gate.isNotEmpty) 'Poarta ${p.gate}',
      ].join(' · ');

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
