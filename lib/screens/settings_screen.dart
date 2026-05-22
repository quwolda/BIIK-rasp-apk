// ─────────────────────────────────────────────────────────────────────────────
// screens/settings_screen.dart  —  настройки пользователя
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/schedule_service.dart';
import 'group_picker_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _svc = ScheduleService();
  Group? _group;
  int _subgroup = 1;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final g = await _svc.getSelectedGroup();
    final s = await _svc.getSubgroup();
    setState(() {
      _group = g;
      _subgroup = s;
    });
  }

  Future<void> _pickGroup() async {
    final selected = await Navigator.push<Group>(
      context,
      MaterialPageRoute(builder: (_) => const GroupPickerScreen()),
    );
    if (selected != null) {
      await _svc.setSelectedGroup(selected);
      setState(() {
        _group = selected;
        _changed = true;
      });
    }
  }

  Future<void> _setSubgroup(int v) async {
    await _svc.setSubgroup(v);
    setState(() {
      _subgroup = v;
      _changed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
        if (didPop && _changed) {
          // Вернём изменения на предыдущий экран
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F4F8),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1565C0),
          foregroundColor: Colors.white,
          title: const Text('Настройки',
              style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            if (_changed)
              TextButton(
                onPressed: () => Navigator.pop(
                    context, {'group': _group, 'subgroup': _subgroup}),
                child:
                    const Text('Готово', style: TextStyle(color: Colors.white)),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _SectionHeader(title: 'Основное'),
            _SettingCard(
              icon: Icons.group,
              title: 'Моя группа',
              subtitle: _group?.name ?? 'Не выбрана',
              onTap: _pickGroup,
            ),
            const SizedBox(height: 16),
            const _SectionHeader(title: 'Подгруппа'),
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('По умолчанию показывать пары для:',
                        style: TextStyle(fontSize: 13, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _sgBtn('Все пары', 0),
                        const SizedBox(width: 8),
                        _sgBtn('1 подгруппа', 1),
                        const SizedBox(width: 8),
                        _sgBtn('2 подгруппа', 2),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _subgroup == 0
                          ? 'Отображаются пары всех подгрупп'
                          : 'Общие пары + пары $_subgroup подгруппы. '
                              'Пары другой подгруппы видны в фоне.',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const _SectionHeader(title: 'Данные'),
            _SettingCard(
              icon: Icons.delete_outline,
              title: 'Очистить кэш',
              subtitle: 'Удалить сохранённые расписания',
              color: Colors.red,
              onTap: _confirmClearCache,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sgBtn(String label, int val) {
    final selected = _subgroup == val;
    return Expanded(
      child: GestureDetector(
        onTap: () => _setSubgroup(val),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1565C0) : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? const Color(0xFF1565C0) : Colors.grey[300]!,
            ),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? Colors.white : Colors.grey[700],
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              )),
        ),
      ),
    );
  }

  Future<void> _confirmClearCache() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Очистить кэш?'),
        content: const Text(
            'Сохранённые расписания и история изменений будут удалены.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Очистить')),
        ],
      ),
    );
    if (ok == true && _group != null) {
      final svc = ScheduleService();
      await svc.clearChanges(_group!.id);
      // Кэш истории и бейзлайна — можно очистить вручную через prefs.clear()
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Кэш очищен')));
      }
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(title.toUpperCase(),
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey[500],
              letterSpacing: 1)),
    );
  }
}

class _SettingCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? color;

  const _SettingCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF1565C0);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: c.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: c, size: 20),
        ),
        title: Text(title),
        subtitle: Text(subtitle,
            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}
