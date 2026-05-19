// ─────────────────────────────────────────────────────────────────────────────
// models/models.dart  —  все дата-классы приложения
// ─────────────────────────────────────────────────────────────────────────────

class Group {
  final String id;    // числовой ID из URL (e.g. "82")
  final String name;  // отображаемое имя (e.g. "ЦС-82")
  final String url;   // файл (e.g. "cg82.htm")

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
  final String date;      // "20.05.2026"
  final String weekday;   // "Ср-1"
  final String pairNum;   // "1"
  final String time;      // "08.30-10.00"
  final String subject;   // "ПиТПМ"
  final String type;      // "Лаб." / "Лек" / ""
  final String room;      // "110"
  final String teacher;   // "Семёнов В.А."
  final int subgroup;     // 0=все, 1=первая, 2=вторая

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

  /// Ключ для сравнения (детектирование изменений)
  String get key => '$date-$pairNum-$subgroup';

  /// Подходит ли пара для указанной подгруппы
  bool matches(int userSubgroup) => subgroup == 0 || subgroup == userSubgroup;

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

  /// Ключ дня  "2026-05-20"
  String get dateKey {
    final d = fetchedAt;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Диапазон дат из самого расписания
  String get weekLabel {
    if (lessons.isEmpty) return 'Нет данных';
    final dates = lessons.map((l) => l.date).toSet().toList()..sort();
    return dates.length == 1 ? dates.first : '${dates.first} – ${dates.last}';
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
  final String subject;   // для контекста
  final String field;     // 'added' | 'removed' | 'subject' | 'room' | 'teacher' | 'time' | 'type'
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
