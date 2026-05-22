// ─────────────────────────────────────────────────────────────────────────────
// services/notification_service.dart
// Планирование уведомлений о парах
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  // ── Инициализация ──────────────────────────────────────────────────────────

  static Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();

    tz.setLocalLocation(tz.getLocation('Asia/Irkutsk')); // UTC+8

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(settings);
    _initialized = true;
  }

  // ── Запрос разрешения (Android 13+) ───────────────────────────────────────

  static Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    return granted ?? false;
  }

  // ── "Сегодня дома" ────────────────────────────────────────────────────────

  static Future<bool> isHomeTodayEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'home_today_${_todayKey()}';
    return prefs.getBool(key) ?? false;
  }

  static Future<void> setHomeToday(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'home_today_${_todayKey()}';
    await prefs.setBool(key, value);
    if (value) {
      await cancelTodayNotifications();
    }
  }

  static String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  // ── Планирование уведомлений ──────────────────────────────────────────────

  /// Планирует уведомления для всех пар в списке.
  /// Уведомление приходит за 5 минут до конца пары.
  static Future<void> scheduleAll(List<Lesson> lessons, int subgroup) async {
    await init();

    if (await isHomeTodayEnabled()) return;

    // Фильтруем по подгруппе
    final filtered = subgroup == 0
        ? lessons
        : lessons
            .where((l) => l.subgroup == 0 || l.subgroup == subgroup)
            .toList();

    // Группируем по дате
    final Map<String, List<Lesson>> byDate = {};
    for (final l in filtered) {
      if (l.time.isEmpty) continue;
      byDate.putIfAbsent(l.date, () => []).add(l);
    }

    // Отменяем старые уведомления перед перепланированием
    await _plugin.cancelAll();

    int notifId = 0;

    for (final date in byDate.keys) {
      final dayLessons = byDate[date]!;
      dayLessons.sort((a, b) => a.pairNum.compareTo(b.pairNum));

      for (int i = 0; i < dayLessons.length; i++) {
        final lesson = dayLessons[i];
        final endTime = _parseEndTime(lesson.date, lesson.time);
        if (endTime == null) continue;

        final notifyAt = endTime.subtract(const Duration(minutes: 5));
        if (notifyAt.isBefore(DateTime.now())) continue;

        final next = i + 1 < dayLessons.length ? dayLessons[i + 1] : null;

        final title = '${lesson.subject} заканчивается через 5 мин.';
        final body = next != null
            ? 'Следующая: ${next.subject}${next.room.isNotEmpty ? ' — ауд. ${next.room}' : ''}'
            : 'Больше пар сегодня нет. Хорошего вечера!';

        await _scheduleNotification(
          id: notifId++,
          title: title,
          body: body,
          scheduledAt: notifyAt,
        );
      }
    }
  }

  static Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledAt,
  }) async {
    final tzTime = tz.TZDateTime.from(scheduledAt, tz.local);

    const androidDetails = AndroidNotificationDetails(
      'biik_lessons',
      'Пары',
      channelDescription: 'Уведомления об окончании пар',
      importance: Importance.high,
      priority: Priority.high,
    );

    // flutter_local_notifications 18.x требует uiLocalNotificationDateInterpretation
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzTime,
      const NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Отменяет все уведомления (для кнопки "Сегодня дома")
  static Future<void> cancelTodayNotifications() async {
    await _plugin.cancelAll();
  }

  // ── Парсинг времени ───────────────────────────────────────────────────────

  /// Парсит конец пары из строки вида "08.30-10.00" и даты "20.05.2026"
  static DateTime? _parseEndTime(String date, String time) {
    try {
      final dateParts = date.split('.');
      if (dateParts.length != 3) return null;
      final day = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final year = int.parse(dateParts[2]);

      // Время может быть "08.30-10.00" или "08:30-10:00"
      final normalized = time.replaceAll('.', ':');
      final timeParts = normalized.split('-');
      if (timeParts.length != 2) return null;

      final endParts = timeParts[1].split(':');
      if (endParts.length != 2) return null;

      final hour = int.parse(endParts[0]);
      final minute = int.parse(endParts[1]);

      return DateTime(year, month, day, hour, minute);
    } catch (_) {
      return null;
    }
  }
}
