import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as htmlParser;
import 'package:html/dom.dart' as dom;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:charset_converter/charset_converter.dart';
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

// ─── Модель одной пары ────────────────────────────────────────────────────────

class Lesson {
  final String date;      // "20.05.2026"
  final String weekday;   // "Ср-1"
  final String pairNum;   // "1 Пара"
  final String time;      // "08.30-10.00"
  final String subject;   // "ПиТПМ"
  final String type;      // "Лаб." / "Лек" / ""
  final String room;      // "110"
  final String teacher;   // "Семёнов В.А."

  const Lesson({
    required this.date,
    required this.weekday,
    required this.pairNum,
    required this.time,
    required this.subject,
    required this.type,
    required this.room,
    required this.teacher,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'weekday': weekday,
        'pairNum': pairNum,
        'time': time,
        'subject': subject,
        'type': type,
        'room': room,
        'teacher': teacher,
      };

  factory Lesson.fromJson(Map<String, dynamic> j) => Lesson(
        date: j['date'] ?? '',
        weekday: j['weekday'] ?? '',
        pairNum: j['pairNum'] ?? '',
        time: j['time'] ?? '',
        subject: j['subject'] ?? '',
        type: j['type'] ?? '',
        room: j['room'] ?? '',
        teacher: j['teacher'] ?? '',
      );
}

// ─── Парсер ───────────────────────────────────────────────────────────────────

List<Lesson> parseSchedule(String html) {
  final document = htmlParser.parse(html);
  final List<Lesson> lessons = [];

  // Ищем все таблицы на странице
  final tables = document.querySelectorAll('table');

  for (final table in tables) {
    final rows = table.querySelectorAll('tr');
    if (rows.isEmpty) continue;

    String currentDate = '';
    String currentWeekday = '';

    for (final row in rows) {
      final cells = row.querySelectorAll('td');
      if (cells.isEmpty) continue;

      // Пробуем определить структуру строки
      // Сайт БИИК использует примерно такую структуру:
      // [Дата + день] [Пара №] [Время] [Предмет + аудитория] [Преподаватель]
      // Ячейка с датой имеет rowspan и появляется только в первой строке дня

      int cellIndex = 0;

      // Проверяем первую ячейку: это дата или уже пара?
      final firstCellText = _cleanText(cells[0].text);

      // Дата выглядит как "20.05.2026" или содержит точки в формате даты
      final datePattern = RegExp(r'\d{2}\.\d{2}\.\d{4}');
      if (datePattern.hasMatch(firstCellText)) {
        // Это строка с датой
        final dateMatch = datePattern.firstMatch(firstCellText);
        currentDate = dateMatch?.group(0) ?? firstCellText;
        // День недели — остаток текста ("Ср-1", "Пн-1" и т.д.)
        currentWeekday = firstCellText.replaceAll(currentDate, '').trim();
        cellIndex = 1;
      }

      if (cells.length <= cellIndex) continue;

      // Далее ищем номер пары
      final pairCell = cells.length > cellIndex ? cells[cellIndex] : null;
      if (pairCell == null) continue;
      final pairText = _cleanText(pairCell.text);

      // Пара — это "1 Пара", "2 Пара" и т.д.
      final pairPattern = RegExp(r'(\d)\s*[Пп]ара');
      if (!pairPattern.hasMatch(pairText) && !RegExp(r'^\d$').hasMatch(pairText)) {
        // Не похоже на номер пары — пропускаем строку
        // (заголовки таблицы и т.п.)
        continue;
      }

      final pairMatch = pairPattern.firstMatch(pairText);
      final pairNum = pairMatch != null
          ? '${pairMatch.group(1)} Пара'
          : '$pairText Пара';

      cellIndex++;

      // Время
      String time = '';
      if (cells.length > cellIndex) {
        time = _cleanText(cells[cellIndex].text);
        // Время выглядит как "08.30-10.00"
        if (!RegExp(r'\d+\.\d+').hasMatch(time)) {
          time = '';
        } else {
          cellIndex++;
        }
      }

      // Предмет + аудитория (обычно в одной ячейке)
      String subject = '';
      String type = '';
      String room = '';
      if (cells.length > cellIndex) {
        final subjectCell = cells[cellIndex];
        final rawSubject = _cleanText(subjectCell.text);
        // Парсим: "ПиТПМ (Лаб.) 110"
        final subjectParsed = _parseSubject(rawSubject);
        subject = subjectParsed['subject'] ?? rawSubject;
        type = subjectParsed['type'] ?? '';
        room = subjectParsed['room'] ?? '';
        cellIndex++;
      }

      // Преподаватель
      String teacher = '';
      if (cells.length > cellIndex) {
        teacher = _cleanText(cells[cellIndex].text);
        cellIndex++;
      }

      // Если предмет пустой — пропускаем (пустая пара)
      if (subject.isEmpty || currentDate.isEmpty) continue;

      lessons.add(Lesson(
        date: currentDate,
        weekday: currentWeekday,
        pairNum: pairNum,
        time: time,
        subject: subject,
        type: type,
        room: room,
        teacher: teacher,
      ));
    }
  }

  return lessons;
}

String _cleanText(String text) {
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

Map<String, String> _parseSubject(String raw) {
  // Формат: "Название (Тип) Аудитория"
  // Тип: Лек, Лаб., Пр. и т.д.
  final typePattern = RegExp(r'\(([^)]+)\)');
  final roomPattern = RegExp(r'\b(\d{3,4}[а-яА-Яa-zA-Z]?)\b');

  String subject = raw;
  String type = '';
  String room = '';

  final typeMatch = typePattern.firstMatch(raw);
  if (typeMatch != null) {
    type = typeMatch.group(1) ?? '';
    subject = raw.substring(0, typeMatch.start).trim();
  }

  final roomMatch = roomPattern.firstMatch(raw);
  if (roomMatch != null) {
    room = roomMatch.group(1) ?? '';
    // Убираем номер аудитории из конца строки предмета
    subject = subject.replaceAll(roomMatch.group(0)!, '').trim();
  }

  return {'subject': subject, 'type': type, 'room': room};
}

// ─── Приложение ───────────────────────────────────────────────────────────────

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'БИИК Расписание',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const RaspPage(),
    );
  }
}

