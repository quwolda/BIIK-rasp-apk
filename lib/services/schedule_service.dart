// ─────────────────────────────────────────────────────────────────────────────
// services/schedule_service.dart
// Сетевые запросы, парсинг HTML, хранение, настройки, детектирование изменений
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as htmlParser;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:charset_converter/charset_converter.dart';
import '../models/models.dart';
import 'dart:async';
import 'dart:typed_data';

const _base = 'https://biik.ru/rasp/';

class ScheduleService {
  // ── Сеть ────────────────────────────────────────────────────────────────────

  Future<Uint8List> _getBytes(String url) async {
    print('=== GET $url ===');
    final response = await http.get(
      Uri.parse(url),
      headers: {'User-Agent': 'Mozilla/5.0 (Android 14)'},
    ).timeout(const Duration(seconds: 15));
    print('=== response: ${response.statusCode} ===');
    if (response.statusCode != 200)
      throw Exception('HTTP ${response.statusCode}');
    return response.bodyBytes;
  }

  Future<String> _get(String url) async {
    final bytes = await _getBytes(url);
    return CharsetConverter.decode('windows-1251', bytes);
  }

  /// Список всех групп с cg.htm
  Future<List<Group>> fetchGroups() async {
    print('=== fetchGroups: start ===');
    final html = await _get('${_base}cg.htm');
    print('=== fetchGroups: got html, length=${html.length} ===');
    final doc = htmlParser.parse(html);
    final groups = <Group>[];

    for (final a in doc.querySelectorAll('a[href]')) {
      final href = (a.attributes['href'] ?? '').trim();
      // Ссылки вида cg82.htm
      if (!RegExp(r'^cg\d+\.htm$', caseSensitive: false).hasMatch(href))
        continue;
      final id = href.replaceAll(RegExp(r'[^0-9]'), '');
      final name = _clean(a.text);
      if (name.isEmpty || id.isEmpty) continue;
      groups.add(Group(id: id, name: name, url: href));
    }
    return groups;
  }

  /// Расписание конкретной группы (текущее)
  Future<List<Lesson>> fetchSchedule(String groupUrl) async {
    final html = await _get('$_base$groupUrl');
    return _parseHtml(html);
  }

  /// Ссылки на архивные расписания группы с vg.htm
  Future<List<String>> fetchArchiveUrls(String groupId) async {
    try {
      final html = await _get('${_base}vg.htm');
      final doc = htmlParser.parse(html);
      final urls = <String>[];
      for (final a in doc.querySelectorAll('a[href]')) {
        final href = (a.attributes['href'] ?? '').trim();
        if (href.contains('vg$groupId') || href.contains('vg_$groupId')) {
          urls.add(href);
        }
      }
      // Также проверяем общий паттерн vgNNNN.htm
      for (final a in doc.querySelectorAll('a[href]')) {
        final href = (a.attributes['href'] ?? '').trim();
        if (RegExp(r'^vg\d+.*\.htm$', caseSensitive: false).hasMatch(href) &&
            !urls.contains(href)) {
          urls.add(href);
        }
      }
      return urls;
    } catch (_) {
      return [];
    }
  }

  Future<List<Lesson>> fetchArchiveSchedule(String archiveUrl) async {
    final html = await _get('$_base$archiveUrl');
    return _parseHtml(html);
  }

  // ── Парсер ──────────────────────────────────────────────────────────────────

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
        final first = _clean(cells[0].text);

        // Ячейка с датой (содержит ДД.ММ.ГГГГ)
        final datePat = RegExp(r'\d{2}\.\d{2}\.\d{4}');
        if (datePat.hasMatch(first)) {
          currentDate = datePat.firstMatch(first)!.group(0)!;
          currentWeekday = first.replaceAll(currentDate, '').trim();
          ci = 1;
        }

        if (currentDate.isEmpty || cells.length <= ci) continue;

        // Номер пары
        final pairText = _clean(cells[ci].text);
        final pairMatch = RegExp(r'(\d)\s*[Пп]ара').firstMatch(pairText);
        final isNumeric = RegExp(r'^\d$').hasMatch(pairText);
        if (pairMatch == null && !isNumeric) continue;

        final pairNum = pairMatch?.group(1) ?? pairText;
        ci++;

        // Время
        String time = '';
        if (cells.length > ci) {
          final t = _clean(cells[ci].text);
          if (RegExp(r'\d+[\.\:]\d+').hasMatch(t)) {
            time = t;
            ci++;
          }
        }

