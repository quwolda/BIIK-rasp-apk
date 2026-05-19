// ─────────────────────────────────────────────────────────────────────────────
// widgets/lesson_card.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../models/models.dart';

class LessonCard extends StatelessWidget {
  final Lesson lesson;
  final bool dimmed; // для пар другой подгруппы

  const LessonCard({super.key, required this.lesson, this.dimmed = false});

  Color _typeColor(String type) {
    final t = type.toLowerCase();
    if (t.contains('лаб')) return const Color(0xFF6A1B9A);
    if (t.contains('лек')) return const Color(0xFF1565C0);
    if (t.contains('пр'))  return const Color(0xFF00695C);
    return const Color(0xFF37474F);
  }

  @override
  Widget build(BuildContext context) {
    final typeColor = _typeColor(lesson.type);

    return Opacity(
      opacity: dimmed ? 0.45 : 1.0,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        elevation: dimmed ? 0 : 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Левая цветная полоска с номером пары
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
                      lesson.pairNum,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: typeColor,
                      ),
                    ),
                    Text(
                      'пара',
                      style: TextStyle(fontSize: 10, color: typeColor.withOpacity(0.7)),
                    ),
                    if (lesson.subgroup != 0) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: typeColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${lesson.subgroup}п/г',
                          style: TextStyle(fontSize: 9, color: typeColor),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Основной контент
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Строка: время + тип + аудитория
                      Row(
                        children: [
                          if (lesson.time.isNotEmpty) ...[
                            Icon(Icons.access_time, size: 13, color: Colors.grey[500]),
                            const SizedBox(width: 3),
                            Text(
                              lesson.time,
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (lesson.type.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: typeColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: typeColor.withOpacity(0.4)),
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
                                    fontWeight: FontWeight.w500,
                                  ),
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
                            Icon(Icons.person_outline, size: 13, color: Colors.grey[500]),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                lesson.teacher,
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                overflow: TextOverflow.ellipsis,
                              ),
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
      ),
    );
  }
}
