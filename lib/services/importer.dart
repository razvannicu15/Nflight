import 'dart:io';

import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

import '../core/bcbp.dart';
import '../core/pkpass.dart';
import '../models/pass.dart';
import '../core/i18n.dart';

/// A barcode read from somewhere: its text and symbology.
class ScannedCode {
  ScannedCode(this.text, this.format);
  final String text;
  final String format; // pdf417 | aztec | qr | code128 | datamatrix
}

String formatName(BarcodeFormat f) => switch (f) {
      BarcodeFormat.pdf417 => 'pdf417',
      BarcodeFormat.aztec => 'aztec',
      BarcodeFormat.qrCode => 'qr',
      BarcodeFormat.code128 => 'code128',
      BarcodeFormat.dataMatrix => 'datamatrix',
      _ => 'qr',
    };

const boardingFormats = [
  BarcodeFormat.pdf417,
  BarcodeFormat.aztec,
  BarcodeFormat.qrCode,
  BarcodeFormat.dataMatrix,
  BarcodeFormat.code128,
];

class ImportResult {
  ImportResult(this.passes, {this.error});
  final List<FlightPass> passes;
  final String? error;
}

class Importer {
  /// Builds one pass per flight leg from a scanned code.
  static List<FlightPass> fromCode(ScannedCode code, {PkPassInfo? pk}) {
    final b = parseBcbp(code.text);
    if (b == null) return [];
    final out = <FlightPass>[];
    for (final (i, leg) in b.legs.indexed) {
      final day = resolveJulian(leg.julianDay,
          issueYearDigit: b.issueYearDigit, issueJulianDay: b.issueJulianDay);
      final p = FlightPass(
        from: leg.from,
        to: leg.to,
        carrier: leg.carrier,
        flightNumber: leg.flightNumber,
        date: ymd(day),
        passenger: b.displayName,
        pnr: leg.pnr,
        seat: leg.seat,
        cabin: cabinName(leg.compartment),
        sequence: leg.sequence,
        frequentFlyer: leg.frequentFlyer ?? '',
        barcode: code.text,
        barcodeFormat: code.format,
      );
      if (pk != null && i == 0) _applyPk(p, pk);
      out.add(p);
    }
    return out;
  }

  static void _applyPk(FlightPass p, PkPassInfo pk) {
    p.gate = pk.field(['gate', 'poarta']) ?? p.gate;
    p.terminal = pk.field(['terminal']) ?? p.terminal;
    p.boarding = timeOf(pk.field(['boarding', 'imbarcare', 'îmbarcare']));
    p.departure = timeOf(pk.field(['departure', 'depart', 'plecare', 'std', 'etd']));
    final rd = pk.relevantDate;
    if (rd != null) {
      final local = rd.toLocal();
      // relevantDate is usually boarding time; use it when nothing better.
      p.boarding ??= hm(local);
      if (p.departure == null && pk.fields.isEmpty) p.departure = hm(local);
    }
    final seat = pk.field(['seat', 'loc']);
    if (seat != null && p.seat.isEmpty) p.seat = seat;
  }

  /// Reads all boarding codes in a picture file.
  static Future<List<ScannedCode>> scanImage(String path) async {
    final ctl = MobileScannerController(formats: boardingFormats);
    try {
      final cap = await ctl.analyzeImage(path, formats: boardingFormats);
      if (cap == null) return [];
      return [
        for (final b in cap.barcodes)
          if ((b.rawValue ?? '').isNotEmpty) ScannedCode(b.rawValue!, formatName(b.format)),
      ];
    } finally {
      await ctl.dispose();
    }
  }

  /// Renders each PDF page and looks for codes (max 6 pages).
  static Future<List<ScannedCode>> scanPdf(String path) async {
    final tmp = await getTemporaryDirectory();
    final doc = await PdfDocument.openFile(path);
    final found = <ScannedCode>[];
    try {
      final pages = doc.pagesCount.clamp(0, 6);
      for (var i = 1; i <= pages; i++) {
        final page = await doc.getPage(i);
        final scale = (3000 / page.width).clamp(2.0, 5.0);
        final img = await page.render(
          width: page.width * scale,
          height: page.height * scale,
          format: PdfPageImageFormat.png,
          backgroundColor: '#FFFFFF',
        );
        await page.close();
        if (img == null) continue;
        final f = File('${tmp.path}/nflight_pdf_$i.png');
        await f.writeAsBytes(img.bytes);
        for (final c in await scanImage(f.path)) {
          if (!found.any((x) => x.text == c.text)) found.add(c);
        }
        await f.delete().catchError((_) => f);
      }
    } finally {
      await doc.close();
    }
    return found;
  }

  /// Any supported file: image, PDF or .pkpass.
  static Future<ImportResult> fromFile(String path) async {
    final lower = path.toLowerCase();
    try {
      if (lower.endsWith('.pkpass') || lower.endsWith('.pkpasses') || await _isZip(path)) {
        final pk = parsePkPass(await File(path).readAsBytes());
        if (pk == null) return ImportResult([], error: tr('Fișierul .pkpass nu a putut fi citit.', 'The .pkpass file could not be read.'));
        final passes = fromCode(ScannedCode(pk.message, pk.format), pk: pk);
        if (passes.isEmpty) {
          return ImportResult([], error: tr('Biletul din .pkpass nu are un cod de îmbarcare standard.', 'The .pkpass has no standard boarding pass code.'));
        }
        return ImportResult(passes);
      }
      final codes = lower.endsWith('.pdf') || await _isPdf(path)
          ? await scanPdf(path)
          : await scanImage(path);
      return fromCodes(codes);
    } catch (e) {
      return ImportResult([], error: tr('Nu am putut citi fișierul.', 'Could not read the file.'));
    }
  }

  static ImportResult fromCodes(List<ScannedCode> codes) {
    if (codes.isEmpty) {
      return ImportResult([], error: tr('Nu am găsit niciun cod de îmbarcare în fișier.', 'No boarding pass code found in the file.'));
    }
    final passes = <FlightPass>[];
    for (final c in codes) {
      passes.addAll(fromCode(c));
    }
    if (passes.isEmpty) {
      return ImportResult([], error: tr('Am găsit un cod, dar nu este un bilet de îmbarcare standard.', 'Found a code, but it is not a standard boarding pass.'));
    }
    return ImportResult(passes);
  }

  static Future<List<int>> _head(String path) async {
    final raf = await File(path).open();
    try {
      return await raf.read(4);
    } finally {
      await raf.close();
    }
  }

  static Future<bool> _isPdf(String path) async {
    final h = await _head(path);
    return h.length == 4 && h[0] == 0x25 && h[1] == 0x50 && h[2] == 0x44 && h[3] == 0x46;
  }

  static Future<bool> _isZip(String path) async {
    final h = await _head(path);
    return h.length == 4 && h[0] == 0x50 && h[1] == 0x4B;
  }
}
