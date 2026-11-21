import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/airlines.dart';
import '../core/airports.dart';
import '../models/pass.dart';
import '../core/i18n.dart';
import '../services/live_api.dart';
import '../services/status_api.dart';
import 'widgets.dart';

/// Which plane to follow, plus what we already know about the flight.
class LiveTarget {
  const LiveTarget({
    required this.from,
    required this.to,
    this.callsign = '',
    this.icao24 = '',
    this.title = '',
    this.carrier = '',
    this.aircraft = '',
    this.schedDep,
    this.schedArr,
    this.date = '',
  });
  final String date; // "yyyy-MM-dd", to identify the flight

  LiveTarget copyWith({String? from, String? to, String? callsign, String? icao24}) => LiveTarget(
      from: from ?? this.from, to: to ?? this.to, callsign: callsign ?? this.callsign, icao24: icao24 ?? this.icao24,
      title: title, carrier: carrier, aircraft: aircraft, schedDep: schedDep, schedArr: schedArr, date: date);
  final String from;
  final String to;
  final String callsign;
  final String icao24;
  final String title; // flight number, e.g. "W6 3141"
  final String carrier; // IATA airline code
  final String aircraft;
  final String? schedDep; // "HH:mm" local
  final String? schedArr;
}

/// Keeps a plane's position fresh while on screen (OpenSky, every 2 min).
mixin _LivePolling<T extends StatefulWidget> on State<T> {
  LiveTarget get target;
  LiveState? get preview => null;
  AircraftInfo? get previewAircraft => null;

  LiveState? state;
  AircraftInfo? aircraft;
  bool loading = true;
  Timer? _timer;

  void startPolling() {
    if (preview != null) {
      state = preview;
      aircraft = previewAircraft;
      loading = false;
      return;
    }
    _poll();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => _poll());
  }

  // Once found, the plane is followed by transponder (1 credit) and the track is
  // fetched once (4 credits) and then extended on the phone.
  String _icao = '';
  List<(double, double)> _path = const [];
  DateTime? _start;
  bool _pathTried = false;

  /// The target with gaps filled in (real callsign, transponder, missing airport).
  LiveTarget? _eff;
  LiveTarget get eff => _eff ?? target;
  bool _idsTried = false;

  Future<void> _poll() async {
    // Flights from the airport board come without callsign/transponder: ask the status API once.
    if (!_idsTried && target.icao24.isEmpty && target.title.isNotEmpty && StatusApi.enabled) {
      _idsTried = true;
      final ids = await StatusApi.ids(target.title, target.date);
      if (ids != null) {
        _eff = eff.copyWith(
          from: eff.from.isNotEmpty ? null : ids['from'],
          to: eff.to.isNotEmpty ? null : ids['to'],
          callsign: (ids['cs'] ?? '').isNotEmpty ? ids['cs'] : null,
          icao24: (ids['hex'] ?? '').isNotEmpty ? ids['hex'] : null,
        );
      }
    }
    final t = eff;
    final prefix = icaoAirline[t.carrier.toUpperCase()] ?? '';
    var s = await LiveApi.find(
        icao24: _icao.isNotEmpty ? _icao : t.icao24,
        callsign: _icao.isNotEmpty ? '' : t.callsign,
        prefix: _icao.isNotEmpty ? '' : prefix,
        from: t.from,
        to: t.to);
    if (s == null && _icao.isNotEmpty) {
      // Lost by transponder: try once more by callsign / route.
      s = await LiveApi.find(callsign: t.callsign, prefix: prefix, from: t.from, to: t.to);
    }
    if (s != null) {
      _icao = s.icao24;
      if (!_pathTried) {
        _pathTried = true;
        final (p, start) = await LiveApi.path(s.icao24);
        _path = p;
        _start = start;
      }
      if (_path.isNotEmpty) _path = [..._path, (s.lat, s.lon)];
      // Origin still unknown: the airport where the track starts.
      if (eff.from.isEmpty && _path.isNotEmpty) {
        final o = Airports.nearest(_path.first.$1, _path.first.$2);
        if (o != null) _eff = eff.copyWith(from: o.iata);
      }
      s = s.withPath(_path, _start);
      aircraft ??= await LiveApi.aircraft(s.icao24);
    }
    if (!mounted) return;
    setState(() {
      loading = false;
      state = s ?? state;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Compact card for the flight details page: map, progress and key numbers.
class LiveFlightCard extends StatefulWidget {
  const LiveFlightCard({super.key, required this.target, this.preview, this.tiles = true});
  final LiveTarget target;
  final LiveState? preview;
  final bool tiles;
  @override
  State<LiveFlightCard> createState() => _LiveFlightCardState();
}

class _LiveFlightCardState extends State<LiveFlightCard> with _LivePolling<LiveFlightCard> {
  @override
  LiveTarget get target => widget.target;
  @override
  LiveState? get preview => widget.preview;

  @override
  void initState() {
    super.initState();
    startPolling();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => LivePage(target: widget.target, preview: widget.preview, tiles: widget.tiles))),
        child: Column(children: [
          SizedBox(
            height: 190,
            child: IgnorePointer(child: LiveMap(target: eff, state: state, tiles: widget.tiles)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: state == null
                ? _Searching(loading: loading)
                : Column(children: [
                    RouteProgress(target: eff, state: state!),
                    const SizedBox(height: 14),
                    LiveNumbers(target: eff, state: state!),
                  ]),
          ),
        ]),
      ),
    );
  }
}

