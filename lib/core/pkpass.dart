import 'dart:convert';

import 'package:archive/archive.dart';

/// The parts of an Apple Wallet .pkpass we care about.
class PkPassInfo {
  PkPassInfo({
    required this.message,
    required this.format,
    this.relevantDate,
    this.fields = const {},
    this.description = '',
  });

  final String message;
  final String format; // pdf417 | qr | aztec | code128
  final DateTime? relevantDate;

  /// Lower-cased "key" or "label" -> value for every field on the pass.
  final Map<String, String> fields;
  final String description;

  String? field(List<String> names) {
    for (final n in names) {
      for (final e in fields.entries) {
        if (e.key.contains(n)) return e.value;
      }
    }
    return null;
  }
}

PkPassInfo? parsePkPass(List<int> bytes) {
  try {
    final zip = ZipDecoder().decodeBytes(bytes);
    final file = zip.files.firstWhere((f) => f.name == 'pass.json');
    final j = jsonDecode(utf8.decode(file.content as List<int>)) as Map<String, dynamic>;
    Map<String, dynamic>? bc;
    final list = j['barcodes'];
    if (list is List && list.isNotEmpty) bc = Map<String, dynamic>.from(list.first as Map);
    bc ??= j['barcode'] is Map ? Map<String, dynamic>.from(j['barcode'] as Map) : null;
    if (bc == null) return null;
    final fmt = (bc['format'] ?? '').toString().toLowerCase();
    final fields = <String, String>{};
    final style = j['boardingPass'] ?? j['generic'] ?? j['eventTicket'];
    if (style is Map) {
      for (final group in ['headerFields', 'primaryFields', 'secondaryFields', 'auxiliaryFields', 'backFields']) {
        final g = style[group];
        if (g is! List) continue;
        for (final f in g) {
          if (f is! Map) continue;
          final v = (f['value'] ?? '').toString().trim();
          if (v.isEmpty) continue;
          fields[(f['key'] ?? '').toString().toLowerCase()] = v;
          final label = (f['label'] ?? '').toString().toLowerCase();
          if (label.isNotEmpty) fields.putIfAbsent(label, () => v);
        }
      }
    }
    return PkPassInfo(
      message: (bc['message'] ?? '').toString(),
      format: fmt.contains('qr')
          ? 'qr'
          : fmt.contains('aztec')
              ? 'aztec'
              : fmt.contains('128')
                  ? 'code128'
                  : 'pdf417',
      relevantDate: DateTime.tryParse((j['relevantDate'] ?? '').toString()),
      fields: fields,
      description: (j['description'] ?? '').toString(),
    );
  } catch (_) {
    return null;
  }
}

/// Picks "HH:mm" out of a pass field value like "14:35", "2:35 PM" or an ISO date.
String? timeOf(String? v) {
  if (v == null) return null;
  final iso = DateTime.tryParse(v);
  if (iso != null) {
    return '${iso.hour.toString().padLeft(2, '0')}:${iso.minute.toString().padLeft(2, '0')}';
  }
  final m = RegExp(r'(\d{1,2})[:.](\d{2})\s*([AaPp][Mm])?').firstMatch(v);
  if (m == null) return null;
  var h = int.parse(m.group(1)!);
  final ap = m.group(3)?.toLowerCase();
  if (ap == 'pm' && h < 12) h += 12;
  if (ap == 'am' && h == 12) h = 0;
  return '${h.toString().padLeft(2, '0')}:${m.group(2)}';
}
