import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/i18n.dart';
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
        title: Text(tr('Cheie AeroDataBox', 'AeroDataBox key')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Cheie gratuită de pe rapidapi.com (AeroDataBox).',
              'Free key from rapidapi.com (AeroDataBox).')),
          const SizedBox(height: 16),
          TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'X-RapidAPI-Key'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Anulează', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(tr('Salvează', 'Save'))),
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
      dialogTitle: tr('Salvează copia de siguranță', 'Save backup'),
      fileName: 'nflight-${ymd(DateTime.now())}.json',
      bytes: bytes,
    );
    if (!mounted || path == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Copie salvată', 'Backup saved'))));
  }

  Future<void> _import() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = r?.files.single.path;
    if (path == null) return;
    String msg;
    try {
      final n = store.importJson(await File(path).readAsString());
      await Notifier.rescheduleAll();
      msg = n == 0 ? tr('Nimic nou de adăugat', 'Nothing new to add') : tr('$n bilete restaurate', '$n passes restored');
    } catch (_) {
      msg = tr('Fișierul nu este o copie Nflight.', 'This is not an Nflight backup.');
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
          headerSliverBuilder: (c, _) => [SliverAppBar.medium(title: Text(tr('Setări', 'Settings')))],
          body: MaxWidth(
            child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
              SectionTitle(tr('Limbă', 'Language')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'system', label: Text(tr('Automat', 'Auto'))),
                    const ButtonSegment(value: 'ro', label: Text('Română')),
                    const ButtonSegment(value: 'en', label: Text('English')),
                  ],
                  selected: {store.language},
                  onSelectionChanged: (s) => _set(() => store.language = s.first, reschedule: true),
                ),
              ),
              SectionTitle(tr('Aspect', 'Appearance')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment(value: ThemeMode.system, label: Text(tr('Automat', 'Auto')), icon: const Icon(Icons.brightness_auto_outlined)),
                    ButtonSegment(value: ThemeMode.light, label: Text(tr('Luminos', 'Light')), icon: const Icon(Icons.light_mode_outlined)),
                    ButtonSegment(value: ThemeMode.dark, label: Text(tr('Întunecat', 'Dark')), icon: const Icon(Icons.dark_mode_outlined)),
                  ],
                  selected: {store.themeMode},
                  onSelectionChanged: (s) => _set(() => store.themeMode = s.first),
                ),
              ),
              SectionTitle(tr('Notificări', 'Notifications')),
              SwitchListTile(
                title: Text(tr('Cu o zi înainte', 'One day before')),
                value: store.remind24h,
                onChanged: (v) => _set(() => store.remind24h = v, reschedule: true),
              ),
              SwitchListTile(
                title: Text(tr('Cu 3 ore înainte', '3 hours before')),
                value: store.remind3h,
                onChanged: (v) => _set(() => store.remind3h = v, reschedule: true),
              ),
              SwitchListTile(
                title: Text(tr('La îmbarcare', 'At boarding')),
                value: store.remindBoarding,
                onChanged: (v) => _set(() => store.remindBoarding = v, reschedule: true),
              ),
              SectionTitle(tr('Status live', 'Live status')),
              ListTile(
                leading: Icon(StatusApi.enabled ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                    color: StatusApi.enabled ? cs.primary : null),
                title: Text(tr('Cheie AeroDataBox', 'AeroDataBox key')),
                subtitle: Text(store.apiKey.trim().isNotEmpty
                    ? tr('Cheie proprie', 'Own key')
                    : StatusApi.builtInKey.isNotEmpty
                        ? tr('Activ · cheie integrată', 'On · built-in key')
                        : tr('Opțional', 'Optional')),
                trailing: const Icon(Icons.chevron_right),
                onTap: _editKey,
              ),
              SectionTitle(tr('Bilete', 'Passes')),
              SwitchListTile(
                title: Text(tr('Mută automat în istoric', 'Move to history automatically')),
                value: store.autoArchive,
                onChanged: (v) => _set(() => store.autoArchive = v),
              ),
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: Text(tr('Salvează o copie de siguranță', 'Save a backup')),
                onTap: _export,
              ),
              ListTile(
                leading: const Icon(Icons.restore),
                title: Text(tr('Restaurează din copie', 'Restore from backup')),
                onTap: _import,
              ),
              SectionTitle(tr('Despre', 'About')),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Nflight 0.1'),
                subtitle: Text(tr('Fără reclame · norAz', 'No ads · norAz')),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
