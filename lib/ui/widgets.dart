import 'package:flutter/material.dart';

import '../core/airlines.dart';
import '../core/airports.dart';
import '../models/pass.dart';
import '../services/store.dart';

const _months = ['ian.', 'feb.', 'mar.', 'apr.', 'mai', 'iun.', 'iul.', 'aug.', 'sept.', 'oct.', 'nov.', 'dec.'];
const _monthsLong = ['ianuarie', 'februarie', 'martie', 'aprilie', 'mai', 'iunie', 'iulie', 'august', 'septembrie', 'octombrie', 'noiembrie', 'decembrie'];
const _days = ['lun.', 'mar.', 'mie.', 'joi', 'vin.', 'sâm.', 'dum.'];
const _daysLong = ['luni', 'marți', 'miercuri', 'joi', 'vineri', 'sâmbătă', 'duminică'];

String shortDate(DateTime d) => '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
String longDate(DateTime d) {
  final y = d.year == DateTime.now().year ? '' : ' ${d.year}';
  return '${_daysLong[d.weekday - 1]}, ${d.day} ${_monthsLong[d.month - 1]}$y';
}

String monthName(int m) => _monthsLong[m - 1];

/// "în 2 zile", "în 3 h 20 min", "a plecat".
String countdown(DateTime target) {
  final d = target.difference(DateTime.now());
  if (d.isNegative) return d.inHours > -6 ? 'a plecat' : 'încheiat';
  if (d.inDays >= 2) return 'în ${d.inDays} zile';
  if (d.inHours >= 24) return 'mâine';
  if (d.inHours >= 1) return 'în ${d.inHours} h ${d.inMinutes % 60} min';
  return 'în ${d.inMinutes} min';
}

String durationText(Duration d) {
  final h = d.inMinutes ~/ 60, m = d.inMinutes % 60;
  return h == 0 ? '$m min' : (m == 0 ? '$h h' : '$h h $m min');
}

String km(num v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// Flight time: from both local times when known, else estimated from distance.
Duration flightDuration(FlightPass p) {
  if (p.departure != null && p.arrival != null) {
    final dep = Airports.toInstant(p.from, p.departureWall);
    final a = p.arrival!.split(':').map(int.parse).toList();
    var arrWall = DateTime(p.day.year, p.day.month, p.day.day, a[0], a[1]);
    var arr = Airports.toInstant(p.to, arrWall);
    if (arr.isBefore(dep)) {
      arrWall = arrWall.add(const Duration(days: 1));
      arr = Airports.toInstant(p.to, arrWall);
    }
    final d = arr.difference(dep);
    if (d.inMinutes > 15 && d.inHours < 20) return d;
  }
  final dist = Airports.distanceKm(p.from, p.to);
  if (dist == 0) return Duration.zero;
  return Duration(minutes: (dist / 800 * 60 + 30).round());
}

class MaxWidth extends StatelessWidget {
  const MaxWidth({super.key, required this.child, this.width = 720});
  final Widget child;
  final double width;
  @override
  Widget build(BuildContext context) => Center(
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: width), child: child));
}

class AirlineBadge extends StatelessWidget {
  const AirlineBadge(this.code, {super.key, this.size = 40});
  final String code;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = Airlines.color(code, cs);
    final fg = ThemeData.estimateBrightnessForColor(c) == Brightness.dark ? Colors.white : Colors.black87;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(size * 0.3)),
      child: Text(code,
          style: TextStyle(
              color: fg, fontWeight: FontWeight.w800, fontSize: size * 0.36, letterSpacing: 0.5)),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.pass, {super.key, this.dense = false});
  final FlightPass pass;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = pass.status;
    if (s == FlightStatus.unknown) return const SizedBox.shrink();
    final (bg, fg) = switch (s) {
      FlightStatus.cancelled || FlightStatus.diverted => (cs.errorContainer, cs.onErrorContainer),
      FlightStatus.delayed => (const Color(0xFFFFE0B2), const Color(0xFF7A3E00)),
      FlightStatus.boarding => (cs.primary, cs.onPrimary),
      FlightStatus.departed || FlightStatus.landed => (cs.secondaryContainer, cs.onSecondaryContainer),
      _ => (const Color(0xFFD5F2DC), const Color(0xFF0D5223)),
    };
    var text = statusLabels[s]!;
    if (s == FlightStatus.delayed && pass.delayMinutes > 0) text += ' ${pass.delayMinutes} min';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: dense ? 11.5 : 12.5)),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
        child: Row(children: [
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Small "label / value" cell used in grids.
class InfoCell extends StatelessWidget {
  const InfoCell(this.label, this.value, {super.key, this.big = false});
  final String label;
  final String value;
  final bool big;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label.toUpperCase(),
          style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant, letterSpacing: 0.8)),
      const SizedBox(height: 2),
      Text(value.isEmpty ? '—' : value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (big ? t.titleLarge : t.titleMedium)?.copyWith(fontWeight: FontWeight.w700)),
    ]);
  }
}

