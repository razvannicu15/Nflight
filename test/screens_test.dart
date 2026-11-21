// Renders every screen to PNG for visual review (CI uploads them).
// Runs only when SCREEN_FONTS points to a folder with Roboto *.ttf files:
//   SCREEN_FONTS=/usr/share/fonts/truetype/roboto flutter test --update-goldens test/screens_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show debugDisableShadows;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nflight/core/airports.dart';
import 'package:nflight/core/i18n.dart';
import 'package:nflight/main.dart';
import 'package:nflight/models/pass.dart';
import 'package:nflight/services/store.dart';
import 'package:nflight/services/board_api.dart';
import 'package:nflight/ui/board_page.dart';
import 'package:nflight/ui/boarding_code_page.dart';
import 'package:nflight/ui/edit_pass_page.dart';
import 'package:nflight/ui/home_shell.dart';
import 'package:nflight/ui/pass_detail_page.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;

final fontsDir = Platform.environment['SCREEN_FONTS'];

Future<void> loadFonts() async {
  final roboto = FontLoader('Roboto');
  for (final f in Directory(fontsDir!).listSync(recursive: true)) {
    final n = f.path.toLowerCase();
    if (n.endsWith('.ttf') && n.contains('roboto') && !n.contains('condensed') && !n.contains('mono') && !n.contains('slab')) {
      final bytes = File(f.path).readAsBytesSync();
      roboto.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
  }
  await roboto.load();
  // Material icons ship with the Flutter SDK.
  final root = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)));
    await l.load();
  }
}

FlightPass demo(String from, String to, String carrier, String no, DateTime day,
    {String dep = '06:40', String arr = '08:15', String pax = 'Razvan Nicu', String seat = '12C',
    String gate = '', String term = '', FlightStatus st = FlightStatus.unknown, int delay = 0, String pnr = 'K7QF2M'}) {
  return FlightPass(
    from: from, to: to, carrier: carrier, flightNumber: no, date: ymd(day),
    departure: dep, arrival: arr, passenger: pax, pnr: pnr, seat: seat, cabin: 'Economy',
    sequence: '42', gate: gate, terminal: term, status: st, delayMinutes: delay, boarding: '06:05',
    barcode: 'M1NICU/RAZVAN         EK7QF2M CLJLTNW6 3141 330Y012C0042 100', barcodeFormat: 'pdf417',
  );
}

void seed() {
  store.boardAirports = ['CLJ', 'OTP', 'LTN'];
  store.boardAirport = 'CLJ';
  final now = DateTime.now();
  final d = DateTime(now.year, now.month, now.day);
  store.passes
    ..clear()
    ..addAll([
      demo('CLJ', 'LTN', 'W6', '3141', d.add(const Duration(days: 3)), term: '1', gate: 'A4', st: FlightStatus.scheduled),
      demo('CLJ', 'LTN', 'W6', '3141', d.add(const Duration(days: 3)), pax: 'Alex Nicu', seat: '12D'),
      demo('LTN', 'CLJ', 'W6', '3142', d.add(const Duration(days: 10)), dep: '21:10', arr: '02:30'),
      demo('OTP', 'FCO', 'RO', '403', d.add(const Duration(days: 24)), dep: '10:20', arr: '11:55', seat: '7A'),
      demo('CLJ', 'BGY', 'FR', '1234', d.subtract(const Duration(days: 40)), st: FlightStatus.landed, seat: '3F'),
      demo('BGY', 'CLJ', 'FR', '1235', d.subtract(const Duration(days: 33)), st: FlightStatus.landed, seat: '3A'),
      demo('OTP', 'IST', 'TK', '1044', d.subtract(const Duration(days: 120)), seat: '21C'),
      demo('IST', 'DXB', 'TK', '760', d.subtract(const Duration(days: 119)), dep: '01:45', arr: '07:10', seat: '34K'),
      demo('DXB', 'OTP', 'TK', '761', d.subtract(const Duration(days: 110)), seat: '30A'),
    ]);
}

