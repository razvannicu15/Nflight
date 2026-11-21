import 'dart:io';

import 'package:flutter/material.dart';

import '../core/airlines.dart';
import '../core/airports.dart';
import '../models/pass.dart';
import '../services/logos.dart';
import '../services/store.dart';
import '../core/i18n.dart';

const _months = ['ian.', 'feb.', 'mar.', 'apr.', 'mai', 'iun.', 'iul.', 'aug.', 'sept.', 'oct.', 'nov.', 'dec.'];
const _monthsLong = ['ianuarie', 'februarie', 'martie', 'aprilie', 'mai', 'iunie', 'iulie', 'august', 'septembrie', 'octombrie', 'noiembrie', 'decembrie'];
const _days = ['lun.', 'mar.', 'mie.', 'joi', 'vin.', 'sâm.', 'dum.'];
const _daysLong = ['luni', 'marți', 'miercuri', 'joi', 'vineri', 'sâmbătă', 'duminică'];

const _monthsEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monthsLongEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _daysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _daysLongEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String shortDate(DateTime d) => isEn
    ? '${_daysEn[d.weekday - 1]} ${d.day} ${_monthsEn[d.month - 1]}'
    : '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
String longDate(DateTime d) {
  final y = d.year == DateTime.now().year ? '' : ' ${d.year}';
  return isEn
      ? '${_daysLongEn[d.weekday - 1]}, ${d.day} ${_monthsLongEn[d.month - 1]}$y'
      : '${_daysLong[d.weekday - 1]}, ${d.day} ${_monthsLong[d.month - 1]}$y';
}

String monthName(int m) => isEn ? _monthsLongEn[m - 1] : _monthsLong[m - 1];

/// "în 2 zile", "în 3 h 20 min", "a plecat".
String countdown(DateTime target) {
  final d = target.difference(DateTime.now());
  if (d.isNegative) return d.inHours > -6 ? tr('a plecat', 'departed') : tr('încheiat', 'done');
  if (d.inDays >= 2) return tr('în ${d.inDays} zile', 'in ${d.inDays} days');
  if (d.inHours >= 24) return tr('mâine', 'tomorrow');
  if (d.inHours >= 1) return tr('în ${d.inHours} h ${d.inMinutes % 60} min', 'in ${d.inHours} h ${d.inMinutes % 60} min');
  return tr('în ${d.inMinutes} min', 'in ${d.inMinutes} min');
}

String durationText(Duration d) {
  final h = d.inMinutes ~/ 60, m = d.inMinutes % 60;
  return h == 0 ? '$m min' : (m == 0 ? '$h h' : '$h h $m min');
}

String km(num v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(isEn ? ',' : '.');
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
  Widget build(BuildContext context) => FutureBuilder<File?>(
        future: Logos.get(code),
        builder: (context, snap) {
          final f = snap.data;
          if (f == null) return _badge(context);
          return Container(
            width: size,
            height: size,
            padding: EdgeInsets.all(size * 0.1),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(size * 0.3),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            ),
            child: Image.file(f, fit: BoxFit.contain, errorBuilder: (_, __, ___) => _badge(context)),
          );
        },
      );

  Widget _badge(BuildContext context) {
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
    var text = statusLabel(s);
    if (s == FlightStatus.delayed && pass.delayMinutes > 0) text += ' ${pass.delayMinutes} min';
    if (s == FlightStatus.landed && pass.arrivalDelayMinutes >= 15) text += ' · +${pass.arrivalDelayMinutes} min';
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
  const PassTile(this.p, {super.key, required this.onTap, this.showDate = false, this.others = 0});
  final FlightPass p;
  final VoidCallback onTap;
  final bool showDate;

  /// Other passengers on the same flight and booking.
  final int others;

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
                  Text(Airlines.name(p.carrier), style: t.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                  Text(showDate ? '${p.flightCode} · ${shortDate(p.day)}' : p.flightCode,
                      style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
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
                    child: Text(others > 0 ? '${p.passenger} +$others' : p.passenger,
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
  const NextFlightCard(this.p, {super.key, required this.onTap, required this.onShowCode, this.others = 0});
  final FlightPass p;
  final int others;
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(tr('URMĂTORUL ZBOR', 'NEXT FLIGHT'),
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
          ]),
          ),
          TicketDivider(color: cs.onPrimaryContainer),
          Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(children: [
            CellRow([
              (tr('Zbor', 'Flight'), p.flightCode),
              ('Terminal', p.terminal),
              (tr('Poarta', 'Gate'), p.gate),
              (tr('Loc', 'Seat'), p.seat),
            ], color: cs.onPrimaryContainer, big: false),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: p.barcode.isEmpty ? null : onShowCode,
                icon: const Icon(Icons.qr_code_2),
                label: Text(others == 0
                    ? tr('Arată biletul', 'Show pass')
                    : tr('Arată biletele (${others + 1})', 'Show passes (${others + 1})')),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ),
          ]),
          ),
        ]),
      ),
    );
  }
}

/// One row of cells separated by hairlines: "TERMINAL | POARTA | LOC".
class CellRow extends StatelessWidget {
  const CellRow(this.cells, {super.key, this.color, this.big = true});
  final List<(String, String)> cells;
  final Color? color;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final fg = color ?? cs.onSurface;
    final line = fg.withValues(alpha: 0.14);
    final children = <Widget>[];
    for (final (i, c) in cells.indexed) {
      if (i > 0) children.add(Container(width: 1, color: line));
      children.add(Expanded(
        child: Padding(
          padding: EdgeInsets.only(left: i == 0 ? 0 : 12, right: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(c.$1.toUpperCase(),
                  maxLines: 1,
                  style: t.labelSmall?.copyWith(color: fg.withValues(alpha: 0.6), letterSpacing: 0.6)),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(c.$2.isEmpty ? '—' : c.$2,
                  maxLines: 1,
                  style: (big ? t.titleLarge : t.titleMedium)?.copyWith(
                      color: fg, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ]),
        ),
      ));
    }
    return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children));
  }
}

/// Label / value table with hairline separators. Empty values are skipped.
class InfoTable extends StatelessWidget {
  const InfoTable(this.rows, {super.key});
  final List<(String, String, String?)> rows;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final visible = rows.where((r) => r.$2.trim().isNotEmpty).toList();
    final children = <Widget>[];
    for (final (i, r) in visible.indexed) {
      if (i > 0) children.add(Divider(height: 1, thickness: 0.6, color: cs.outlineVariant.withValues(alpha: 0.6)));
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 116,
            child: Text(r.$1, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(r.$2,
                  textAlign: TextAlign.end,
                  style: t.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
              if (r.$3 != null && r.$3!.isNotEmpty)
                Text(r.$3!, textAlign: TextAlign.end, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
        ]),
      ));
    }
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Column(children: children)),
    );
  }
}

/// Perforated tear line with side notches, like a paper boarding pass.
/// Place it directly inside a card that clips its children.
class TicketDivider extends StatelessWidget {
  const TicketDivider({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final line = (color ?? Theme.of(context).colorScheme.onSurface).withValues(alpha: 0.18);
    return SizedBox(
      height: 28,
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: LayoutBuilder(builder: (_, c) {
            final n = (c.maxWidth / 10).floor();
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(n, (_) => Container(width: 5, height: 1.5, color: line)),
            );
          }),
        ),
        Positioned(left: -14, child: _notch(bg)),
        Positioned(right: -14, child: _notch(bg)),
      ]),
    );
  }

  Widget _notch(Color bg) =>
      Container(width: 28, height: 28, decoration: BoxDecoration(color: bg, shape: BoxShape.circle));
}