class RaspPage extends StatefulWidget {
  const RaspPage({super.key});

  @override
  State<RaspPage> createState() => _RaspPageState();
}

class _RaspPageState extends State<RaspPage> {
  List<Lesson> _lessons = [];
  bool _loading = false;
  String _status = '';

  // ─── Загрузка с сайта ──────────────────────────────────────────────────────

  Future<void> _fetchSchedule() async {
    setState(() {
      _loading = true;
      _status = 'Загрузка...';
    });

    try {
      final response = await http.get(
        Uri.parse('https://biik.ru/rasp/cg82.htm'),
      );

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final decoded = await CharsetConverter.decode('windows-1251', bytes);
        final lessons = parseSchedule(decoded);

        // Сохраняем в кэш
        final prefs = await SharedPreferences.getInstance();
        final jsonList = lessons.map((l) => jsonEncode(l.toJson())).toList();
        await prefs.setStringList('schedule_v2', jsonList);

        setState(() {
          _lessons = lessons;
          _status = 'Обновлено: ${_nowFormatted()}';
        });
      } else {
        setState(() {
          _status = 'Ошибка сервера: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Ошибка: $e';
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  // ─── Загрузка из кэша ──────────────────────────────────────────────────────

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('schedule_v2');
    if (saved != null && saved.isNotEmpty) {
      final lessons =
          saved.map((s) => Lesson.fromJson(jsonDecode(s))).toList();
      setState(() {
        _lessons = lessons;
        _status = 'Загружено из кэша';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  String _nowFormatted() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}.'
        '${now.month.toString().padLeft(2, '0')}.'
        '${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
  }

  // ─── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Группируем пары по дате
    final Map<String, List<Lesson>> byDate = {};
    for (final l in _lessons) {
      byDate.putIfAbsent(l.date, () => []).add(l);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: const Text(
          'БИИК Расписание',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Container(
            color: const Color(0xFF1565C0),
            padding: const EdgeInsets.only(bottom: 8, left: 16),
            alignment: Alignment.centerLeft,
            child: Text(
              _status,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _lessons.isEmpty
              ? _buildEmpty()
              : _buildList(byDate),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _fetchSchedule,
        icon: const Icon(Icons.refresh),
        label: const Text('Обновить'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_today_outlined,
              size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('Нет данных',
              style: TextStyle(fontSize: 18, color: Colors.grey[600])),
          const SizedBox(height: 8),
          Text('Нажмите «Обновить» для загрузки',
              style: TextStyle(color: Colors.grey[400])),
        ],
      ),
    );
  }

  Widget _buildList(Map<String, List<Lesson>> byDate) {
    final dates = byDate.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: dates.length,
      itemBuilder: (context, i) {
        final date = dates[i];
        final dayLessons = byDate[date]!;
        final weekday = dayLessons.first.weekday;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок дня
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1565C0),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      date,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (weekday.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      weekday,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Карточки пар
            ...dayLessons.map((lesson) => _LessonCard(lesson: lesson)),
            const SizedBox(height: 4),
          ],
        );
      },
    );
  }
}

// ─── Карточка пары ────────────────────────────────────────────────────────────

class _LessonCard extends StatelessWidget {
  final Lesson lesson;

  const _LessonCard({required this.lesson});

  Color _typeColor(String type) {
    final t = type.toLowerCase();
    if (t.contains('лаб')) return const Color(0xFF6A1B9A);
    if (t.contains('лек')) return const Color(0xFF1565C0);
    if (t.contains('пр')) return const Color(0xFF00695C);
    return const Color(0xFF37474F);
  }

  @override
  Widget build(BuildContext context) {
    final typeColor = _typeColor(lesson.type);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Левая полоска с номером пары
            Container(
              width: 52,
              decoration: BoxDecoration(
                color: typeColor.withOpacity(0.12),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    lesson.pairNum.replaceAll(' Пара', ''),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: typeColor,
                    ),
                  ),
                  Text(
                    'пара',
                    style: TextStyle(
                      fontSize: 10,
                      color: typeColor.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            // Основной контент
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Время + тип + аудитория
                    Row(
                      children: [
                        if (lesson.time.isNotEmpty) ...[
                          Icon(Icons.access_time,
                              size: 13, color: Colors.grey[500]),
                          const SizedBox(width: 3),
                          Text(
                            lesson.time,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (lesson.type.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: typeColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: typeColor.withOpacity(0.4)),
                            ),
                            child: Text(
                              lesson.type,
                              style: TextStyle(
                                fontSize: 11,
                                color: typeColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        const Spacer(),
                        if (lesson.room.isNotEmpty)
                          Row(
                            children: [
                              Icon(Icons.meeting_room_outlined,
                                  size: 13, color: Colors.grey[500]),
                              const SizedBox(width: 3),
                              Text(
                                lesson.room,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    // Название предмета
                    Text(
                      lesson.subject,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    // Преподаватель
                    if (lesson.teacher.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.person_outline,
                              size: 13, color: Colors.grey[500]),
                          const SizedBox(width: 3),
                          Text(
                            lesson.teacher,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}