/// Full screen map with a details panel, like the big flight trackers (also opened from the airport board).
class LivePage extends StatefulWidget {
  const LivePage({super.key, required this.target, this.preview, this.previewAircraft, this.tiles = true});
  final LiveTarget target;
  final LiveState? preview;
  final AircraftInfo? previewAircraft;
  final bool tiles;
  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> with _LivePolling<LivePage> {
  @override
  LiveTarget get target => widget.target;
  @override
  LiveState? get preview => widget.preview;
  @override
  AircraftInfo? get previewAircraft => widget.previewAircraft;

  @override
  void initState() {
    super.initState();
    startPolling();
  }

  @override
  Widget build(BuildContext context) {
    final t = eff;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(titleSpacing: 0, title: _title(context, t)),
      body: Column(children: [
        Expanded(child: LiveMap(target: t, state: state, tiles: widget.tiles, interactive: true)),
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: state == null ? _Searching(loading: loading) : _panel(context, t, state!),
            ),
          ),
        ),
      ]),
    );
  }

  /// [logo] FR 7603 / Ryanair · RYR59BU · B738
  Widget _title(BuildContext context, LiveTarget t) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final carrier = t.carrier.isNotEmpty ? t.carrier : t.title.split(' ').first;
    final sub = [
      Airlines.name(carrier),
      if (state?.callsign.isNotEmpty == true) state!.callsign,
      if (aircraft?.typecode.isNotEmpty == true) aircraft!.typecode,
    ].join(' · ');
    return Row(children: [
      AirlineBadge(carrier, size: 36),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(t.title.isEmpty ? '${t.from} – ${t.to}' : t.title,
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
    ]);
  }

  Widget _panel(BuildContext context, LiveTarget t, LiveState s) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final model = aircraft?.model.isNotEmpty == true ? aircraft!.model : t.aircraft;
    final reg = aircraft?.registration ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      RouteProgress(target: t, state: s, large: true),
      const SizedBox(height: 18),
      LiveNumbers(target: t, state: s, withVertical: true),
      if (model.isNotEmpty || reg.isNotEmpty) ...[
        Divider(height: 28, color: cs.outlineVariant.withValues(alpha: 0.6)),
        Row(children: [
          Expanded(
            child: Text(model.isEmpty ? '—' : model,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
          ),
          if (reg.isNotEmpty) ...[
            Text(tr('ÎNMATR. ', 'REG '), style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant, letterSpacing: 0.8)),
            Text(reg, style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ]),
      ],
    ]);
  }
}

class _Searching extends StatelessWidget {
  const _Searching({required this.loading});
  final bool loading;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      if (loading)
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
      else
        Icon(Icons.flight, size: 18, color: cs.onSurfaceVariant),
      const SizedBox(width: 10),
      Text(loading ? tr('Caut avionul…', 'Looking for the plane…') : tr('Avionul nu e în aer acum', 'The plane is not airborne now'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
    ]);
  }
}

