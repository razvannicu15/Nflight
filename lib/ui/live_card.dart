import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/airports.dart';
import '../core/i18n.dart';
import '../services/live_api.dart';
import 'widgets.dart';

/// Which plane to follow.
class LiveTarget {
  const LiveTarget({required this.from, required this.to, this.callsign = '', this.icao24 = '', this.title = ''});
  final String from;
  final String to;
  final String callsign;
  final String icao24;
  final String title;
}

/// Keeps a plane's position fresh while on screen (OpenSky, every 2 min).
mixin _LivePolling<T extends StatefulWidget> on State<T> {
  LiveTarget get target;
  LiveState? get preview => null;

  LiveState? state;
  bool loading = true;
  Timer? _timer;

  void startPolling() {
    if (preview != null) {
      state = preview;
      loading = false;
      return;
    }
    _poll();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => _poll());
  }

  Future<void> _poll() async {
    var s = await LiveApi.find(
        icao24: target.icao24, callsign: target.callsign, from: target.from, to: target.to);
    if (s != null) {
      final p = await LiveApi.path(s.icao24);
      if (p.length > 1) s = s.withPath(p);
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

/// Map with the route and the plane, plus altitude / speed / distance left.
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
            height: 200,
            child: IgnorePointer(child: LiveMap(target: widget.target, state: state, tiles: widget.tiles)),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 16), child: LiveStats(target: widget.target, state: state, loading: loading)),
        ]),
      ),
    );
  }
}

/// Full screen, interactive map (also used from the airport board).
class LivePage extends StatefulWidget {
  const LivePage({super.key, required this.target, this.preview, this.tiles = true});
  final LiveTarget target;
  final LiveState? preview;
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
  void initState() {
    super.initState();
    startPolling();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.target;
    return Scaffold(
      appBar: AppBar(title: Text(t.title.isEmpty ? '${t.from} – ${t.to}' : t.title)),
      body: Column(children: [
        Expanded(child: LiveMap(target: t, state: state, tiles: widget.tiles, interactive: true)),
        SafeArea(
          top: false,
          child: Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 16), child: LiveStats(target: t, state: state, loading: loading)),
        ),
      ]),
    );
  }
}

class LiveStats extends StatelessWidget {
  const LiveStats({super.key, required this.target, required this.state, required this.loading});
  final LiveTarget target;
  final LiveState? state;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final s = state;
    if (s == null) {
      return Row(children: [
        if (loading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
        else Icon(Icons.flight, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 10),
        Text(loading ? tr('Caut avionul…', 'Looking for the plane…') : tr('Avionul nu e în aer acum', 'The plane is not airborne now'),
            style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
      ]);
    }
    final left = LiveApi.kmTo(s, target.to);
    return CellRow([
      (tr('Altitudine', 'Altitude'), s.onGround ? tr('la sol', 'ground') : '${km(s.altitudeM)} m'),
      (tr('Viteză', 'Speed'), '${s.speedKmh.round()} km/h'),
      (tr('Mai are', 'To go'), '${km(left)} km'),
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
    if (a == null || b == null) return const SizedBox.shrink();
    final pa = LatLng(a.lat, a.lon), pb = LatLng(b.lat, b.lon);
    final s = state;
    final plane = s == null ? null : LatLng(s.lat, s.lon);
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

    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(36)),
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
          Marker(point: pa, width: 44, height: 22, child: dot(target.from)),
          Marker(point: pb, width: 44, height: 22, child: dot(target.to)),
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
    );
  }
}
