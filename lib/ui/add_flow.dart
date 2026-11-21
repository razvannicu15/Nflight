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

Future<void> showAddSheet(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text('Adaugă un bilet de îmbarcare', style: Theme.of(c).textTheme.titleLarge),
        ),
        _opt(c, 'camera', Icons.qr_code_scanner, 'Scanează cu camera',
            'Bilet pe hârtie sau pe alt ecran'),
        _opt(c, 'file', Icons.upload_file, 'Din fișier',
            'PDF-ul de la companie, captură de ecran, poză sau .pkpass'),
        _opt(c, 'manual', Icons.edit_note, 'Manual', 'Zbor fără bilet digital'),
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
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: Card(child: Padding(
        padding: EdgeInsets.all(24),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Text('Caut codul de îmbarcare…'),
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
      content: Text(res.error ?? 'Nu am găsit niciun bilet.'),
      action: SnackBarAction(
        label: 'Manual',
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
          ? 'Bilet salvat: ${saved.first.flightCode}, ${saved.first.route}'
          : '${saved.length} zboruri salvate')));
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
