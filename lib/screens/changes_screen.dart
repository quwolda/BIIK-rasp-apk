// ─────────────────────────────────────────────────────────────────────────────
// screens/changes_screen.dart  —  история изменений расписания
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/schedule_service.dart';

class ChangesScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const ChangesScreen({super.key, required this.groupId, required this.groupName});

  @override
  State<ChangesScreen> createState() => _ChangesScreenState();
}

class _ChangesScreenState extends State<ChangesScreen> {
  final _svc = ScheduleService();
  List<LessonChange> _changes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await _svc.loadChanges(widget.groupId);
    setState(() { _changes = c.reversed.toList(); _loading = false; });
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Очистить историю?'),
        content: const Text('Все записи об изменениях будут удалены.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, true),  child: const Text('Очистить')),
        ],
      ),
    );
    if (ok == true) {
      await _svc.clearChanges(widget.groupId);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        title: Text('Изменения — ${widget.groupName}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_changes.isNotEmpty)
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _clear),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _changes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, size: 64, color: Colors.green[300]),
                      const SizedBox(height: 12),
                      Text('Изменений не обнаружено',
                          style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _changes.length,
                  itemBuilder: (_, i) => _ChangeCard(change: _changes[i]),
                ),
    );
  }
}

class _ChangeCard extends StatelessWidget {
  final LessonChange change;
  const _ChangeCard({required this.change});

  @override
  Widget build(BuildContext context) {
    final cfg = _fieldConfig(change.field);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Дата + пара + метка
            Row(
              children: [
                Text('${change.date}  •  ${change.pairNum} пара',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cfg.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: cfg.color.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(cfg.icon, size: 12, color: cfg.color),
                      const SizedBox(width: 4),
                      Text(cfg.label, style: TextStyle(fontSize: 11, color: cfg.color,
                          fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(change.subject,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 6),
            // Было → стало
            if (change.field != 'added' && change.field != 'removed') ...[
              _diffRow('Было', change.oldValue, Colors.red[700]!),
              _diffRow('Стало', change.newValue, Colors.green[700]!),
            ] else if (change.field == 'added')
              _diffRow('Добавлено', change.newValue, Colors.green[700]!)
            else
              _diffRow('Удалено', change.oldValue, Colors.red[700]!),
            const SizedBox(height: 4),
            Text(_fmtDt(change.detectedAt),
                style: TextStyle(fontSize: 11, color: Colors.grey[400])),
          ],
        ),
      ),
    );
  }

  Widget _diffRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 48,
              child: Text(label, style: TextStyle(fontSize: 12, color: color,
                  fontWeight: FontWeight.w600))),
          Expanded(child: Text(value, style: TextStyle(fontSize: 12, color: color))),
        ],
      ),
    );
  }

  String _fmtDt(DateTime dt) =>
      '${dt.day.toString().padLeft(2,'0')}.${dt.month.toString().padLeft(2,'0')}.${dt.year} '
      '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';

  ({Color color, IconData icon, String label}) _fieldConfig(String field) {
    return switch (field) {
      'added'   => (color: Colors.green,  icon: Icons.add_circle_outline,    label: 'Добавлено'),
      'removed' => (color: Colors.red,    icon: Icons.remove_circle_outline,  label: 'Удалено'),
      'room'    => (color: Colors.orange, icon: Icons.meeting_room_outlined,  label: 'Аудитория'),
      'teacher' => (color: Colors.purple, icon: Icons.person_outline,         label: 'Преподаватель'),
      'type'    => (color: Colors.teal,   icon: Icons.category_outlined,      label: 'Тип'),
      'time'    => (color: Colors.blue,   icon: Icons.access_time,            label: 'Время'),
      _         => (color: Colors.blue,   icon: Icons.edit_outlined,          label: 'Предмет'),
    };
  }
}
