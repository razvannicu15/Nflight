import 'package:flutter/material.dart';

class Airline {
  const Airline(this.name, this.color);
  final String name;
  final Color color;
}

const _airlines = <String, Airline>{
  'W6': Airline('Wizz Air', Color(0xFFC6007E)),
  'W4': Airline('Wizz Air Malta', Color(0xFFC6007E)),
  'W9': Airline('Wizz Air UK', Color(0xFFC6007E)),
  '5W': Airline('Wizz Air Abu Dhabi', Color(0xFFC6007E)),
  'FR': Airline('Ryanair', Color(0xFF073590)),
  'RK': Airline('Ryanair UK', Color(0xFF073590)),
  'AL': Airline('Malta Air', Color(0xFF073590)),
  'RO': Airline('TAROM', Color(0xFF1B3A6B)),
  'H4': Airline('HiSky', Color(0xFF00A3E0)),
  'H7': Airline('HiSky Europe', Color(0xFF00A3E0)),
  'DN': Airline('Dan Air', Color(0xFF0057B8)),
  'LH': Airline('Lufthansa', Color(0xFF05164D)),
  'OS': Airline('Austrian', Color(0xFFD81E05)),
  'LX': Airline('SWISS', Color(0xFFE2001A)),
  'SN': Airline('Brussels Airlines', Color(0xFF00235F)),
  'EW': Airline('Eurowings', Color(0xFF8A1B61)),
  'KL': Airline('KLM', Color(0xFF00A1DE)),
  'AF': Airline('Air France', Color(0xFF002157)),
  'BA': Airline('British Airways', Color(0xFF075AAA)),
  'U2': Airline('easyJet', Color(0xFFFF6600)),
  'EC': Airline('easyJet Europe', Color(0xFFFF6600)),
  'DS': Airline('easyJet Switzerland', Color(0xFFFF6600)),
  'TK': Airline('Turkish Airlines', Color(0xFFC70A0C)),
  'PC': Airline('Pegasus', Color(0xFFFDC300)),
  'LO': Airline('LOT', Color(0xFF11397E)),
  'A3': Airline('Aegean', Color(0xFF0B2F6B)),
  'AZ': Airline('ITA Airways', Color(0xFF0B1C4A)),
  'IB': Airline('Iberia', Color(0xFFD7192D)),
  'VY': Airline('Vueling', Color(0xFFFFCC00)),
  'TP': Airline('TAP Air Portugal', Color(0xFF00A651)),
  'SK': Airline('SAS', Color(0xFF000F6E)),
  'AY': Airline('Finnair', Color(0xFF0B1560)),
  'DY': Airline('Norwegian', Color(0xFFD81939)),
  'D8': Airline('Norwegian', Color(0xFFD81939)),
  'LS': Airline('Jet2', Color(0xFFE5242A)),
  'QR': Airline('Qatar Airways', Color(0xFF5C0632)),
  'EK': Airline('Emirates', Color(0xFFD71921)),
  'EY': Airline('Etihad', Color(0xFFBD8B13)),
  'FZ': Airline('flydubai', Color(0xFF1A3D6F)),
  'KM': Airline('KM Malta Airlines', Color(0xFFCF142B)),
  'OU': Airline('Croatia Airlines', Color(0xFF0B3B7A)),
  'JU': Airline('Air Serbia', Color(0xFF0A2A5E)),
  'FB': Airline('Bulgaria Air', Color(0xFF0E3A6D)),
  '9U': Airline('Air Moldova', Color(0xFF00529B)),
  'BT': Airline('airBaltic', Color(0xFF8CC63F)),
  'EI': Airline('Aer Lingus', Color(0xFF008566)),
  'UA': Airline('United', Color(0xFF002244)),
  'DL': Airline('Delta', Color(0xFF003366)),
  'AA': Airline('American Airlines', Color(0xFF0078D2)),
  'AC': Airline('Air Canada', Color(0xFFD22630)),
  'SQ': Airline('Singapore Airlines', Color(0xFF1D3C6E)),
  'CX': Airline('Cathay Pacific', Color(0xFF006564)),
  'TO': Airline('Transavia France', Color(0xFF00D66C)),
  'HV': Airline('Transavia', Color(0xFF00D66C)),
  'XQ': Airline('SunExpress', Color(0xFFF7A800)),
  'V7': Airline('Volotea', Color(0xFFC8102E)),
  'EN': Airline('Air Dolomiti', Color(0xFF0B3C6B)),
  'LG': Airline('Luxair', Color(0xFF00A3E0)),
  'MS': Airline('EgyptAir', Color(0xFF00205B)),
  'LY': Airline('El Al', Color(0xFF00305F)),
};

/// IATA -> ICAO airline designator, used for radio callsigns (W6 3141 -> WZZ3141).
const icaoAirline = {
  'W6': 'WZZ', 'W4': 'WMT', 'W9': 'WUK', '5W': 'WAZ', 'FR': 'RYR', 'RK': 'RUK', 'AL': 'MAY',
  'RO': 'ROT', 'H4': 'HYS', 'LH': 'DLH', 'OS': 'AUA', 'LX': 'SWR', 'SN': 'BEL', 'EW': 'EWG',
  'KL': 'KLM', 'AF': 'AFR', 'BA': 'BAW', 'U2': 'EZY', 'EC': 'EJU', 'DS': 'EZS', 'TK': 'THY',
  'PC': 'PGT', 'LO': 'LOT', 'A3': 'AEE', 'AZ': 'ITY', 'IB': 'IBE', 'VY': 'VLG', 'TP': 'TAP',
  'SK': 'SAS', 'AY': 'FIN', 'DY': 'NOZ', 'LS': 'EXS', 'QR': 'QTR', 'EK': 'UAE', 'EY': 'ETD',
  'FZ': 'FDB', 'KM': 'KMM', 'OU': 'CTN', 'JU': 'ASL', 'FB': 'LZB', 'BT': 'BTI', 'EI': 'EIN',
  'UA': 'UAL', 'DL': 'DAL', 'AA': 'AAL', 'AC': 'ACA', 'SQ': 'SIA', 'CX': 'CPA', 'TO': 'TVF',
  'HV': 'TRA', 'XQ': 'SXS', 'V7': 'VOE', 'EN': 'DLA', 'LG': 'LGL', 'MS': 'MSR', 'LY': 'ELY',
};

/// Best guess of the radio callsign; airlines sometimes use other ones.
String? guessCallsign(String carrier, String number) {
  final icao = icaoAirline[carrier.toUpperCase().trim()];
  final n = number.replaceAll(RegExp(r'\s'), '').replaceFirst(RegExp(r'^0+'), '');
  return icao == null || n.isEmpty ? null : '$icao$n';
}

class Airlines {
  static Airline? get(String code) => _airlines[code.toUpperCase().trim()];
  static String name(String code) => get(code)?.name ?? code;
  static Color color(String code, ColorScheme cs) => get(code)?.color ?? cs.primary;
}
