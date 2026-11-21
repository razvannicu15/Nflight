import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../models/pass.dart';
import '../services/notifier.dart';
import '../services/board_api.dart';
import '../services/live_api.dart';
import '../services/quota.dart';
import '../services/status_api.dart';
import '../services/store.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

/// Set by CI: --dart-define=BUILD=123 --dart-define=BUILT=2026-11-21 14:58
const _build = String.fromEnvironment('BUILD');
const _built = String.fromEnvironment('BUILT');
String get _version => _build.isEmpty ? 'Nflight 0.1' : 'Nflight 0.1.$_build${_built.isEmpty ? '' : ' · $_built'}';

class _SettingsPageState extends State<SettingsPage> {
  void _set(VoidCallback f, {bool reschedule = false}) {
    f();
    store.save();
    if (reschedule) Notifier.rescheduleAll();
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
                  showSelectedIcon: false,
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
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: ThemeMode.system, icon: const Icon(Icons.brightness_auto_outlined), tooltip: tr('Automat', 'Auto')),
                    ButtonSegment(value: ThemeMode.light, icon: const Icon(Icons.light_mode_outlined), tooltip: tr('Luminos', 'Light')),
                    ButtonSegment(value: ThemeMode.dark, icon: const Icon(Icons.dark_mode_outlined), tooltip: tr('Întunecat', 'Dark')),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Card(
                  elevation: 0,
                  color: cs.surfaceContainerLow,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
                    child: Column(children: [
                      _QuotaRow(tr('Status și tabele', 'Status and boards'), 'AeroDataBox', Quota.get(Quota.aerodatabox),
                          active: StatusApi.enabled),
                      if (BoardApi.avKey.isNotEmpty)
                        _QuotaRow(tr('Rezervă tabele', 'Backup boards'), 'aviationstack', Quota.get(Quota.aviationstack)),
                      _QuotaRow(tr('Hartă live', 'Live map'), LiveApi.authed ? 'OpenSky · ${tr('cont', 'account')}' : 'OpenSky',
                          Quota.get(Quota.opensky, expectedLimit: LiveApi.authed ? 4000 : 400),
                          error: LiveApi.authError == null ? null : tr('autentificare eșuată (${LiveApi.authError}) · verifică client_id și secret',
                              'login failed (${LiveApi.authError}) · check client_id and secret'),
                          last: true),
                    ]),
                  ),
                ),
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
                title: Text(_version),
                subtitle: Text(tr('Fără reclame · norAz', 'No ads · norAz')),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One data source: remaining / total, a slim bar and when it refills.
class _QuotaRow extends StatelessWidget {
  const _QuotaRow(this.title, this.source, this.q, {this.active = true, this.last = false, this.error});
  final String? error;
  final String title;
  final String source;
  final QuotaInfo? q;
  final bool active;
  final bool last;

  String _reset(DateTime r) {
    final now = DateTime.now();
    final d = DateTime(r.year, r.month, r.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    final at = '${r.hour.toString().padLeft(2, '0')}:${r.minute.toString().padLeft(2, '0')}';
    if (d <= 0) return tr('se reîncarcă azi la $at', 'refills today at $at');
    if (d == 1) return tr('se reîncarcă mâine la $at', 'refills tomorrow at $at');
    return tr('se reîncarcă în $d zile · ${shortDate(r)}', 'refills in $d days · ${shortDate(r)}');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final q = this.q;
    final rem = q?.remaining, lim = q?.limit;
    final frac = (active && rem != null && lim != null && lim > 0) ? (rem / lim).clamp(0.0, 1.0) : null;
    final low = frac != null && frac < 0.15;
    final String right;
    if (!active) {
      right = tr('inactiv', 'off');
    } else if (rem == null) {
      right = '—';
    } else {
      right = lim == null ? '$rem' : '$rem / $lim';
    }
    final sub = !active
        ? tr('fără cheie API', 'no API key')
        : q == null
            ? tr('încă nicio cerere', 'no requests yet')
            : [
                if (q.resetAt != null) _reset(q.resetAt!),
                if (q.estimated) tr('estimat', 'estimated'),
              ].join(' · ');
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: title, style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                TextSpan(text: '  $source', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ])),
            ),
            Text(right,
                style: t.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: low ? cs.error : null,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
          if (frac != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 6,
                color: low ? cs.error : cs.primary,
                backgroundColor: cs.surfaceContainerHighest,
              ),
            ),
          ],
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(sub, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
          if (error != null) ...[
            const SizedBox(height: 4),
            Text(error!, style: t.bodySmall?.copyWith(color: cs.error, fontWeight: FontWeight.w600)),
          ],
        ]),
      ),
      if (!last) Divider(height: 1, thickness: 0.6, color: cs.outlineVariant.withValues(alpha: 0.6)),
    ]);
  }
}
