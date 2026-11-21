import 'package:flutter/material.dart';

import '../core/airports.dart';
import '../models/pass.dart';
import 'widgets.dart';
import '../core/i18n.dart';

/// EU + EEA + Switzerland: where Regulation (EC) 261/2004 applies.
const euCountries = {
  'AT', 'BE', 'BG', 'HR', 'CY', 'CZ', 'DK', 'EE', 'FI', 'FR', 'DE', 'GR', 'HU', 'IE', 'IT',
  'LV', 'LT', 'LU', 'MT', 'NL', 'PL', 'PT', 'RO', 'SK', 'SI', 'ES', 'SE', 'IS', 'NO', 'LI', 'CH',
};

/// Amount in EUR for a delay at arrival / cancellation, or 0.
/// Simplified: the airline may still refuse for "extraordinary circumstances".
int compensationEur(double distanceKm, int delayMinutes, {required bool intraEu, bool cancelled = false}) {
  if (!cancelled && delayMinutes < 180) return 0;
  if (distanceKm <= 1500) return 250;
  if (distanceKm <= 3500 || intraEu) return 400;
  // Long haul: halved when the delay is between 3 and 4 hours.
  if (!cancelled && delayMinutes < 240) return 300;
  return 600;
}

void showCompensationSheet(BuildContext context, FlightPass p) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CompSheet(p),
  );
}

class _CompSheet extends StatefulWidget {
  const _CompSheet(this.p);
  final FlightPass p;
  @override
  State<_CompSheet> createState() => _CompSheetState();
}

class _CompSheetState extends State<_CompSheet> {
  late double _delay = ((widget.p.arrivalDelayMinutes > 0 ? widget.p.arrivalDelayMinutes : widget.p.delayMinutes) / 60)
      .clamp(0, 8)
      .toDouble();
  late bool _cancelled = widget.p.status == FlightStatus.cancelled;

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final dist = Airports.distanceKm(p.from, p.to);
    final fromEu = euCountries.contains(Airports.get(p.from)?.country);
    final toEu = euCountries.contains(Airports.get(p.to)?.country);
    final amount = compensationEur(dist, (_delay * 60).round(), intraEu: fromEu && toEu, cancelled: _cancelled);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Compensație UE 261', 'EU 261 compensation'), style: t.titleLarge),
          const SizedBox(height: 4),
          Text('${p.from} → ${p.to} · ${km(dist)} km', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Zbor anulat', 'Flight cancelled')),
            subtitle: Text(tr('Anunțat cu mai puțin de 14 zile înainte', 'Announced less than 14 days before')),
            value: _cancelled,
            onChanged: (v) => setState(() => _cancelled = v),
          ),
          if (!_cancelled) ...[
            Text('${tr('Întârziere la sosire', 'Arrival delay')}: ${_delay >= 8 ? '8 h+' : durationText(Duration(minutes: (_delay * 60).round()))}',
                style: t.titleSmall),
            Slider(
              value: _delay,
              max: 8,
              divisions: 32,
              label: durationText(Duration(minutes: (_delay * 60).round())),
              onChanged: (v) => setState(() => _delay = v),
            ),
          ],
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: amount > 0 ? cs.primaryContainer : cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(amount > 0 ? tr('$amount € de persoană', '€$amount per person') : tr('Fără compensație', 'No compensation'),
                  style: t.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: amount > 0 ? cs.onPrimaryContainer : cs.onSurface)),
              const SizedBox(height: 4),
              Text(
                amount > 0
                    ? tr('Se cere direct de la compania aeriană, de obicei printr-un formular pe site-ul ei.',
                        'Claim it directly from the airline, usually through a form on its website.')
                    : tr('Compensația începe de la 3 ore întârziere la sosire.',
                        'Compensation starts at a 3-hour delay on arrival.'),
                style: t.bodyMedium?.copyWith(color: amount > 0 ? cs.onPrimaryContainer : cs.onSurfaceVariant),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Text(
            fromEu
                ? tr('Zborul pleacă din UE, deci regulamentul se aplică.', 'The flight departs from the EU, so the regulation applies.')
                : toEu
                    ? tr('Se aplică doar dacă zbori cu o companie aeriană din UE.', 'It applies only if you fly with an EU airline.')
                    : tr('Zborul nu pleacă și nu aterizează în UE: regulamentul nu se aplică.', 'The flight neither departs from nor lands in the EU: the regulation does not apply.'),
            style: t.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            tr('Calcul orientativ. Compania poate refuza plata pentru circumstanțe extraordinare '
                '(vreme, greve ale controlorilor de trafic etc.).',
                'Rough estimate. The airline may refuse to pay for extraordinary circumstances '
                '(weather, air traffic control strikes, etc.).'),
            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }
}
