import 'package:flutter/material.dart';

import '../main.dart';
import '../services/importer.dart';
import '../services/native.dart';
import '../services/notifier.dart';
import '../services/status_api.dart';
import '../services/store.dart';
import 'add_flow.dart';
import 'board_page.dart';
import 'pass_detail_page.dart';
import 'settings_page.dart';
import 'stats_page.dart';
import 'trips_page.dart';
import '../core/i18n.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.startServices = true, this.initialTab = 0});

  /// False in screenshot tests: no plugins, no network.
  final bool startServices;
  final int initialTab;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  late int _tab = widget.initialTab;

  @override
  void initState() {
    super.initState();
    if (!widget.startServices) return;
    WidgetsBinding.instance.addObserver(this);
    Native.onFile = _openFile;
    Notifier.onOpen = _openPass;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final launch = Notifier.launchPassId;
      if (launch != null) _openPass(launch);
      final f = await Native.initialFile();
      if (f != null) _openFile(f);
      await Notifier.requestPermission();
      await Notifier.rescheduleAll();
      await StatusApi.refreshSoon();
      StatusApi.backfillPast();
    });
  }

  @override
  void dispose() {
    if (!widget.startServices) return super.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && widget.startServices) StatusApi.refreshSoon();
  }

  void _openPass(String id) {
    final p = store.byId(id);
    final nav = navigatorKey.currentState;
    if (p == null || nav == null) return;
    nav.push(MaterialPageRoute(builder: (_) => PassDetailPage(passId: p.id)));
  }

  Future<void> _openFile(String path) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    final res = await runWithProgress(ctx, Importer.fromFile(path));
    if (!mounted) return;
    final c = navigatorKey.currentContext;
    if (c != null && c.mounted) await saveImported(c, res);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const TripsPage(history: false),
      BoardPage(active: _tab == 1 && widget.startServices),
      const TripsPage(history: true),
      const StatsPage(),
      const SettingsPage(),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => showAddSheet(context),
              icon: const Icon(Icons.add),
              label: Text(tr('Adaugă', 'Add')),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.flight_takeoff_outlined),
              selectedIcon: const Icon(Icons.flight_takeoff),
              label: tr('Zboruri', 'Flights')),
          NavigationDestination(
              icon: const Icon(Icons.connecting_airports_outlined),
              selectedIcon: const Icon(Icons.connecting_airports),
              label: tr('Aeroport', 'Airport')),
          NavigationDestination(
              icon: const Icon(Icons.history_outlined),
              selectedIcon: const Icon(Icons.history),
              label: tr('Istoric', 'History')),
          NavigationDestination(
              icon: const Icon(Icons.insights_outlined),
              selectedIcon: const Icon(Icons.insights),
              label: tr('Statistici', 'Stats')),
          NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings),
              label: tr('Setări', 'Settings')),
        ],
      ),
    );
  }
}