Board demoBoard() {
  BoardFlight f(String no, String al, String to, String t, {String? rev, String gate = '', String st = 'expected'}) =>
      BoardFlight(number: no, airline: al, otherIata: to, otherName: Airports.city(to), scheduled: t,
          revised: rev, gate: gate, status: st);
  return Board([
    f('W6 3141', 'Wizz Air', 'LTN', '06:40', gate: 'A4', st: 'boarding'),
    f('W6 3301', 'Wizz Air', 'BVA', '07:05', gate: 'A2', st: 'departed'),
    f('RO 650', 'TAROM', 'OTP', '07:30', rev: '08:10', gate: 'B1', st: 'delayed'),
    f('LH 1665', 'Lufthansa', 'MUC', '08:15', gate: 'B3'),
    f('FR 1234', 'Ryanair', 'BGY', '09:00', st: 'canceled'),
    f('W6 3021', 'Wizz Air', 'DTM', '10:20'),
    f('OS 798', 'Austrian', 'VIE', '11:45'),
    f('W6 3445', 'Wizz Air', 'MAD', '12:10'),
  ], [], DateTime.now());
}

Widget app(Widget home, Brightness b) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: NflightApp.theme(b),
      home: home,
    );

Future<void> shot(WidgetTester t, String name, Widget home, {Brightness b = Brightness.light, Future<void> Function()? act}) async {
  await t.pumpWidget(const SizedBox()); // fresh state for every screen
  await t.pumpWidget(app(home, b));
  await t.pumpAndSettle();
  if (act != null) {
    await act();
    await t.pumpAndSettle();
  }
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('screens/$name.png'));
}

void main() {
  final skip = fontsDir == null;

  setUpAll(() async {
    if (skip) return;
    TestWidgetsFlutterBinding.ensureInitialized();
    debugDisableShadows = false; // real shadows, not the test outlines
    tzdata.initializeTimeZones();
    await loadFonts();
    await Airports.load();
  });

  for (final lang in ['ro', 'en']) {
    testWidgets('screens $lang', (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 2.625;
      addTearDown(t.view.reset);
      setLanguage(lang);
      seed();
      final id = store.upcoming.first.id;
      final pre = lang == 'ro' ? '' : 'en_';

      await shot(t, '${pre}01_trips', const HomeShell(startServices: false));
      await shot(t, '${pre}02_detail', PassDetailPage(passId: id));
      await shot(t, '${pre}03_stats', const HomeShell(startServices: false, initialTab: 3));
      if (lang == 'en') return;
      await shot(t, '04_trips_dark', const HomeShell(startServices: false), b: Brightness.dark);
      await shot(t, '05_detail_dark', PassDetailPage(passId: id), b: Brightness.dark);
      await shot(t, '06_stats_dark', const HomeShell(startServices: false, initialTab: 3), b: Brightness.dark);
      await shot(t, '07_history', const HomeShell(startServices: false, initialTab: 2));
      await shot(t, '08_settings', const HomeShell(startServices: false, initialTab: 4));
      await shot(t, '09_add_sheet', const HomeShell(startServices: false), act: () async {
        await t.tap(find.byType(FloatingActionButton));
      });
      await shot(t, '10_code', BoardingCodePage(passes: [store.upcoming.first, ...store.companions(store.upcoming.first)]));
      await shot(t, '10_code_dark', BoardingCodePage(passes: [store.upcoming.first, ...store.companions(store.upcoming.first)]),
          b: Brightness.dark);
      await shot(t, '13_board', BoardPage(preview: demoBoard()));
      await shot(t, '14_board_dark', BoardPage(preview: demoBoard()), b: Brightness.dark);
      await shot(t, '11_edit', EditPassPage(existing: store.upcoming.first));
      store.passes.clear();
      await shot(t, '12_empty', const HomeShell(startServices: false));
    }, skip: skip);
  }
}
