import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';

import '../core/airlines.dart';
import '../models/pass.dart';
import '../services/native.dart';
import '../services/store.dart';
import 'widgets.dart';
import '../core/i18n.dart';

/// Opens the full-screen code for [p] and everyone else on the same booking.
void openBoardingCode(BuildContext context, FlightPass p) {
  final group = [p, ...store.companions(p)].where((x) => x.barcode.isNotEmpty).toList();
  if (group.isEmpty) return;
  Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true, builder: (_) => BoardingCodePage(passes: group)));
}

Barcode barcodeFor(String format) => switch (format) {
      'qr' => Barcode.qrCode(),
      'aztec' => Barcode.aztec(),
      'datamatrix' => Barcode.dataMatrix(),
      'code128' => Barcode.code128(),
      _ => Barcode.pdf417(),
    };

/// White screen, maximum brightness, swipe between passengers.
class BoardingCodePage extends StatefulWidget {
  const BoardingCodePage({super.key, required this.passes});
  final List<FlightPass> passes;
  @override
  State<BoardingCodePage> createState() => _BoardingCodePageState();
}

class _BoardingCodePageState extends State<BoardingCodePage> {
  int _page = 0;

  @override
  void initState() {
    super.initState();
    Native.brightness(1.0);
    Native.keepScreenOn(true);
  }

  @override
  void dispose() {
    Native.brightness(null);
    Native.keepScreenOn(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF111318);
    return Theme(
      data: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF2B5CE6)),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: ink,
          title: Text(widget.passes.length > 1
              ? tr('Pasager ${_page + 1} din ${widget.passes.length}', 'Passenger ${_page + 1} of ${widget.passes.length}')
              : tr('Bilet de îmbarcare', 'Boarding pass')),
        ),
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: PageView.builder(
                itemCount: widget.passes.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _one(widget.passes[i]),
              ),
            ),
            if (widget.passes.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < widget.passes.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _page ? 20 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _page ? ink : Colors.black26,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _one(FlightPass p) {
    const ink = Color(0xFF111318);
    final square = p.barcodeFormat == 'qr' || p.barcodeFormat == 'aztec' || p.barcodeFormat == 'datamatrix';
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth - 40;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(children: [
          Text(p.passenger.isEmpty ? '—' : p.passenger,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: ink)),
          const SizedBox(height: 4),
          Text('${p.flightCode} · ${Airlines.name(p.carrier)} · ${shortDate(p.day)}',
              style: const TextStyle(fontSize: 15, color: Colors.black54)),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: BarcodeWidget(
              barcode: barcodeFor(p.barcodeFormat),
              data: p.barcode,
              drawText: false,
              color: Colors.black,
              backgroundColor: Colors.white,
              width: square ? w * 0.82 : w,
              height: square ? w * 0.82 : w * 0.36,
              errorBuilder: (_, e) => Text(tr('Codul nu poate fi afișat.', 'The code cannot be shown.')),
            ),
          ),
          const SizedBox(height: 28),
          CellRow([
            (tr('De la', 'From'), p.from),
            (tr('Spre', 'To'), p.to),
            (tr('Loc', 'Seat'), p.seat),
          ], color: ink),
          const Divider(height: 32, color: Colors.black12),
          CellRow([
            (tr('Poarta', 'Gate'), p.gate),
            (tr('Îmbarcare', 'Boarding'), p.boarding ?? ''),
            (tr('Secvență', 'Seq.'), p.sequence),
          ], color: ink),
        ]),
      );
    });
  }
}
