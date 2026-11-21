import 'package:flutter/material.dart';

import '../main.dart';
import '../services/importer.dart';
import '../services/native.dart';
import '../services/notifier.dart';
import '../services/status_api.dart';
import '../services/store.dart';
import 'add_flow.dart';
import 'pass_detail_page.dart';
import 'settings_page.dart';
import 'stats_page.dart';
import 'trips_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
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
      StatusApi.refreshSoon();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) StatusApi.refreshSoon();
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
              label: const Text('Adaugă'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.flight_takeoff_outlined),
              selectedIcon: Icon(Icons.flight_takeoff),
              label: 'Zboruri'),
          NavigationDestination(
              icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history), label: 'Istoric'),
          NavigationDestination(
              icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Statistici'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Setări'),
        ],
      ),
    );
  }
}
