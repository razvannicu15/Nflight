import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/bcbp.dart';
import '../core/i18n.dart';
import '../services/importer.dart';

/// Live camera scanner. Pops with the codes it found.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  // Full HD analysis: dense PDF417 codes are unreadable at the 640x480 default.
  final _ctl = MobileScannerController(
    formats: boardingFormats,
    detectionSpeed: DetectionSpeed.unrestricted,
    cameraResolution: const Size(1920, 1080),
    autoZoom: true,
  );
  bool _done = false;
  bool _torch = false;
  double _zoom = 0;
  double _zoomStart = 0;

  // A non-standard code is accepted once it has been seen a few times,
  // so a stray QR in the background does not win over the boarding pass.
  String? _other;
  int _otherHits = 0;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _finish(List<ScannedCode> codes) {
    if (_done) return;
    _done = true;
    Navigator.pop(context, codes);
  }

  void _onDetect(BarcodeCapture cap) {
    if (_done) return;
    for (final b in cap.barcodes) {
      final v = b.rawValue;
      if (v == null || v.isEmpty) continue;
      if (parseBcbp(v) != null) {
        _finish([ScannedCode(v, formatName(b.format))]);
        return;
      }
      if (v == _other) {
        if (++_otherHits >= 6) _finish([ScannedCode(v, formatName(b.format))]);
      } else {
        _other = v;
        _otherHits = 1;
      }
    }
  }

  Future<void> _fromGallery() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = r?.files.single.path;
    if (path == null) return;
    final codes = await Importer.scanImage(path);
    if (!mounted) return;
    if (codes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Niciun cod în imagine', 'No code in this image'))));
      return;
    }
    _finish(codes);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width * 0.86;
    final window = Rect.fromCenter(
        center: size.center(Offset.zero) - const Offset(0, 40), width: w, height: w * 0.66);
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_torch ? Icons.flashlight_off_outlined : Icons.flashlight_on_outlined),
            onPressed: () {
              _ctl.toggleTorch();
              setState(() => _torch = !_torch);
            },
          ),
        ],
      ),
      body: GestureDetector(
        onScaleStart: (_) => _zoomStart = _zoom,
        onScaleUpdate: (d) {
          final z = (_zoomStart + (d.scale - 1) * 0.5).clamp(0.0, 1.0);
          if ((z - _zoom).abs() > 0.01) {
            _zoom = z;
            _ctl.setZoomScale(z);
          }
        },
        child: Stack(fit: StackFit.expand, children: [
          MobileScanner(controller: _ctl, onDetect: _onDetect),
          IgnorePointer(child: CustomPaint(painter: _Frame(window))),
          Positioned(
            left: 24,
            right: 24,
            top: window.bottom + 20,
            child: Text(
              tr('Încadrează codul de pe bilet', 'Frame the code on your pass'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Center(
              child: FilledButton.tonalIcon(
                onPressed: _fromGallery,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(tr('Din galerie', 'From gallery')),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Frame extends CustomPainter {
  _Frame(this.window);
  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(window, const Radius.circular(24));
    final bg = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(r)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(bg, Paint()..color = Colors.black.withValues(alpha: 0.5));
    // Corner brackets only: cleaner than a full outline.
    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const l = 34.0, rad = 24.0;
    final w = window;
    for (final (x, y, sx, sy) in [
      (w.left, w.top, 1.0, 1.0),
      (w.right, w.top, -1.0, 1.0),
      (w.left, w.bottom, 1.0, -1.0),
      (w.right, w.bottom, -1.0, -1.0),
    ]) {
      final path = Path()
        ..moveTo(x, y + sy * (rad + l))
        ..lineTo(x, y + sy * rad)
        ..arcToPoint(Offset(x + sx * rad, y),
            radius: const Radius.circular(rad), clockwise: sx * sy > 0)
        ..lineTo(x + sx * (rad + l), y);
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_Frame old) => old.window != window;
}
