import 'dart:math';

enum FlightStatus { unknown, scheduled, delayed, boarding, departed, landed, cancelled, diverted }

const statusLabels = {
  FlightStatus.unknown: '',
  FlightStatus.scheduled: 'La timp',
  FlightStatus.delayed: 'Întârziat',
  FlightStatus.boarding: 'Îmbarcare',
  FlightStatus.departed: 'A decolat',
  FlightStatus.landed: 'A aterizat',
  FlightStatus.cancelled: 'Anulat',
  FlightStatus.diverted: 'Deviat',
};

/// One flight leg with its boarding pass. Times are local to the airport
/// (wall clock), kept as "yyyy-MM-ddTHH:mm" strings so they never shift
/// with the phone's time zone.
class FlightPass {
  FlightPass({
    String? id,
    required this.from,
    required this.to,
    required this.carrier,
    required this.flightNumber,
    required this.date,
    this.departure,
    this.arrival,
    this.passenger = '',
    this.pnr = '',
    this.seat = '',
    this.cabin = '',
    this.sequence = '',
    this.frequentFlyer = '',
    this.barcode = '',
    this.barcodeFormat = 'pdf417',
    this.gate = '',
    this.terminal = '',
    this.boarding,
    this.status = FlightStatus.unknown,
    this.delayMinutes = 0,
    this.aircraft = '',
    this.archived = false,
    this.note = '',
    DateTime? createdAt,
    this.statusCheckedAt,
  })  : id = id ?? _newId(),
        createdAt = createdAt ?? DateTime.now();

  final String id;
  String from;
  String to;
  String carrier;
  String flightNumber;

  /// Flight date, "yyyy-MM-dd" (local at departure airport).
  String date;

  /// "HH:mm" local at departure / arrival airport, when known.
  String? departure;
  String? arrival;
  String? boarding;

  String passenger;
  String pnr;
  String seat;
  String cabin;
  String sequence;
  String frequentFlyer;
  String barcode;
  String barcodeFormat;
  String gate;
  String terminal;
  FlightStatus status;
  int delayMinutes;
  String aircraft;
  bool archived;
  String note;
  final DateTime createdAt;
  DateTime? statusCheckedAt;

  String get flightCode => '$carrier $flightNumber';
  String get route => '$from → $to';

  DateTime get day {
    final p = date.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  /// Wall-clock departure at the origin airport (not converted).
  DateTime get departureWall {
    final d = day;
    final t = _hm(departure) ?? const (12, 0);
    return DateTime(d.year, d.month, d.day, t.$1, t.$2);
  }

  static (int, int)? _hm(String? s) {
    if (s == null) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s);
    if (m == null) return null;
    return (int.parse(m.group(1)!), int.parse(m.group(2)!));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': from,
        'to': to,
        'carrier': carrier,
        'flight': flightNumber,
        'date': date,
        'dep': departure,
        'arr': arrival,
        'boarding': boarding,
        'pax': passenger,
        'pnr': pnr,
        'seat': seat,
        'cabin': cabin,
        'seq': sequence,
        'ff': frequentFlyer,
        'code': barcode,
        'fmt': barcodeFormat,
        'gate': gate,
        'term': terminal,
        'status': status.name,
        'delay': delayMinutes,
        'ac': aircraft,
        'arch': archived,
        'note': note,
        'created': createdAt.toIso8601String(),
        'checked': statusCheckedAt?.toIso8601String(),
      };

  factory FlightPass.fromJson(Map<String, dynamic> j) => FlightPass(
        id: j['id'] as String?,
        from: j['from'] ?? '',
        to: j['to'] ?? '',
        carrier: j['carrier'] ?? '',
        flightNumber: j['flight'] ?? '',
        date: j['date'] ?? '2000-01-01',
        departure: j['dep'],
        arrival: j['arr'],
        boarding: j['boarding'],
        passenger: j['pax'] ?? '',
        pnr: j['pnr'] ?? '',
        seat: j['seat'] ?? '',
        cabin: j['cabin'] ?? '',
        sequence: j['seq'] ?? '',
        frequentFlyer: j['ff'] ?? '',
        barcode: j['code'] ?? '',
        barcodeFormat: j['fmt'] ?? 'pdf417',
        gate: j['gate'] ?? '',
        terminal: j['term'] ?? '',
        status: FlightStatus.values.firstWhere((s) => s.name == j['status'],
            orElse: () => FlightStatus.unknown),
        delayMinutes: (j['delay'] as num?)?.toInt() ?? 0,
        aircraft: j['ac'] ?? '',
        archived: j['arch'] == true,
        note: j['note'] ?? '',
        createdAt: DateTime.tryParse(j['created'] ?? ''),
        statusCheckedAt: DateTime.tryParse(j['checked'] ?? ''),
      );

  /// Same physical flight for the same passenger (to avoid duplicates).
  bool sameAs(FlightPass o) =>
      o.carrier == carrier &&
      o.flightNumber == flightNumber &&
      o.date == date &&
      o.from == from &&
      o.passenger.toLowerCase() == passenger.toLowerCase();
}

final _rnd = Random();
String _newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rnd.nextInt(1 << 20).toRadixString(36)}';

String two(int n) => n.toString().padLeft(2, '0');
String ymd(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
String hm(DateTime d) => '${two(d.hour)}:${two(d.minute)}';
