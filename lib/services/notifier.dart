import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/airlines.dart';
import '../core/airports.dart';
import '../models/pass.dart';
import 'store.dart';

/// Departure reminders and the "your pass is ready" notification.
class Notifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static void Function(String passId)? onOpen;
  static String? launchPassId;

  static const _channel = AndroidNotificationDetails(
    'flights',
    'Zboruri',
    channelDescription: 'Mementouri înainte de plecare și biletul de îmbarcare',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
  );

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) {
        final id = r.payload;
        if (id != null && id.isNotEmpty) onOpen?.call(id);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      launchPassId = launch!.notificationResponse?.payload;
    }
  }

  static Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  /// Stable notification ids per pass: base + 0..3.
  static int _base(FlightPass p) => (p.id.hashCode & 0x0FFFFFFF) * 4;

  static Future<void> cancel(FlightPass p) async {
    for (var i = 0; i < 4; i++) {
      await _plugin.cancel(_base(p) + i);
    }
  }

  static Future<void> rescheduleAll() async {
    await _plugin.cancelAll();
    for (final p in store.upcoming) {
      await schedule(p);
    }
  }

  static Future<void> schedule(FlightPass p) async {
    await cancel(p);
    if (p.archived || p.status == FlightStatus.cancelled) return;
    final dep = Store.departureOf(p).add(Duration(minutes: p.delayMinutes));
    final city = '${Airports.city(p.from)} → ${Airports.city(p.to)}';
    final airline = Airlines.name(p.carrier);
    final where = [
      if (p.terminal.isNotEmpty) 'Terminal ${p.terminal}',
      if (p.gate.isNotEmpty) 'Poarta ${p.gate}',
      if (p.seat.isNotEmpty) 'Loc ${p.seat}',
    ].join(' · ');
    final time = p.departure == null ? '' : ' la ${hmOf(p)}';

    final items = <(int, Duration, String, String)>[
      if (store.remind24h)
        (0, const Duration(hours: 24), 'Mâine zbori: ${p.flightCode}',
            '$city$time · $airline'),
      if (store.remind3h)
        (1, const Duration(hours: 3), '${p.flightCode} pleacă în 3 ore',
            [city, if (where.isNotEmpty) where].join(' · ')),
      if (store.remindBoarding)
        (2, const Duration(minutes: 45), 'Îmbarcare ${p.flightCode}',
            'Atinge ca să deschizi biletul${where.isEmpty ? '' : ' · $where'}'),
    ];
    for (final it in items) {
      final at = dep.subtract(it.$2);
      if (at.isBefore(DateTime.now())) continue;
      await _plugin.zonedSchedule(
        _base(p) + it.$1,
        it.$3,
        it.$4,
        tz.TZDateTime.from(at, tz.UTC),
        const NotificationDetails(android: _channel),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: p.id,
      );
    }
  }

  /// Immediate notification, e.g. when live status reports a change.
  static Future<void> showNow(FlightPass p, String title, String body) async {
    await _plugin.show(_base(p) + 3, title, body,
        const NotificationDetails(android: _channel), payload: p.id);
  }

  static String hmOf(FlightPass p) {
    if (p.departure == null) return '';
    if (p.delayMinutes <= 0) return p.departure!;
    return hm(p.departureWall.add(Duration(minutes: p.delayMinutes)));
  }
}
