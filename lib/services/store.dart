import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/airports.dart';
import '../core/i18n.dart';
import '../models/pass.dart';
import 'quota.dart';

/// All app data: passes + settings, kept in one JSON file on the phone.
class Store extends ChangeNotifier {
  final List<FlightPass> passes = [];

  ThemeMode themeMode = ThemeMode.system;

  /// 'system' | 'ro' | 'en'
  String language = 'system';

  /// Airport tab: saved airports (chips) and the one shown.
  List<String> boardAirports = ['CLJ'];

  /// Free-allowance status per data source (see quota.dart).
  final Map<String, QuotaInfo> quotas = {};
  String boardAirport = 'CLJ';
  String apiKey = '';
  bool remind24h = true;
  bool remind3h = true;
  bool remindBoarding = true;
  bool autoArchive = true;

  File? _file;

  Future<void> load() async {
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/nflight.json');
    if (!await _file!.exists()) {
      setLanguage(language);
      return;
    }
    try {
      final j = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
      passes
        ..clear()
        ..addAll(((j['passes'] as List?) ?? [])
            .map((e) => FlightPass.fromJson(Map<String, dynamic>.from(e as Map))));
      final s = Map<String, dynamic>.from((j['settings'] as Map?) ?? {});
      themeMode = ThemeMode.values.firstWhere((m) => m.name == s['theme'],
          orElse: () => ThemeMode.system);
      apiKey = s['apiKey'] ?? '';
      language = s['lang'] ?? 'system';
      quotas
        ..clear()
        ..addAll({
          for (final e in Map<String, dynamic>.from((s['quotas'] as Map?) ?? {}).entries)
            e.key: QuotaInfo.fromJson(Map<String, dynamic>.from(e.value as Map)),
        });
      boardAirports = ((s['boardAirports'] as List?) ?? ['CLJ']).map((e) => e.toString()).toList();
      boardAirport = s['boardAirport'] ?? (boardAirports.isEmpty ? 'CLJ' : boardAirports.first);
      remind24h = s['r24'] ?? true;
      remind3h = s['r3'] ?? true;
      remindBoarding = s['rb'] ?? true;
      autoArchive = s['autoArchive'] ?? true;
    } catch (_) {
      // Corrupt file: keep a copy instead of losing it.
      await _file!.copy('${_file!.path}.bak');
    }
    setLanguage(language);
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'passes': passes.map((p) => p.toJson()).toList(),
        'settings': {
          'theme': themeMode.name,
          'apiKey': apiKey,
          'lang': language,
          'boardAirports': boardAirports,
          'quotas': {for (final e in quotas.entries) e.key: e.value.toJson()},
          'boardAirport': boardAirport,
          'r24': remind24h,
          'r3': remind3h,
          'rb': remindBoarding,
          'autoArchive': autoArchive,
        },
      };

  Future<void> save() async {
    setLanguage(language);
    notifyListeners();
    final f = _file;
    if (f == null) return;
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(toJson()));
    await tmp.rename(f.path);
  }

  /// Adds or replaces (same flight + passenger). Returns the stored pass.
  FlightPass upsert(FlightPass p) {
    final i = passes.indexWhere((x) => x.id == p.id || x.sameAs(p));
    if (i >= 0) {
      final old = passes[i];
      // Keep status info we already fetched.
      if (p.gate.isEmpty) p.gate = old.gate;
      if (p.terminal.isEmpty) p.terminal = old.terminal;
      p.departure ??= old.departure;
      p.arrival ??= old.arrival;
      passes[i] = p;
    } else {
      passes.add(p);
    }
    save();
    return p;
  }

  void remove(FlightPass p) {
    passes.removeWhere((x) => x.id == p.id);
    save();
  }

  FlightPass? byId(String id) {
    for (final p in passes) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Absolute departure instant (airport time zone applied).
  static DateTime departureOf(FlightPass p) => Airports.toInstant(p.from, p.departureWall);

  /// A flight counts as done a few hours after its departure.
  static bool isPast(FlightPass p) =>
      departureOf(p).add(Duration(hours: 6 + p.delayMinutes ~/ 60)).isBefore(DateTime.now());

  List<FlightPass> get upcoming {
    final l = passes.where((p) => !p.archived && !(autoArchive && isPast(p))).toList()
      ..sort((a, b) => departureOf(a).compareTo(departureOf(b)));
    return _onePerFlight(l);
  }

  List<FlightPass> get history {
    final l = passes.where((p) => p.archived || (autoArchive && isPast(p))).toList()
      ..sort((a, b) => departureOf(b).compareTo(departureOf(a)));
    return _onePerFlight(l);
  }

  /// Family on one booking shows as one flight (first pass added leads).
  static List<FlightPass> _onePerFlight(List<FlightPass> l) {
    final seen = <String>{};
    final byAge = [...l]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final keep = <String>{};
    for (final p in byAge) {
      final k = '${p.carrier}${p.flightNumber}${p.date}${p.from}${p.pnr}';
      if (p.pnr.isEmpty || seen.add(k)) keep.add(p.id);
    }
    return l.where((p) => keep.contains(p.id)).toList();
  }

  FlightPass? get next {
    final u = upcoming;
    return u.isEmpty ? null : u.first;
  }

  /// Passes on the same booking reference and day (family / group).
  List<FlightPass> companions(FlightPass p) => passes
      .where((x) => x.id != p.id && x.pnr.isNotEmpty && x.pnr == p.pnr && x.date == p.date &&
          x.flightNumber == p.flightNumber)
      .toList();

  String exportJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  int importJson(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    var n = 0;
    for (final e in (j['passes'] as List? ?? [])) {
      final p = FlightPass.fromJson(Map<String, dynamic>.from(e as Map));
      if (!passes.any((x) => x.id == p.id || x.sameAs(p))) {
        passes.add(p);
        n++;
      }
    }
    save();
    return n;
  }
}

final store = Store();
