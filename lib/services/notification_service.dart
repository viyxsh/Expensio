import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const _androidChannel = AndroidNotificationDetails(
    'expensio_reminders',
    'Expensio Reminders',
    channelDescription: 'Daily reminders from Expensio',
    importance: Importance.high,
    priority: Priority.high,
  );

  static Future<void> init() async {
    try {
      tz_data.initializeTimeZones();
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    } catch (e) {
      debugPrint('[Notifications] Timezone init error: $e');
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );
  }

  /// Returns true if permission was granted (or already granted)
  static Future<bool> requestPermission() async {
    try {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        return await ios.requestPermissions(
              alert: true, badge: true, sound: true,
            ) ??
            false;
      }
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }
      return true;
    } catch (e) {
      debugPrint('[Notifications] requestPermission error: $e');
      return false;
    }
  }

  static Future<void> scheduleSettlementReminder(bool enable) async {
    if (!enable) {
      await _plugin.cancel(1);
      return;
    }
    await _scheduleDailyAt(
      id: 1,
      title: 'Settle Up Reminder',
      body: 'You have pending settlements. Tap to review and settle.',
      hour: 20,
    );
  }

  static Future<void> scheduleDailyTransactionReminder(bool enable) async {
    if (!enable) {
      await _plugin.cancel(2);
      return;
    }
    await _scheduleDailyAt(
      id: 2,
      title: 'Log Today\'s Expenses',
      body: 'Don\'t forget to track today\'s transactions in Expensio.',
      hour: 21,
    );
  }

  static Future<void> _scheduleDailyAt({
    required int id,
    required String title,
    required String body,
    required int hour,
  }) async {
    try {
      final now = tz.TZDateTime.now(tz.local);
      var scheduled =
          tz.TZDateTime(tz.local, now.year, now.month, now.day, hour);
      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }

      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        const NotificationDetails(
          android: _androidChannel,
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      debugPrint('[Notifications] Scheduled id=$id at $hour:00 daily');
    } catch (e) {
      debugPrint('[Notifications] Schedule error: $e');
    }
  }
}
