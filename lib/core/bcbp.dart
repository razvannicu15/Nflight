/// Parser for the IATA Bar Coded Boarding Pass (BCBP, Resolution 792)
/// string found in the PDF417 / Aztec / QR code of a boarding pass.
library;

class BcbpLeg {
  BcbpLeg({
    required this.pnr,
    required this.from,
    required this.to,
    required this.carrier,
    required this.flightNumber,
    required this.julianDay,
    required this.compartment,
    required this.seat,
    required this.sequence,
    this.frequentFlyer,
  });

  final String pnr;
  final String from;
  final String to;
  final String carrier;
  final String flightNumber;
  final int julianDay;
  final String compartment;
  final String seat;
  final String sequence;
  String? frequentFlyer;
}

class BcbpPass {
  BcbpPass({required this.passenger, required this.legs, this.issueYearDigit, this.issueJulianDay});

  /// "SURNAME/GIVEN" as printed in the code.
  final String passenger;
  final List<BcbpLeg> legs;
  final int? issueYearDigit;
  final int? issueJulianDay;

  /// "Given Surname" in title case.
  String get displayName => prettyName(passenger);
}

String prettyName(String raw) {
  final clean = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  final parts = clean.split('/');
  String tc(String s) => s.toLowerCase().replaceAllMapped(
      RegExp(r"(^|[ \-'])(\S)"), (m) => '${m[1]}${m[2]!.toUpperCase()}');
  // Strip titles that airlines append to the given name.
  String given = parts.length > 1 ? parts[1] : '';
  given = given.replaceAll(RegExp(r'\s*(MRS|MR|MS|MISS|MSTR|CHD|INF)$'), '');
  final surname = parts[0];
  return given.isEmpty ? tc(surname) : '${tc(given)} ${tc(surname)}';
}

int? _hex(String s) => int.tryParse(s.trim(), radix: 16);

/// Returns null when [data] is not a BCBP string.
BcbpPass? parseBcbp(String data) {
  try {
    return _parse(data);
  } catch (_) {
    return null;
  }
}

BcbpPass? _parse(String raw) {
  final s = raw.replaceAll('\r', '').replaceAll('\n', '');
  if (s.length < 60 || s[0] != 'M') return null;
  final legCount = int.tryParse(s[1]);
  if (legCount == null || legCount < 1 || legCount > 4) return null;
  final passenger = s.substring(2, 22).trim();

  int? issueYear;
  int? issueDay;
  final legs = <BcbpLeg>[];
  var pos = 23;
  for (var i = 0; i < legCount; i++) {
    if (pos + 37 > s.length) break;
    final f = s.substring(pos, pos + 35);
    final julian = int.tryParse(f.substring(21, 24).trim());
    final leg = BcbpLeg(
      pnr: f.substring(0, 7).trim(),
      from: f.substring(7, 10).trim().toUpperCase(),
      to: f.substring(10, 13).trim().toUpperCase(),
      carrier: f.substring(13, 16).trim().toUpperCase(),
      flightNumber: _flightNo(f.substring(16, 21)),
      julianDay: julian ?? 0,
      compartment: f.substring(24, 25).trim(),
      seat: _seat(f.substring(25, 29)),
      sequence: _seq(f.substring(29, 34)),
    );
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(leg.from) ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(leg.to)) {
      return null;
    }
    final varSize = _hex(s.substring(pos + 35, pos + 37)) ?? 0;
    final condStart = pos + 37;
    final condEnd = (condStart + varSize).clamp(0, s.length);
    final cond = s.substring(condStart, condEnd);
    var c = 0;
    if (i == 0 && cond.startsWith('>') && cond.length >= 4) {
      final uniqueSize = _hex(cond.substring(2, 4)) ?? 0;
      final unique = cond.substring(4, (4 + uniqueSize).clamp(0, cond.length));
      // passenger desc(1) source checkin(1) source issuance(1) date of issue(4)
      if (unique.length >= 7) {
        final d = unique.substring(3, 7);
        if (RegExp(r'^\d{4}$').hasMatch(d)) {
          issueYear = int.parse(d[0]);
          issueDay = int.parse(d.substring(1));
        }
      }
      c = 4 + uniqueSize;
    }
    // Repeated conditional section: size(2) + fields.
    if (c + 2 <= cond.length) {
      final repSize = _hex(cond.substring(c, c + 2)) ?? 0;
      final rep = cond.substring(c + 2, (c + 2 + repSize).clamp(0, cond.length));
      // airline numeric(3) doc serial(10) selectee(1) intl doc(1)
      // marketing carrier(3) FF airline(3) FF number(16)
      if (rep.length >= 37) {
        final ffAirline = rep.substring(18, 21).trim();
        final ffNumber = rep.substring(21, 37).trim();
        if (ffNumber.isNotEmpty) {
          leg.frequentFlyer = ffAirline.isEmpty ? ffNumber : '$ffAirline $ffNumber';
        }
      }
    }
    legs.add(leg);
    pos = condEnd;
  }
  if (legs.isEmpty) return null;
  return BcbpPass(
      passenger: passenger, legs: legs, issueYearDigit: issueYear, issueJulianDay: issueDay);
}

String _flightNo(String s) {
  final t = s.trim();
  final m = RegExp(r'^0*(\d+)([A-Z]?)$').firstMatch(t);
  if (m == null) return t;
  return '${m.group(1)}${m.group(2)}';
}

String _seat(String s) {
  final t = s.trim();
  final m = RegExp(r'^0*(\d+)([A-Z])$').firstMatch(t);
  if (m == null) return t;
  return '${m.group(1)}${m.group(2)}';
}

String _seq(String s) {
  final t = s.trim();
  final m = RegExp(r'^0*(\d+)').firstMatch(t);
  return m == null ? t : m.group(1)!;
}

/// Converts a day-of-year to a date. The year is taken from the date of
/// issue when the code carries it, otherwise the year that puts the flight
/// closest to [now].
DateTime resolveJulian(int day, {DateTime? now, int? issueYearDigit, int? issueJulianDay}) {
  final ref = now ?? DateTime.now();
  DateTime fromYear(int y) => DateTime(y, 1, 1).add(Duration(days: day - 1));
  if (issueYearDigit != null && issueJulianDay != null) {
    // Issue year: the latest year <= ref.year+1 ending in that digit.
    var y = ref.year + 1;
    while (y % 10 != issueYearDigit) {
      y--;
    }
    // Flight is on or after issue; it may roll into the next year.
    return fromYear(day < issueJulianDay ? y + 1 : y);
  }
  DateTime best = fromYear(ref.year);
  for (final y in [ref.year - 1, ref.year + 1]) {
    final d = fromYear(y);
    if ((d.difference(ref).inDays).abs() < (best.difference(ref).inDays).abs()) best = d;
  }
  return best;
}

const compartmentNames = {
  'F': 'First',
  'A': 'First',
  'J': 'Business',
  'C': 'Business',
  'D': 'Business',
  'I': 'Business',
  'Z': 'Business',
  'W': 'Premium Economy',
  'P': 'Premium Economy',
};

String cabinName(String code) =>
    code.isEmpty ? '' : (compartmentNames[code.toUpperCase()] ?? 'Economy');
