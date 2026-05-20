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

  // ── Архив ─────────────────────────────────────────────────────────────────
  // URL архива строится как vgNN.htm где NN — id группы

  Future<List<String>> fetchArchiveUrls(String groupId) async {
    // Прямой URL архива группы
    final directUrl = 'vg$groupId.htm';
    try {
      final html = await _get('$_base$directUrl');
      // Парсим ссылки на конкретные недели внутри архива
      final doc = htmlParser.parse(html);
      final urls = <String>[];
      for (final a in doc.querySelectorAll('a[href]')) {
        final href = (a.attributes['href'] ?? '').trim();
        // Ссылки вида vgNN_1.htm, vgNN_2.htm и т.д.
        if (RegExp(r'^vg\d+.*\.htm$', caseSensitive: false).hasMatch(href)) {
          urls.add(href);
        }
      }
      // Если внутри нет подссылок — сам файл и есть архив
      if (urls.isEmpty) urls.add(directUrl);
      return urls.reversed.toList(); // новые первыми
    } catch (_) {
      return [];
    }
  }

  Future<List<Lesson>> fetchArchiveSchedule(String archiveUrl) async {
    final html = await _get('$_base$archiveUrl');
    return _parseHtml(html);
  }

  // ── Парсер ────────────────────────────────────────────────────────────────
  // Структура таблицы:
  // TR > TD(дата, rowspan) | TD(пара+время) | TD(colspan=2, вся группа)
  //                                         | TD(colspan=1) TD(colspan=1) — подгруппы

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

        // Ячейка с датой (rowspan, содержит ДД.ММ.ГГГГ)
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

        // Ячейка с номером пары и временем
        final pairText = _clean(cells[ci].text);
        final pairMatch = RegExp(r'(\d)\s*[Пп]ара').firstMatch(pairText);
        final isNumOnly = RegExp(r'^\d$').hasMatch(pairText);
        if (pairMatch == null && !isNumOnly) continue;

        // Пустые пары (class=nul)
        final isEmptyRow = row.querySelectorAll('td.nul').isNotEmpty ||
            cells.any((c) => (c.attributes['class'] ?? '').contains('nul'));
        if (isEmptyRow) continue;

        final pairNum = pairMatch?.group(1) ?? pairText;

        // Время из той же ячейки
        String time = '';
        final timeMatch = RegExp(r'(\d{2}[\.\:]\d{2})-(\d{2}[\.\:]\d{2})')
            .firstMatch(pairText);
        if (timeMatch != null) {
          time = '${timeMatch.group(1)}-${timeMatch.group(2)}';
        }
        ci++;

        if (cells.length <= ci) continue;

        // Определяем подгруппы по colspan оставшихся ячеек
        final subjectCells = cells.sublist(ci);
        if (subjectCells.isEmpty) continue;

        final colspan0 =
            int.tryParse(subjectCells[0].attributes['colspan'] ?? '2') ?? 2;

        if (colspan0 == 2 || subjectCells.length == 1) {
          // Вся группа (подгруппа 0)
          final lesson = _parseSubjectCell(
              subjectCells[0], currentDate, currentWeekday, pairNum, time, 0);
          if (lesson != null) lessons.add(lesson);
        } else {
          // Две подгруппы рядом
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
    // Пропускаем пустые ячейки
    final text = _clean(cell.text);
    if (text.isEmpty || text == '\u00a0' || text == '&nbsp;') return null;
    if ((cell.attributes['class'] ?? '').contains('nul')) return null;

    // Предмет — первая ссылка z1
    final subjectLink = cell.querySelector('a.z1');
    String subject = subjectLink != null ? _clean(subjectLink.text) : text;

    // Тип занятия из скобок в названии: "(Лаб.)", "(Лек)", "(Практич.)"
    String type = '';
    final typeMatch = RegExp(r'\(([^)]+)\)').firstMatch(subject);
    if (typeMatch != null) {
      type = typeMatch.group(1)!;
      subject = subject.substring(0, typeMatch.start).trim();
    }

    // Аудитория — ссылка z2
    final roomLink = cell.querySelector('a.z2');
    final room = roomLink != null ? _clean(roomLink.text) : '';

    // Преподаватель — ссылка z3
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

  // ── SharedPreferences ─────────────────────────────────────────────────────

  Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  // ── Базовая линия дня (фиксируется один раз, не перезаписывается) ─────────

  Future<ScheduleSnapshot?> loadTodaysBaseline(String groupId) async {
    final raw = (await _p).getString('baseline_${groupId}_${_todayKey()}');
    if (raw == null) return null;
    try {
      return ScheduleSnapshot.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  /// Сохраняет базовую линию ТОЛЬКО если её ещё нет на сегодня
  Future<bool> saveTodaysBaselineIfAbsent(
      String groupId, ScheduleSnapshot snap) async {
    final prefs = await _p;
    final key = 'baseline_${groupId}_${_todayKey()}';
    if (prefs.containsKey(key)) return false; // уже есть — не перезаписываем
    await prefs.setString(key, jsonEncode(snap.toJson()));
    return true;
  }

  // ── История снимков ───────────────────────────────────────────────────────

  Future<List<ScheduleSnapshot>> loadHistory(String groupId) async {
    final raw = (await _p).getStringList('history_$groupId') ?? [];
    return raw
        .map((s) {
          try {
            return ScheduleSnapshot.fromJson(jsonDecode(s));
          } catch (_) {
            return null;
          }
        })
        .whereType<ScheduleSnapshot>()
        .toList();
  }

  Future<void> addToHistory(String groupId, ScheduleSnapshot snap) async {
    final prefs = await _p;
    final history = await loadHistory(groupId);
    if (history.any((h) => h.dateKey == snap.dateKey)) return; // дубликат
    history.add(snap);
    final trimmed =
        history.length > 60 ? history.sublist(history.length - 60) : history;
    await prefs.setStringList(
      'history_$groupId',
      trimmed.map((s) => jsonEncode(s.toJson())).toList(),
    );
  }

  // ── Изменения — без дубликатов ────────────────────────────────────────────

  List<LessonChange> detectChanges(List<Lesson> baseline, List<Lesson> fresh) {
    final changes = <LessonChange>[];
    final now = DateTime.now();

    // Ключ: дата + пара + подгруппа + предмет (чтобы не дублировать)
    String lessonSig(Lesson l) => '${l.date}-${l.pairNum}-${l.subgroup}';

    final baseMap = <String, Lesson>{};
    for (final l in baseline) baseMap[lessonSig(l)] = l;

    final freshMap = <String, Lesson>{};
    for (final l in fresh) freshMap[lessonSig(l)] = l;

    for (final key in baseMap.keys) {
      final base = baseMap[key]!;
      final f = freshMap[key];
      if (f == null) {
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
    final raw = (await _p).getStringList('changes_$groupId') ?? [];
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

  /// Сохраняет только новые изменения которых ещё нет в истории
  Future<void> saveChanges(
      String groupId, List<LessonChange> newChanges) async {
    if (newChanges.isEmpty) return;
    final prefs = await _p;
    final existing = await loadChanges(groupId);

    // Дедупликация по дата+пара+поле+старое значение
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
      (await _p).remove('changes_$groupId');

  // ── Настройки ─────────────────────────────────────────────────────────────

  Future<Group?> getSelectedGroup() async {
    final raw = (await _p).getString('selected_group');
    if (raw == null) return null;
    try {
      return Group.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> setSelectedGroup(Group g) async =>
      (await _p).setString('selected_group', jsonEncode(g.toJson()));

  Future<int> getSubgroup() async => (await _p).getInt('subgroup') ?? 1;

  Future<void> setSubgroup(int v) async => (await _p).setInt('subgroup', v);

  // ── Избранное ─────────────────────────────────────────────────────────────

  Future<List<Group>> getFavorites() async {
    final raw = (await _p).getStringList('favorites') ?? [];
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
    final prefs = await _p;
    final favs = await getFavorites();
    if (favs.any((f) => f.id == g.id)) return;
    favs.add(g);
    await prefs.setStringList(
        'favorites', favs.map((f) => jsonEncode(f.toJson())).toList());
  }

  Future<void> removeFavorite(Group g) async {
    final prefs = await _p;
    final favs = await getFavorites();
    favs.removeWhere((f) => f.id == g.id);
    await prefs.setStringList(
        'favorites', favs.map((f) => jsonEncode(f.toJson())).toList());
  }

  // ── Кэш групп ─────────────────────────────────────────────────────────────

  Future<List<Group>> getCachedGroups() async {
    final raw = (await _p).getStringList('cached_groups') ?? [];
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
      (await _p).setStringList(
        'cached_groups',
        groups.map((g) => jsonEncode(g.toJson())).toList(),
      );
}