        // Предмет + аудитория + подгруппа
        String subject = '', type = '', room = '';
        int subgroup = 0;
        if (cells.length > ci) {
          final p = _parseSubjectCell(_clean(cells[ci].text));
          subject = p['subject']!;
          type = p['type']!;
          room = p['room']!;
          subgroup = int.tryParse(p['subgroup']!) ?? 0;
          ci++;
        }

        // Преподаватель
        String teacher = '';
        if (cells.length > ci) teacher = _clean(cells[ci].text);

        if (subject.isEmpty) continue;

        lessons.add(Lesson(
          date: currentDate,
          weekday: currentWeekday,
          pairNum: pairNum,
          time: time,
          subject: subject,
          type: type,
          room: room,
          teacher: teacher,
          subgroup: subgroup,
        ));
      }
    }
    return lessons;
  }

  String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  Map<String, String> _parseSubjectCell(String raw) {
    String subject = raw;
    String type = '', room = '', subgroup = '0';

    // Подгруппа: "1 п/г", "2 п/г", "1 п.", "2 подгр."
    final sgMatch =
        RegExp(r'([12])\s*(?:п/г|п\.г\.|подгр\.?|п\.)').firstMatch(raw);
    if (sgMatch != null) {
      subgroup = sgMatch.group(1)!;
      subject = subject.replaceFirst(sgMatch.group(0)!, '').trim();
    }

    // Тип занятия: (Лек), (Лаб.), (Пр.) …
    final typeMatch = RegExp(r'\(([^)]+)\)').firstMatch(subject);
    if (typeMatch != null) {
      type = typeMatch.group(1)!;
      subject = subject.substring(0, typeMatch.start).trim();
    }

    // Аудитория: 3-4 цифры (возможно с буквой)
    final roomMatch = RegExp(r'\b(\d{3,4}[а-яА-Яa-zA-Z]?)\b').firstMatch(raw);
    if (roomMatch != null) {
      room = roomMatch.group(1)!;
      subject = subject.replaceFirst(room, '').trim();
    }

    return {
      'subject': subject,
      'type': type,
      'room': room,
      'subgroup': subgroup
    };
  }

  // ── SharedPreferences helper ─────────────────────────────────────────────

  Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  // ── Базовый снимок (сохраняется раз в день) ──────────────────────────────

  Future<ScheduleSnapshot?> loadTodaysBaseline(String groupId) async {
    final raw = (await _p).getString('baseline_${groupId}_${_todayKey()}');
    if (raw == null) return null;
    try {
      return ScheduleSnapshot.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveTodaysBaseline(String groupId, ScheduleSnapshot snap) async {
    await (await _p).setString(
      'baseline_${groupId}_${_todayKey()}',
      jsonEncode(snap.toJson()),
    );
  }

  // ── История снимков ──────────────────────────────────────────────────────

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

  /// Добавляет снимок в историю, избегая дубликатов по dateKey
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

  // ── Детектирование изменений ─────────────────────────────────────────────

  List<LessonChange> detectChanges(List<Lesson> baseline, List<Lesson> fresh) {
    final changes = <LessonChange>[];
    final now = DateTime.now();
    final baseMap = {for (final l in baseline) l.key: l};
    final freshMap = {for (final l in fresh) l.key: l};

    void chk(Lesson base, Lesson? f) {
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
        return;
      }
      void diff(String field, String o, String n) {
        if (o != n && n.isNotEmpty) {
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
      }

      diff('subject', base.subject, f.subject);
      diff('type', base.type, f.type);
      diff('room', base.room, f.room);
      diff('teacher', base.teacher, f.teacher);
      diff('time', base.time, f.time);
    }

    for (final key in baseMap.keys) chk(baseMap[key]!, freshMap[key]);

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

  Future<void> saveChanges(
      String groupId, List<LessonChange> newChanges) async {
    if (newChanges.isEmpty) return;
    final prefs = await _p;
    final existing = await loadChanges(groupId);
    final all = [...existing, ...newChanges];
    final trimmed = all.length > 200 ? all.sublist(all.length - 200) : all;
    await prefs.setStringList(
      'changes_$groupId',
      trimmed.map((c) => jsonEncode(c.toJson())).toList(),
    );
  }

  Future<void> clearChanges(String groupId) async =>
      (await _p).remove('changes_$groupId');

  // ── Настройки ────────────────────────────────────────────────────────────

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

  // ── Избранное ────────────────────────────────────────────────────────────

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

  // ── Кэш списка групп ────────────────────────────────────────────────────

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
