import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Airline logos, downloaded once per airline and kept on the phone (works offline after).
class Logos {
  static final Map<String, Future<File?>> _mem = {};

  static Future<File?> get(String iata) {
    final code = iata.toUpperCase().trim();
    if (!RegExp(r'^[A-Z0-9]{2}$').hasMatch(code)) return Future.value(null);
    return _mem.putIfAbsent(code, () => _load(code));
  }

  static Future<File?> _load(String code) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/logos/$code.png');
      if (await f.exists() && await f.length() > 200) return f;
      for (final url in [
        'https://img.wway.io/pics/root/$code@png?exar=1&rs=fit:160:160',
        'https://pics.avs.io/160/160/$code.png',
      ]) {
        try {
          final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
          final b = r.bodyBytes;
          final isImage = b.length > 200 &&
              ((b[0] == 0x89 && b[1] == 0x50) || (b[0] == 0xFF && b[1] == 0xD8) || (b[0] == 0x52 && b[1] == 0x49));
          if (r.statusCode == 200 && isImage) {
            await f.parent.create(recursive: true);
            await f.writeAsBytes(b);
            return f;
          }
        } catch (_) {}
      }
    } catch (_) {}
    return null;
  }
}