/// Minutes to landing from distance left and ground speed (+ a few for the approach).
int? minutesToGo(LiveTarget t, LiveState s) {
  if (s.onGround || s.speedKmh < 150) return null;
  return (LiveApi.kmTo(s, t.to) / s.speedKmh * 60 + 8).round();
}

/// CLJ ———✈——— LTN with cities, departed / landing times.
class RouteProgress extends StatelessWidget {
  const RouteProgress({super.key, required this.target, required this.state, this.large = false});
  final LiveTarget target;
  final LiveState state;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final total = target.from.isEmpty ? 0.0 : Airports.distanceKm(target.from, target.to);
    final left = LiveApi.kmTo(state, target.to);
    final frac = total <= 0 ? 0.0 : (1 - left / total).clamp(0.0, 1.0);
    final mins = minutesToGo(target, state);
    final eta = mins == null ? null : hm(Airports.nowAt(target.to).add(Duration(minutes: mins)));
    final since = state.departedAt == null ? null : DateTime.now().difference(state.departedAt!);
    final code = (large ? tt.headlineMedium : tt.titleLarge)?.copyWith(fontWeight: FontWeight.w800);
    final sub = tt.bodySmall?.copyWith(color: cs.onSurfaceVariant);

    Widget end(String iata, String? sched, CrossAxisAlignment a) => Column(crossAxisAlignment: a, children: [
          Text(iata.isEmpty ? '—' : iata, style: code),
          Text(Airports.city(iata), maxLines: 1, overflow: TextOverflow.ellipsis, style: sub),
          if (sched != null) Text(sched, style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
        ]);

    return Column(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 92, child: end(target.from, target.schedDep, CrossAxisAlignment.start)),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: large ? 14 : 10),
            child: LayoutBuilder(builder: (_, c) {
              const icon = 22.0;
              final x = (c.maxWidth - icon) * frac;
              return SizedBox(
                height: icon,
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned(left: 0, right: 0, top: icon / 2 - 1.5,
                      child: Container(height: 3, decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)))),
                  Positioned(left: 0, top: icon / 2 - 1.5,
                      child: Container(width: x + icon / 2, height: 3, decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(2)))),
                  Positioned(left: x, top: 0, child: Transform.rotate(angle: pi / 2, child: Icon(Icons.flight, size: icon, color: cs.primary))),
                ]),
              );
            }),
          ),
        ),
        SizedBox(width: 92, child: end(target.to, target.schedArr, CrossAxisAlignment.end)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: Text(
            since == null ? '' : tr('Decolat acum ${durationText(since)}', 'Departed ${durationText(since)} ago'),
            style: sub,
          ),
        ),
        if (eta != null)
          Text.rich(TextSpan(children: [
            TextSpan(text: tr('Aterizează ~', 'Lands ~'), style: sub),
            TextSpan(text: eta, style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.primary)),
            TextSpan(text: tr(' · în ${durationText(Duration(minutes: mins!))}', ' · in ${durationText(Duration(minutes: mins!))}'), style: sub),
          ])),
      ]),
    ]);
  }
}

class LiveNumbers extends StatelessWidget {
  const LiveNumbers({super.key, required this.target, required this.state, this.withVertical = false});
  final LiveTarget target;
  final LiveState state;
  final bool withVertical;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final vr = (s.verticalRate * 60).round(); // m/min
    final vText = vr.abs() < 60 ? tr('constant', 'level') : '${vr > 0 ? '+' : '−'}${km(vr.abs())} m/min';
    return CellRow([
      (tr('Altitudine', 'Altitude'), s.onGround ? tr('la sol', 'ground') : '${km(s.altitudeM)} m'),
      (tr('Viteză', 'Speed'), '${s.speedKmh.round()} km/h'),
      if (withVertical) (tr('Vertical', 'Vertical'), vText),
      (tr('Mai are', 'To go'), '${km(LiveApi.kmTo(s, target.to))} km'),
    ], big: false);
  }
}

class LiveMap extends StatelessWidget {
  const LiveMap({super.key, required this.target, this.state, this.tiles = true, this.interactive = false});
  final LiveTarget target;
  final LiveState? state;
  final bool tiles;
  final bool interactive;

