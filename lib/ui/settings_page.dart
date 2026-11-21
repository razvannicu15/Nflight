import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/pass.dart';
import '../services/notifier.dart';
import '../services/status_api.dart';
import '../services/store.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  void _set(VoidCallback f, {bool reschedule = false}) {
    f();
    store.save();
    if (reschedule) Notifier.rescheduleAll();
  }

  Future<void> _editKey() async {
    final c = TextEditingController(text: store.apiKey);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cheie AeroDataBox'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
              'Pentru întârzieri, poartă și terminal în timp real. Fă-ți un cont gratuit pe '
              'rapidapi.com, abonează-te la planul gratuit AeroDataBox și copiază aici cheia '
              '„X-RapidAPI-Key”. Fără cheie, aplicația merge normal, doar fără status live.'),
          const SizedBox(height: 16),
          TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'X-RapidAPI-Key'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anulează')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Salvează')),
        ],
      ),
    );
    if (v == null) return;
    _set(() => store.apiKey = v);
    if (v.isNotEmpty) StatusApi.refreshSoon();
  }

  Future<void> _export() async {
    final bytes = Uint8List.fromList(utf8.encode(store.exportJson()));
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Salvează copia de siguranță',
      fileName: 'nflight-${ymd(DateTime.now())}.json',
      bytes: bytes,
    );
    if (!mounted || path == null) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copie salvată')));
  }

  Future<void> _import() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = r?.files.single.path;
    if (path == null) return;
    String msg;
    try {
      final n = store.importJson(await File(path).readAsString());
      await Notifier.rescheduleAll();
      msg = n == 0 ? 'Nimic nou de adăugat' : '$n bilete restaurate';
    } catch (_) {
      msg = 'Fișierul nu este o copie Nflight.';
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (c, _) => [const SliverAppBar.medium(title: Text('Setări'))],
          body: MaxWidth(
            child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
              const SectionTitle('Aspect'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('Automat'), icon: Icon(Icons.brightness_auto_outlined)),
                    ButtonSegment(value: ThemeMode.light, label: Text('Luminos'), icon: Icon(Icons.light_mode_outlined)),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Întunecat'), icon: Icon(Icons.dark_mode_outlined)),
                  ],
                  selected: {store.themeMode},
                  onSelectionChanged: (s) => _set(() => store.themeMode = s.first),
                ),
              ),
              const SectionTitle('Notificări'),
              SwitchListTile(
                title: const Text('Cu o zi înainte'),
                value: store.remind24h,
                onChanged: (v) => _set(() => store.remind24h = v, reschedule: true),
              ),
              SwitchListTile(
                title: const Text('Cu 3 ore înainte'),
                subtitle: const Text('Cu terminalul și poarta, dacă sunt anunțate'),
                value: store.remind3h,
                onChanged: (v) => _set(() => store.remind3h = v, reschedule: true),
              ),
              SwitchListTile(
                title: const Text('La îmbarcare'),
                subtitle: const Text('Cu 45 de minute înainte; atingi și se deschide biletul'),
                value: store.remindBoarding,
                onChanged: (v) => _set(() => store.remindBoarding = v, reschedule: true),
              ),
              const SectionTitle('Status live'),
              ListTile(
                leading: Icon(StatusApi.enabled ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                    color: StatusApi.enabled ? cs.primary : null),
                title: const Text('Cheie AeroDataBox'),
                subtitle: Text(StatusApi.enabled
                    ? 'Activ · se verifică doar zborurile din următoarele 36 de ore'
                    : 'Opțional · întârzieri, poartă și terminal'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _editKey,
              ),
              const SectionTitle('Bilete'),
              SwitchListTile(
                title: const Text('Mută automat în istoric'),
                subtitle: const Text('Zborurile încheiate dispar din lista principală'),
                value: store.autoArchive,
                onChanged: (v) => _set(() => store.autoArchive = v),
              ),
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('Salvează o copie de siguranță'),
                subtitle: Text('${store.passes.length} bilete, într-un fișier .json'),
                onTap: _export,
              ),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('Restaurează din copie'),
                onTap: _import,
              ),
              const SectionTitle('Despre'),
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Nflight 0.1'),
                subtitle: Text('Fără reclame, fără cont. Biletele rămân doar pe telefonul tău. norAz'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
