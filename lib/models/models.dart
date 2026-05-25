// ─────────────────────────────────────────────────────────────────────────────
// models/models.dart  —  все дата-классы приложения
// ─────────────────────────────────────────────────────────────────────────────

class Group {
  final String id;
  final String name;
  final String url;

  const Group({required this.id, required this.name, required this.url});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'url': url};

  factory Group.fromJson(Map<String, dynamic> j) =>
      Group(id: j['id'] ?? '', name: j['name'] ?? '', url: j['url'] ?? '');

  @override
  bool operator ==(Object other) => other is Group && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => name;
}

// ─────────────────────────────────────────────────────────────────────────────

class Lesson {
  final String date; // "20.05.2026"
  final String weekday; // "Ср-1"
  final String pairNum; // "1"
  final String time; // "08.30-10.00"
  final String subject;
  final String type;
  final String room;
  final String teacher;
  final int subgroup; // 0=все, 1=первая, 2=вторая

  const Lesson({
    required this.date,
    required this.weekday,
    required this.pairNum,
    required this.time,
    required this.subject,
    required this.type,
    required this.room,
    required this.teacher,
    this.subgroup = 0,
  });

  String get key => '$date-$pairNum-$subgroup';

  bool matches(int userSubgroup) =>
      userSubgroup == 0 || subgroup == 0 || subgroup == userSubgroup;

  /// Парсит дату "DD.MM.YYYY" в DateTime для сортировки
  DateTime? get parsedDate {
    try {
      final p = date.split('.');
      if (p.length != 3) return null;
      return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'weekday': weekday,
        'pairNum': pairNum,
        'time': time,
        'subject': subject,
        'type': type,
        'room': room,
        'teacher': teacher,
        'subgroup': subgroup,
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
        subgroup: j['subgroup'] ?? 0,
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class ScheduleSnapshot {
  final String groupId;
  final DateTime fetchedAt;
  final List<Lesson> lessons;

  const ScheduleSnapshot({
    required this.groupId,
    required this.fetchedAt,
    required this.lessons,
  });

  String get dateKey {
    final d = fetchedAt;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Диапазон дат недели, отсортированный правильно: "19.05 – 25.05"
  String get weekLabel {
    if (lessons.isEmpty) return 'Нет данных';
    final parsed =
        lessons.map((l) => l.parsedDate).whereType<DateTime>().toList();
    if (parsed.isEmpty) return 'Нет данных';
    parsed.sort((a, b) => a.compareTo(b));
    final first = parsed.first;
    final last = parsed.last;

    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

    return first == last ? fmt(first) : '${fmt(first)} – ${fmt(last)}';
  }

  Map<String, dynamic> toJson() => {
        'groupId': groupId,
        'fetchedAt': fetchedAt.toIso8601String(),
        'lessons': lessons.map((l) => l.toJson()).toList(),
      };

  factory ScheduleSnapshot.fromJson(Map<String, dynamic> j) => ScheduleSnapshot(
        groupId: j['groupId'] ?? '',
        fetchedAt: DateTime.tryParse(j['fetchedAt'] ?? '') ?? DateTime.now(),
        lessons: ((j['lessons'] as List?) ?? [])
            .map((l) => Lesson.fromJson(l as Map<String, dynamic>))
            .toList(),
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class LessonChange {
  final String date;
  final String pairNum;
  final String subject;
  final String field;
  final String oldValue;
  final String newValue;
  final DateTime detectedAt;

  const LessonChange({
    required this.date,
    required this.pairNum,
    required this.subject,
    required this.field,
    required this.oldValue,
    required this.newValue,
    required this.detectedAt,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'pairNum': pairNum,
        'subject': subject,
        'field': field,
        'oldValue': oldValue,
        'newValue': newValue,
        'detectedAt': detectedAt.toIso8601String(),
      };

  factory LessonChange.fromJson(Map<String, dynamic> j) => LessonChange(
        date: j['date'] ?? '',
        pairNum: j['pairNum'] ?? '',
        subject: j['subject'] ?? '',
        field: j['field'] ?? '',
        oldValue: j['oldValue'] ?? '',
        newValue: j['newValue'] ?? '',
        detectedAt: DateTime.tryParse(j['detectedAt'] ?? '') ?? DateTime.now(),
      );
}
