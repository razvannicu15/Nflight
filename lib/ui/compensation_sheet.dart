import 'package:flutter/material.dart';

import '../core/airports.dart';
import '../models/pass.dart';
import 'widgets.dart';

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
  late double _delay = (widget.p.delayMinutes / 60).clamp(0, 8).toDouble();
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
          Text('Compensație UE 261', style: t.titleLarge),
          const SizedBox(height: 4),
          Text('${p.from} → ${p.to} · ${km(dist)} km', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Zbor anulat'),
            subtitle: const Text('Anunțat cu mai puțin de 14 zile înainte'),
            value: _cancelled,
            onChanged: (v) => setState(() => _cancelled = v),
          ),
          if (!_cancelled) ...[
            Text('Întârziere la sosire: ${_delay >= 8 ? '8 h+' : durationText(Duration(minutes: (_delay * 60).round()))}',
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
              Text(amount > 0 ? '$amount € de persoană' : 'Fără compensație',
                  style: t.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: amount > 0 ? cs.onPrimaryContainer : cs.onSurface)),
              const SizedBox(height: 4),
              Text(
                amount > 0
                    ? 'Se cere direct de la compania aeriană, de obicei printr-un formular pe site-ul ei.'
                    : 'Compensația începe de la 3 ore întârziere la sosire.',
                style: t.bodyMedium?.copyWith(color: amount > 0 ? cs.onPrimaryContainer : cs.onSurfaceVariant),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Text(
            fromEu
                ? 'Zborul pleacă din UE, deci regulamentul se aplică.'
                : toEu
                    ? 'Se aplică doar dacă zbori cu o companie aeriană din UE.'
                    : 'Zborul nu pleacă și nu aterizează în UE: regulamentul nu se aplică.',
            style: t.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Calcul orientativ. Compania poate refuza plata pentru circumstanțe extraordinare '
            '(vreme, greve ale controlorilor de trafic etc.).',
            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }
}
