// ─────────────────────────────────────────────────────────────────────────────
// widgets/day_header.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

class DayHeader extends StatelessWidget {
  final String date;
  final String weekday;

  const DayHeader({super.key, required this.date, required this.weekday});

  bool get _isToday {
    final now = DateTime.now();
    final today =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
    return date == today;
  }

  @override
  Widget build(BuildContext context) {
    final today = _isToday;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          // Бейдж с датой
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: today ? const Color(0xFF1565C0) : const Color(0xFF1565C0).withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              date,
              style: TextStyle(
                color: today ? Colors.white : const Color(0xFF1565C0),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // День недели
          if (weekday.isNotEmpty)
            Text(
              weekday,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),

          // Метка "Сегодня"
          if (today) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Сегодня',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