/// Route line "OTP ——✈—— LTN" with cities and times.
class RouteHeader extends StatelessWidget {
  const RouteHeader(this.p, {super.key, this.large = false, this.onColor});
  final FlightPass p;
  final bool large;
  final Color? onColor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final fg = onColor ?? cs.onSurface;
    final sub = onColor?.withValues(alpha: 0.75) ?? cs.onSurfaceVariant;
    final codeStyle = (large ? t.displaySmall : t.headlineSmall)
        ?.copyWith(fontWeight: FontWeight.w800, color: fg, letterSpacing: 1);
    final dur = flightDuration(p);

    Widget side(String code, String? time, CrossAxisAlignment a, {bool delayed = false}) => Expanded(
          child: Column(crossAxisAlignment: a, children: [
            Text(code, style: codeStyle),
            Text(Airports.city(code),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(color: sub)),
            if (time != null) ...[
              const SizedBox(height: 4),
              Text(time,
                  style: t.titleMedium?.copyWith(
                      color: delayed ? const Color(0xFFE65100) : fg, fontWeight: FontWeight.w700)),
            ],
          ]),
        );

    final delayed = p.delayMinutes >= 5 && p.departure != null;
    final depTime = delayed ? hm(p.departureWall.add(Duration(minutes: p.delayMinutes))) : p.departure;

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      side(p.from, depTime, CrossAxisAlignment.start, delayed: delayed),
      Padding(
        padding: EdgeInsets.only(top: large ? 14 : 8),
        child: Column(children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            _dash(sub),
            Icon(Icons.flight, size: large ? 24 : 20, color: fg),
            _dash(sub),
          ]),
          if (dur > Duration.zero)
            Text(durationText(dur), style: t.labelSmall?.copyWith(color: sub)),
        ]),
      ),
      side(p.to, p.arrival, CrossAxisAlignment.end),
    ]);
  }

  Widget _dash(Color c) => Container(
      width: 22, height: 1.5, margin: const EdgeInsets.symmetric(horizontal: 4), color: c.withValues(alpha: 0.5));
}

/// Compact list card for a flight.
class PassTile extends StatelessWidget {
  const PassTile(this.p, {super.key, required this.onTap});
  final FlightPass p;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(children: [
            Row(children: [
              AirlineBadge(p.carrier, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${p.flightCode} · ${Airlines.name(p.carrier)}',
                      style: t.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                  Text(shortDate(p.day), style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
              StatusChip(p, dense: true),
            ]),
            const SizedBox(height: 12),
            RouteHeader(p),
            if (p.passenger.isNotEmpty || p.seat.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(children: [
                Icon(Icons.person_outline, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                    child: Text(p.passenger,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall)),
                if (p.seat.isNotEmpty) ...[
                  Icon(Icons.event_seat_outlined, size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(p.seat, style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Large card for the next flight, with countdown.
class NextFlightCard extends StatelessWidget {
  const NextFlightCard(this.p, {super.key, required this.onTap, required this.onShowCode});
  final FlightPass p;
  final VoidCallback onTap;
  final VoidCallback onShowCode;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final dep = Store.departureOf(p).add(Duration(minutes: p.delayMinutes));
    return Card(
      elevation: 0,
      color: cs.primaryContainer,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('URMĂTORUL ZBOR',
                  style: t.labelMedium?.copyWith(
                      color: cs.onPrimaryContainer, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
              const Spacer(),
              StatusChip(p, dense: true),
            ]),
            const SizedBox(height: 4),
            Text(p.departure == null ? longDate(p.day) : '${countdown(dep)} · ${longDate(p.day)}',
                style: t.bodyMedium?.copyWith(color: cs.onPrimaryContainer)),
            const SizedBox(height: 16),
            RouteHeader(p, large: true, onColor: cs.onPrimaryContainer),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _cell(context, 'Zbor', p.flightCode)),
              Expanded(child: _cell(context, 'Terminal', p.terminal)),
              Expanded(child: _cell(context, 'Poarta', p.gate)),
              Expanded(child: _cell(context, 'Loc', p.seat)),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: p.barcode.isEmpty ? null : onShowCode,
                icon: const Icon(Icons.qr_code_2),
                label: const Text('Arată biletul'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, String l, String v) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(l.toUpperCase(),
          style: t.labelSmall?.copyWith(color: cs.onPrimaryContainer.withValues(alpha: 0.7), letterSpacing: 0.8)),
      Text(v.isEmpty ? '—' : v,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.titleMedium?.copyWith(color: cs.onPrimaryContainer, fontWeight: FontWeight.w800)),
    ]);
  }
}