  /// Points along the great circle, so long routes curve like on real maps.
  static List<LatLng> greatCircle(LatLng a, LatLng b, {int n = 64}) {
    double rad(double d) => d * pi / 180;
    double deg(double r) => r * 180 / pi;
    final la1 = rad(a.latitude), lo1 = rad(a.longitude), la2 = rad(b.latitude), lo2 = rad(b.longitude);
    final d = 2 * asin(sqrt(pow(sin((la2 - la1) / 2), 2) + cos(la1) * cos(la2) * pow(sin((lo2 - lo1) / 2), 2)));
    if (d == 0) return [a, b];
    return [
      for (var i = 0; i <= n; i++)
        () {
          final f = i / n;
          final x1 = sin((1 - f) * d) / sin(d), x2 = sin(f * d) / sin(d);
          final x = x1 * cos(la1) * cos(lo1) + x2 * cos(la2) * cos(lo2);
          final y = x1 * cos(la1) * sin(lo1) + x2 * cos(la2) * sin(lo2);
          final z = x1 * sin(la1) + x2 * sin(la2);
          return LatLng(deg(atan2(z, sqrt(x * x + y * y))), deg(atan2(y, x)));
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final a = Airports.get(target.from), b = Airports.get(target.to);
    final s = state;
    final plane = s == null ? null : LatLng(s.lat, s.lon);
    if (a == null && b == null && plane == null) {
      return Container(color: dark ? const Color(0xFF1B1E24) : const Color(0xFFE8EDF2));
    }
    // A missing airport is replaced by the plane (or the other airport) so the map still draws.
    final pa = a != null ? LatLng(a.lat, a.lon) : (s?.path.isNotEmpty == true ? LatLng(s!.path.first.$1, s.path.first.$2) : (plane ?? LatLng(b!.lat, b.lon)));
    final pb = b != null ? LatLng(b.lat, b.lon) : (plane ?? pa);
    // Flown part (solid): the real track if known, else origin -> plane.
    // Remaining part (dashed): plane -> destination. The plane always sits on the line.
    final flown = plane == null
        ? <LatLng>[]
        : (s!.path.length > 1 ? [for (final p in s.path) LatLng(p.$1, p.$2), plane] : greatCircle(pa, plane, n: 32));
    final remaining = plane == null ? greatCircle(pa, pb) : greatCircle(plane, pb, n: 32);
    final bounds = LatLngBounds.fromPoints([pa, pb, if (plane != null) plane, ...flown]);

    Widget dot(String code) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.primary, width: 1.5)),
          child: Text(code, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: cs.onSurface)),
        );

    // Re-fit to the whole route whenever the map size changes or the plane first appears.
    return LayoutBuilder(builder: (context, c) => FlutterMap(
      key: ValueKey('${c.maxWidth.round()}x${c.maxHeight.round()}-${plane != null}-${flown.length > 2}'),
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.fromLTRB(40, 40, 40, 40)),
        backgroundColor: dark ? const Color(0xFF1B1E24) : const Color(0xFFE8EDF2),
        interactionOptions: InteractionOptions(
            flags: interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none),
      ),
      children: [
        if (tiles)
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'ro.noraz.nflight',
            tileBuilder: dark ? darkModeTileBuilder : null,
          ),
        PolylineLayer(polylines: [
          Polyline(
            points: remaining,
            strokeWidth: 2.5,
            color: cs.primary.withValues(alpha: 0.55),
            pattern: StrokePattern.dashed(segments: const [8, 7]),
          ),
          if (flown.length > 1) Polyline(points: flown, strokeWidth: 3.5, color: cs.primary),
        ]),
        MarkerLayer(markers: [
          if (a != null) Marker(point: pa, width: 44, height: 22, child: dot(target.from)),
          if (b != null) Marker(point: pb, width: 44, height: 22, child: dot(target.to)),
          if (plane != null)
            Marker(
              point: plane,
              width: 40,
              height: 40,
              child: Transform.rotate(
                angle: s!.track * pi / 180,
                child: Icon(Icons.flight, size: 34, color: cs.primary,
                    shadows: [Shadow(color: cs.surface, blurRadius: 6)]),
              ),
            ),
        ]),
        if (tiles)
          RichAttributionWidget(
            showFlutterMapAttribution: false,
            attributions: [TextSourceAttribution('OpenStreetMap contributors')],
          ),
      ],
    ));
  }
}
