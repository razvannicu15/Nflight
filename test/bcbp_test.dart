import 'package:flutter_test/flutter_test.dart';
import 'package:nflight/core/bcbp.dart';
import 'package:nflight/core/pkpass.dart';

String pad(String s, int n) => s.padRight(n).substring(0, n);
String hex2(int n) => n.toRadixString(16).toUpperCase().padLeft(2, '0');

/// Mandatory leg fields (35 chars) as in IATA Res. 792.
String leg(String pnr, String from, String to, String carrier, String flight, String julian, String cls,
        String seat, String seq) =>
    '${pad(pnr, 7)}$from$to${pad(carrier, 3)}${pad(flight, 5)}$julian$cls${pad(seat, 4)}${pad(seq, 5)}1';

void main() {
  test('IATA sample, one leg, no conditional data', () {
    const s = 'M1DESMARAIS/LUC       EABC123 YULFRAAC 0834 326J001A0025 100';
    final p = parseBcbp(s)!;
    expect(p.legs.length, 1);
    expect(p.displayName, 'Luc Desmarais');
    final l = p.legs.first;
    expect(l.pnr, 'ABC123');
    expect(l.from, 'YUL');
    expect(l.to, 'FRA');
    expect(l.carrier, 'AC');
    expect(l.flightNumber, '834');
    expect(l.julianDay, 326);
    expect(l.seat, '1A');
    expect(l.sequence, '25');
    expect(cabinName(l.compartment), 'Business');
  });

  test('two legs with unique + repeated conditional sections', () {
    const unique = '1WW6325BW6 '; // desc, src, src, issue date 6325, doc type, issuer
    final rep1 = '${pad('', 3)}${pad('', 10)}  ${pad('W6', 3)}${pad('W6', 3)}${pad('123456789', 16)}';
    final cond1 = '>5${hex2(unique.length)}$unique${hex2(rep1.length)}$rep1';
    final l1 = leg('XYZ12A', 'CLJ', 'LTN', 'W6', '3141', '330', 'Y', '012C', '0042');
    final l2 = leg('XYZ12A', 'LTN', 'OTP', 'W6', '0302', '332', 'Y', '007F', '0007');
    final s = 'M2${pad('POPESCU/ION MR', 20)}E$l1${hex2(cond1.length)}$cond1${l2}00';
    final p = parseBcbp(s)!;
    expect(p.displayName, 'Ion Popescu');
    expect(p.legs.length, 2);
    expect(p.issueYearDigit, 6);
    expect(p.issueJulianDay, 325);
    expect(p.legs[0].seat, '12C');
    expect(p.legs[0].frequentFlyer, 'W6 123456789');
    expect(p.legs[1].from, 'LTN');
    expect(p.legs[1].to, 'OTP');
    expect(p.legs[1].flightNumber, '302');
    expect(p.legs[1].seat, '7F');
    final d = resolveJulian(332, now: DateTime(2026, 11, 21), issueYearDigit: 6, issueJulianDay: 325);
    expect(d, DateTime(2026, 11, 28));
  });

  test('not a boarding pass', () {
    expect(parseBcbp('https://example.com/ticket/123'), isNull);
    expect(parseBcbp(''), isNull);
  });

  test('julian day picks the closest year', () {
    expect(resolveJulian(5, now: DateTime(2026, 12, 28)), DateTime(2027, 1, 5));
    expect(resolveJulian(360, now: DateTime(2027, 1, 3)), DateTime(2026, 12, 26));
  });

  test('time parsing from pass fields', () {
    expect(timeOf('14:35'), '14:35');
    expect(timeOf('2:05 PM'), '14:05');
    expect(timeOf('Boarding 06.10'), '06:10');
    expect(timeOf('—'), isNull);
  });
}
