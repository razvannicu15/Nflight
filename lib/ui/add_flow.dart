import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/pass.dart';
import '../services/importer.dart';
import '../services/notifier.dart';
import '../services/status_api.dart';
import '../services/store.dart';
import 'edit_pass_page.dart';
import 'pass_detail_page.dart';
import 'scan_page.dart';
import '../core/i18n.dart';

Future<void> showAddSheet(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(tr('Adaugă un bilet de îmbarcare', 'Add a boarding pass'), style: Theme.of(c).textTheme.titleLarge),
        ),
        _opt(c, 'camera', Icons.qr_code_scanner, tr('Scanează cu camera', 'Scan with camera'),
            tr('Bilet pe hârtie sau pe alt ecran', 'Paper pass or another screen')),
        _opt(c, 'file', Icons.upload_file, tr('Din fișier', 'From a file'),
            tr('PDF-ul de la companie, captură de ecran, poză sau .pkpass',
                'Airline PDF, screenshot, photo or .pkpass')),
        _opt(c, 'manual', Icons.edit_note, tr('Manual', 'Manually'),
            tr('Zbor fără bilet digital', 'Flight without a digital pass')),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'camera':
      final codes = await Navigator.of(context)
          .push<List<ScannedCode>>(MaterialPageRoute(builder: (_) => const ScanPage()));
      if (codes == null || !context.mounted) return;
      await saveImported(context, Importer.fromCodes(codes));
    case 'file':
      final r = await FilePicker.platform.pickFiles(type: FileType.any);
      final path = r?.files.single.path;
      if (path == null || !context.mounted) return;
      final res = await runWithProgress(context, Importer.fromFile(path));
      if (context.mounted) await saveImported(context, res);
    case 'manual':
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditPassPage()));
  }
}

Widget _opt(BuildContext c, String v, IconData icon, String title, String sub) => ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(c).colorScheme.secondaryContainer,
        foregroundColor: Theme.of(c).colorScheme.onSecondaryContainer,
        child: Icon(icon),
      ),
      title: Text(title),
      subtitle: Text(sub),
      onTap: () => Navigator.pop(c, v),
    );

Future<T> runWithProgress<T>(BuildContext context, Future<T> job) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: Center(child: Card(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          Text(tr('Caut codul de îmbarcare…', 'Looking for the boarding code…')),
        ]),
      ))),
    ),
  );
  try {
    return await job;
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

/// Stores imported passes, schedules reminders, fetches status, opens the first.
Future<void> saveImported(BuildContext context, ImportResult res) async {
  final messenger = ScaffoldMessenger.of(context);
  if (res.passes.isEmpty) {
    messenger.showSnackBar(SnackBar(
      content: Text(res.error ?? tr('Nu am găsit niciun bilet.', 'No pass found.')),
      action: SnackBarAction(
        label: tr('Manual', 'Manually'),
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const EditPassPage())),
      ),
    ));
    return;
  }
  final saved = <FlightPass>[];
  for (final p in res.passes) {
    saved.add(store.upsert(p));
  }
  for (final p in saved) {
    await Notifier.schedule(p);
  }
  messenger.showSnackBar(SnackBar(
      content: Text(saved.length == 1
          ? tr('Bilet salvat: ${saved.first.flightCode}, ${saved.first.route}',
              'Pass saved: ${saved.first.flightCode}, ${saved.first.route}')
          : tr('${saved.length} zboruri salvate', '${saved.length} flights saved'))));
  if (StatusApi.enabled) {
    for (final p in saved) {
      if (!Store.isPast(p)) StatusApi.refresh(p);
    }
  }
  if (context.mounted) {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => PassDetailPage(passId: saved.first.id)));
  }
}
