// ─────────────────────────────────────────────────────────────────────────────
// services/schedule_service.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as htmlParser;
import 'package:html/dom.dart' as dom;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:charset_converter/charset_converter.dart';
import '../models/models.dart';

const _base = 'https://biik.ru/rasp/';

class ScheduleService {
  // ── Сеть ──────────────────────────────────────────────────────────────────

  Future<Uint8List> _getBytes(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200)
      throw Exception('HTTP ${response.statusCode}');
    return response.bodyBytes;
  }

  Future<String> _get(String url) async {
    final bytes = await _getBytes(url);
    return CharsetConverter.decode('windows-1251', bytes);
  }

  // ── Группы ────────────────────────────────────────────────────────────────

  Future<List<Group>> fetchGroups() async {
    final html = await _get('${_base}cg.htm');
    final doc = htmlParser.parse(html);
    final groups = <Group>[];
    for (final a in doc.querySelectorAll('a[href]')) {
      final href = (a.attributes['href'] ?? '').trim();
      if (!RegExp(r'^cg\d+\.htm$', caseSensitive: false).hasMatch(href))
        continue;
      final id = href.replaceAll(RegExp(r'[^0-9]'), '');
      final name = _clean(a.text);
      if (name.isEmpty || id.isEmpty) continue;
      groups.add(Group(id: id, name: name, url: href));
    }
    return groups;
  }

  Future<List<Lesson>> fetchSchedule(String groupUrl) async {
    final html = await _get('$_base$groupUrl');
    return _parseHtml(html);
  }

  // ── Парсер ────────────────────────────────────────────────────────────────

  List<Lesson> _parseHtml(String html) {
    final doc = htmlParser.parse(html);
    final lessons = <Lesson>[];

    for (final table in doc.querySelectorAll('table')) {
      final rows = table.querySelectorAll('tr');
      if (rows.isEmpty) continue;

      String currentDate = '';
      String currentWeekday = '';

      for (final row in rows) {
        final cells = row.querySelectorAll('td');
        if (cells.isEmpty) continue;

        int ci = 0;

        final datePat = RegExp(r'\d{2}\.\d{2}\.\d{4}');
        final firstText = _clean(cells[0].text);
        if (datePat.hasMatch(firstText)) {
          currentDate = datePat.firstMatch(firstText)!.group(0)!;
          currentWeekday = firstText
              .replaceAll(currentDate, '')
              .replaceAll('<br>', '')
              .trim();
          ci = 1;
        }

        if (currentDate.isEmpty || cells.length <= ci) continue;

        final pairText = _clean(cells[ci].text);
        final pairMatch = RegExp(r'(\d)\s*[Пп]ара').firstMatch(pairText);
        final isNumOnly = RegExp(r'^\d$').hasMatch(pairText);
        if (pairMatch == null && !isNumOnly) continue;

        final isEmptyRow = row.querySelectorAll('td.nul').isNotEmpty ||
            cells.any((c) => (c.attributes['class'] ?? '').contains('nul'));
        if (isEmptyRow) continue;

        final pairNum = pairMatch?.group(1) ?? pairText;

        String time = '';
        final timeMatch = RegExp(r'(\d{2}[\.\:]\d{2})-(\d{2}[\.\:]\d{2})')
            .firstMatch(pairText);
        if (timeMatch != null) {
          time = '${timeMatch.group(1)}-${timeMatch.group(2)}';
        }
        ci++;

        if (cells.length <= ci) continue;

        final subjectCells = cells.sublist(ci);
        if (subjectCells.isEmpty) continue;

        final colspan0 =
            int.tryParse(subjectCells[0].attributes['colspan'] ?? '2') ?? 2;

        if (colspan0 == 2 || subjectCells.length == 1) {
          final lesson = _parseSubjectCell(
              subjectCells[0], currentDate, currentWeekday, pairNum, time, 0);
          if (lesson != null) lessons.add(lesson);
        } else {
          if (subjectCells.isNotEmpty) {
            final l1 = _parseSubjectCell(
                subjectCells[0], currentDate, currentWeekday, pairNum, time, 1);
            if (l1 != null) lessons.add(l1);
          }
          if (subjectCells.length > 1) {
            final l2 = _parseSubjectCell(
                subjectCells[1], currentDate, currentWeekday, pairNum, time, 2);
            if (l2 != null) lessons.add(l2);
          }
        }
      }
    }
    return lessons;
  }

  Lesson? _parseSubjectCell(dom.Element cell, String date, String weekday,
      String pairNum, String time, int subgroup) {
    final text = _clean(cell.text);
    if (text.isEmpty || text == '\u00a0' || text == '&nbsp;') return null;
    if ((cell.attributes['class'] ?? '').contains('nul')) return null;

    final subjectLink = cell.querySelector('a.z1');
    String subject = subjectLink != null ? _clean(subjectLink.text) : text;

    String type = '';
    final typeMatch = RegExp(r'\(([^)]+)\)').firstMatch(subject);
    if (typeMatch != null) {
      type = typeMatch.group(1)!;
      subject = subject.substring(0, typeMatch.start).trim();
    }

    final roomLink = cell.querySelector('a.z2');
    final room = roomLink != null ? _clean(roomLink.text) : '';

    final teacherLink = cell.querySelector('a.z3');
    final teacher = teacherLink != null ? _clean(teacherLink.text) : '';

    if (subject.isEmpty) return null;

    return Lesson(
      date: date,
      weekday: weekday,
      pairNum: pairNum,
      time: time,
      subject: subject,
      type: type,
      room: room,
      teacher: teacher,
      subgroup: subgroup,
    );
  }

  String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  // ── Ключ недели ───────────────────────────────────────────────────────────
  // Возвращает "YYYY-WNN" — ISO номер недели (Пн=начало)

  String weekKey(DateTime date) {
    // ISO week: находим понедельник текущей недели
    final monday = date.subtract(Duration(days: date.weekday - 1));
    final y = monday.year;
    final m = monday.month.toString().padLeft(2, '0');
    final d = monday.day.toString().padLeft(2, '0');
    // Используем дату понедельника как ключ для надёжности
    return '$y-$m-$d';
  }

  String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  String _todayWeekKey() => weekKey(DateTime.now());

  // ── Парсинг даты урока "DD.MM.YYYY" → DateTime ────────────────────────────

  DateTime? _parseDate(String date) {
    try {
      final p = date.split('.');
      if (p.length != 3) return null;
      return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
    } catch (_) {
      return null;
    }
  }

  // ── История по неделям ────────────────────────────────────────────────────

  /// Загружает снимок конкретной недели (ключ = "YYYY-MM-DD" понедельника)
  Future<ScheduleSnapshot?> loadWeekSnapshot(
      String groupId, String wKey) async {
    final raw = (await SharedPreferences.getInstance())
        .getString('week_${groupId}_$wKey');
    if (raw == null) return null;
    try {
      return ScheduleSnapshot.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  /// Сохраняет снимок недели. Перезаписывает если уже есть (обновление).
  Future<void> saveWeekSnapshot(
      String groupId, String wKey, ScheduleSnapshot snap) async {
    await (await SharedPreferences.getInstance())
        .setString('week_${groupId}_$wKey', jsonEncode(snap.toJson()));
    // Обновляем список ключей недель
    await _addWeekKey(groupId, wKey);
  }

  Future<void> _addWeekKey(String groupId, String wKey) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'week_keys_$groupId';
    final keys = prefs.getStringList(key) ?? [];
    if (!keys.contains(wKey)) {
      keys.add(wKey);
      keys.sort();
      // Храним максимум 12 недель
      final trimmed = keys.length > 12 ? keys.sublist(keys.length - 12) : keys;
      await prefs.setStringList(key, trimmed);
    }
  }

  /// Возвращает все сохранённые снимки недель, отсортированные по дате
  Future<List<ScheduleSnapshot>> loadWeekHistory(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getStringList('week_keys_$groupId') ?? [];
    final result = <ScheduleSnapshot>[];
    for (final wKey in keys) {
      final snap = await loadWeekSnapshot(groupId, wKey);
      if (snap != null) result.add(snap);
    }
    return result;
  }

  // ── Защита сегодняшнего дня ───────────────────────────────────────────────
  // Если на сайте сегодняшний день уже исчез — берём его из кэша текущей недели

  List<Lesson> mergeWithTodayProtection(
      List<Lesson> fresh, List<Lesson> cached) {
    final today = _todayKey();

    // Есть ли сегодня в свежих данных
    final todayInFresh =
        fresh.any((l) => l.date == _lessonDateKey(l.date, today));
    if (todayInFresh) return fresh; // всё хорошо, сайт ещё показывает сегодня

    // Сегодня исчез с сайта — берём из кэша
    final todayLessons = cached.where((l) {
      final d = _parseDate(l.date);
      if (d == null) return false;
      final dk =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      return dk == today;
    }).toList();

    if (todayLessons.isEmpty) return fresh;

    // Объединяем: свежие данные + сегодняшний день из кэша
    final merged = [...fresh, ...todayLessons];
    // Сортируем по дате и паре
    merged.sort((a, b) {
      final da = _parseDate(a.date);
      final db = _parseDate(b.date);
      if (da == null || db == null) return 0;
      final dateCmp = da.compareTo(db);
      if (dateCmp != 0) return dateCmp;
      return a.pairNum.compareTo(b.pairNum);
    });
    return merged;
  }

  String _lessonDateKey(String lessonDate, String todayKey) {
    final d = _parseDate(lessonDate);
    if (d == null) return '';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  // ── Главный метод обновления ───────────────────────────────────────────────
  // Возвращает итоговый список уроков для отображения

  Future<RefreshResult> refreshSchedule(String groupId, String groupUrl) async {
    final fresh = await fetchSchedule(groupUrl);
    final wKey = _todayWeekKey();

    // Загружаем текущий кэш недели
    final cached = await loadWeekSnapshot(groupId, wKey);
    final cachedLessons = cached?.lessons ?? [];

    // Защищаем сегодняшний день
    final merged = mergeWithTodayProtection(fresh, cachedLessons);

    // Создаём новый снимок
    final newSnap = ScheduleSnapshot(
      groupId: groupId,
      fetchedAt: DateTime.now(),
      lessons: merged,
    );

    // Детектируем изменения относительно кэша
    List<LessonChange> changes = [];
    if (cachedLessons.isNotEmpty) {
      changes = detectChanges(cachedLessons, merged);
    }

    // Сохраняем снимок недели (перезапись — всегда актуальные данные)
    await saveWeekSnapshot(groupId, wKey, newSnap);

    return RefreshResult(
      lessons: merged,
      changes: changes,
      weekKey: wKey,
    );
  }

  // ── Базовая линия дня (для детектирования изменений внутри дня) ───────────

  Future<ScheduleSnapshot?> loadTodaysBaseline(String groupId) async {
    final raw = (await SharedPreferences.getInstance())
        .getString('baseline_${groupId}_${_todayKey()}');
    if (raw == null) return null;
    try {
      return ScheduleSnapshot.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<bool> saveTodaysBaselineIfAbsent(
      String groupId, ScheduleSnapshot snap) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'baseline_${groupId}_${_todayKey()}';
    if (prefs.containsKey(key)) return false;
    await prefs.setString(key, jsonEncode(snap.toJson()));
    return true;
  }

  // ── Изменения ─────────────────────────────────────────────────────────────

  List<LessonChange> detectChanges(List<Lesson> baseline, List<Lesson> fresh) {
    final changes = <LessonChange>[];
    final now = DateTime.now();

    String lessonSig(Lesson l) => '${l.date}-${l.pairNum}-${l.subgroup}';

    final baseMap = <String, Lesson>{};
    for (final l in baseline) baseMap[lessonSig(l)] = l;

    final freshMap = <String, Lesson>{};
    for (final l in fresh) freshMap[lessonSig(l)] = l;

    for (final key in baseMap.keys) {
      final base = baseMap[key]!;
      final f = freshMap[key];
      if (f == null) {
        // Не добавляем "removed" для сегодняшнего дня — он защищён
        final d = _parseDate(base.date);
        if (d != null) {
          final dk =
              '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          if (dk == _todayKey()) continue; // сегодня не удаляем
        }
        changes.add(LessonChange(
          date: base.date,
          pairNum: base.pairNum,
          subject: base.subject,
          field: 'removed',
          oldValue:
              '${base.subject}${base.type.isNotEmpty ? ' (${base.type})' : ''} ауд.${base.room}',
          newValue: '—',
          detectedAt: now,
        ));
        continue;
      }
      void diff(String field, String o, String n) {
        if (o != n)
          changes.add(LessonChange(
            date: base.date,
            pairNum: base.pairNum,
            subject: base.subject,
            field: field,
            oldValue: o,
            newValue: n,
            detectedAt: now,
          ));
      }

      diff('subject', base.subject, f.subject);
      diff('type', base.type, f.type);
      diff('room', base.room, f.room);
      diff('teacher', base.teacher, f.teacher);
      diff('time', base.time, f.time);
    }

    for (final key in freshMap.keys) {
      if (!baseMap.containsKey(key)) {
        final f = freshMap[key]!;
        changes.add(LessonChange(
          date: f.date,
          pairNum: f.pairNum,
          subject: f.subject,
          field: 'added',
          oldValue: '—',
          newValue:
              '${f.subject}${f.type.isNotEmpty ? ' (${f.type})' : ''} ауд.${f.room}',
          detectedAt: now,
        ));
      }
    }
    return changes;
  }

  Future<List<LessonChange>> loadChanges(String groupId) async {
    final raw = (await SharedPreferences.getInstance())
            .getStringList('changes_$groupId') ??
        [];
    return raw
        .map((s) {
          try {
            return LessonChange.fromJson(jsonDecode(s));
          } catch (_) {
            return null;
          }
        })
        .whereType<LessonChange>()
        .toList();
  }

  Future<void> saveChanges(
      String groupId, List<LessonChange> newChanges) async {
    if (newChanges.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadChanges(groupId);

    String changeSig(LessonChange c) =>
        '${c.date}-${c.pairNum}-${c.field}-${c.oldValue}';
    final existingSigs = existing.map(changeSig).toSet();
    final toAdd =
        newChanges.where((c) => !existingSigs.contains(changeSig(c))).toList();
    if (toAdd.isEmpty) return;

    final all = [...existing, ...toAdd];
    final trimmed = all.length > 200 ? all.sublist(all.length - 200) : all;
    await prefs.setStringList(
      'changes_$groupId',
      trimmed.map((c) => jsonEncode(c.toJson())).toList(),
    );
  }

  Future<void> clearChanges(String groupId) async =>
      (await SharedPreferences.getInstance()).remove('changes_$groupId');

  // ── Настройки ─────────────────────────────────────────────────────────────

  Future<Group?> getSelectedGroup() async {
    final raw =
        (await SharedPreferences.getInstance()).getString('selected_group');
    if (raw == null) return null;
    try {
      return Group.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> setSelectedGroup(Group g) async =>
      (await SharedPreferences.getInstance())
          .setString('selected_group', jsonEncode(g.toJson()));

  Future<int> getSubgroup() async =>
      (await SharedPreferences.getInstance()).getInt('subgroup') ?? 1;

  Future<void> setSubgroup(int v) async =>
      (await SharedPreferences.getInstance()).setInt('subgroup', v);

  // ── Избранное ─────────────────────────────────────────────────────────────

  Future<List<Group>> getFavorites() async {
    final raw =
        (await SharedPreferences.getInstance()).getStringList('favorites') ??
            [];
    return raw
        .map((s) {
          try {
            return Group.fromJson(jsonDecode(s));
          } catch (_) {
            return null;
          }
        })
        .whereType<Group>()
        .toList();
  }

  Future<void> addFavorite(Group g) async {
    final prefs = await SharedPreferences.getInstance();
    final favs = await getFavorites();
    if (favs.any((f) => f.id == g.id)) return;
    favs.add(g);
    await prefs.setStringList(
        'favorites', favs.map((f) => jsonEncode(f.toJson())).toList());
  }

  Future<void> removeFavorite(Group g) async {
    final prefs = await SharedPreferences.getInstance();
    final favs = await getFavorites();
    favs.removeWhere((f) => f.id == g.id);
    await prefs.setStringList(
        'favorites', favs.map((f) => jsonEncode(f.toJson())).toList());
  }

  // ── Кэш групп ─────────────────────────────────────────────────────────────

  Future<List<Group>> getCachedGroups() async {
    final raw = (await SharedPreferences.getInstance())
            .getStringList('cached_groups') ??
        [];
    return raw
        .map((s) {
          try {
            return Group.fromJson(jsonDecode(s));
          } catch (_) {
            return null;
          }
        })
        .whereType<Group>()
        .toList();
  }

  Future<void> cacheGroups(List<Group> groups) async =>
      (await SharedPreferences.getInstance()).setStringList(
        'cached_groups',
        groups.map((g) => jsonEncode(g.toJson())).toList(),
      );
}

// ── Результат обновления ──────────────────────────────────────────────────────

class RefreshResult {
  final List<Lesson> lessons;
  final List<LessonChange> changes;
  final String weekKey;

  const RefreshResult({
    required this.lessons,
    required this.changes,
    required this.weekKey,
  });
}
