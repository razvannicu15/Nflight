import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/bcbp.dart';
import '../services/importer.dart';

/// Live camera scanner. Pops with the boarding codes it found.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final _ctl = MobileScannerController(formats: boardingFormats, detectionSpeed: DetectionSpeed.normal);
  bool _done = false;
  String? _hint;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    if (_done) return;
    for (final b in cap.barcodes) {
      final v = b.rawValue;
      if (v == null || v.isEmpty) continue;
      if (parseBcbp(v) != null) {
        _done = true;
        Navigator.pop(context, [ScannedCode(v, formatName(b.format))]);
        return;
      }
      setState(() => _hint = 'Codul găsit nu este un bilet de îmbarcare.');
    }
  }

  Future<void> _fromGallery() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = r?.files.single.path;
    if (path == null) return;
    final codes = await Importer.scanImage(path);
    if (!mounted) return;
    if (codes.isEmpty) {
      setState(() => _hint = 'Nu am găsit niciun cod în imagine.');
      return;
    }
    _done = true;
    Navigator.pop(context, codes);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width * 0.84;
    final window = Rect.fromCenter(center: size.center(Offset.zero) - const Offset(0, 40), width: w, height: w * 0.62);
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Scanează biletul'),
        actions: [
          IconButton(
            tooltip: 'Lanternă',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _ctl.toggleTorch(),
          ),
        ],
      ),
      body: Stack(fit: StackFit.expand, children: [
        MobileScanner(controller: _ctl, onDetect: _onDetect),
        CustomPaint(painter: _Frame(window)),
        Positioned(
          left: 24,
          right: 24,
          top: window.bottom + 24,
          child: Text(
            _hint ?? 'Încadrează codul de pe bilet (pătrat sau dreptunghiular).',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 40,
          child: Center(
            child: FilledButton.tonalIcon(
              onPressed: _fromGallery,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Din galerie'),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Frame extends CustomPainter {
  _Frame(this.window);
  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(window, const Radius.circular(20));
    final bg = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(r)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(bg, Paint()..color = Colors.black.withValues(alpha: 0.55));
    canvas.drawRRect(
        r,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(_Frame old) => old.window != window;
}
