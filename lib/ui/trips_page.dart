import 'package:flutter/material.dart';

import '../models/pass.dart';
import '../services/status_api.dart';
import '../services/store.dart';
import 'add_flow.dart';
import 'boarding_code_page.dart';
import 'pass_detail_page.dart';
import 'widgets.dart';
import '../core/i18n.dart';

class TripsPage extends StatelessWidget {
  const TripsPage({super.key, required this.history});
  final bool history;

  void _open(BuildContext context, FlightPass p) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => PassDetailPage(passId: p.id)));

  Future<void> _refresh() async {
    for (final p in store.upcoming.take(6)) {
      final h = Store.departureOf(p).difference(DateTime.now()).inHours;
      if (h < 72 && h > -12) await StatusApi.refresh(p, notify: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final list = history ? store.history : store.upcoming;
        final body = list.isEmpty
            ? (history ? const _EmptyHistory() : const _EmptyTrips())
            : _list(context, list);
        return Scaffold(
          body: NestedScrollView(
            headerSliverBuilder: (c, _) => [
              SliverAppBar.medium(
                title: Text(history ? tr('Istoric', 'History') : tr('Zborurile mele', 'My flights')),
              ),
            ],
            body: history || !StatusApi.enabled
                ? body
                : RefreshIndicator(onRefresh: _refresh, child: body),
          ),
        );
      },
    );
  }

  Widget _list(BuildContext context, List<FlightPass> list) {
    final items = <Widget>[];
    var start = 0;
    if (!history) {
      final next = list.first;
      items.add(NextFlightCard(
        next,
        onTap: () => _open(context, next),
        onShowCode: () => openBoardingCode(context, next),
      ));
      start = 1;
    }
    String? lastHeader;
    for (final p in list.skip(start)) {
      final header = history
          ? '${monthName(p.day.month)[0].toUpperCase()}${monthName(p.day.month).substring(1)} ${p.day.year}'
          : longDate(p.day);
      if (header != lastHeader) {
        items.add(SectionTitle(header));
        lastHeader = header;
      }
      items.add(PassTile(p, onTap: () => _open(context, p)));
    }
    items.add(const SizedBox(height: 96));
    return MaxWidth(
      child: ListView(
        padding: const EdgeInsets.only(top: 4),
        physics: const AlwaysScrollableScrollPhysics(),
        children: items,
      ),
    );
  }
}

class _EmptyTrips extends StatelessWidget {
  const _EmptyTrips();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    Widget step(int n, String title, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: cs.primaryContainer,
              child: Text('$n', style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(text, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
          ]),
        );
    return MaxWidth(
      child: ListView(padding: const EdgeInsets.fromLTRB(24, 16, 24, 120), children: [
        Center(
          child: Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
            child: Icon(Icons.airplane_ticket_outlined, size: 56, color: cs.onPrimaryContainer),
          ),
        ),
        const SizedBox(height: 20),
        Text(tr('Niciun zbor încă', 'No flights yet'), textAlign: TextAlign.center, style: t.headlineSmall),
        const SizedBox(height: 6),
        Text(tr('Adaugă primul bilet de îmbarcare. Rămâne doar pe telefonul tău și merge fără internet.', 'Add your first boarding pass. It stays on your phone and works offline.'),
            textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 24),
        step(1, tr('Fă check-in online', 'Check in online'), tr('În aplicația sau pe site-ul companiei aeriene.', 'In the airline app or on its website.')),
        step(2, tr('Ia biletul', 'Get the pass'), tr('PDF-ul primit pe e-mail, o captură de ecran sau biletul tipărit.', 'The PDF from your email, a screenshot or the printed pass.')),
        step(3, tr('Adaugă-l aici', 'Add it here'), tr('Apasă „Adaugă” sau trimite fișierul spre Nflight din „Distribuie”.', 'Tap “Add” or send the file to Nflight from “Share”.')),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => showAddSheet(context),
          icon: const Icon(Icons.add),
          label: Text(tr('Adaugă un bilet', 'Add a pass')),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
      ]),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.history, size: 56, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(tr('Zborurile încheiate apar aici.', 'Past flights show up here.'),
              textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}
