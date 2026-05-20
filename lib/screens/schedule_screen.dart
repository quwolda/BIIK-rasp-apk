// ─────────────────────────────────────────────────────────────────────────────
// screens/schedule_screen.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/schedule_service.dart';
import '../widgets/lesson_card.dart';
import '../widgets/day_header.dart';
import 'changes_screen.dart';
import 'settings_screen.dart';
import 'group_picker_screen.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final _svc = ScheduleService();

  Group? _group;
  int _subgroup = 1;
  List<Lesson> _lessons = [];
  List<ScheduleSnapshot> _history = [];
  int _changeCount = 0;

  bool _loading = false;
  String _status = '';

  ScheduleSnapshot? _viewingSnapshot;

  @override
  void initState() {
    super.initState();
    _init();
  }

  // ── Инициализация ──────────────────────────────────────────────────────────

  Future<void> _init() async {
    _group = await _svc.getSelectedGroup();
    _subgroup = await _svc.getSubgroup();

    if (_group == null) {
      if (mounted) {
        final selected = await Navigator.push<Group>(
          context,
          MaterialPageRoute(
              builder: (_) => const GroupPickerScreen(isOnboarding: true)),
        );
        if (selected != null) {
          await _svc.setSelectedGroup(selected);
          _group = selected;
        }
      }
    }

    if (_group != null) {
      await _loadCached();
      await _refresh(silent: true);
    } else {
      setState(() => _status = '');
    }
  }

  // ── Загрузка кэша ─────────────────────────────────────────────────────────

  Future<void> _loadCached() async {
    if (_group == null) return;
    final baseline = await _svc.loadTodaysBaseline(_group!.id);
    final history = await _svc.loadHistory(_group!.id);
    final changes = await _svc.loadChanges(_group!.id);
    setState(() {
      _lessons = baseline?.lessons ?? [];
      _history = history;
      _changeCount = changes.length;
      _status = baseline != null ? 'Кэш от ${_fmtDt(baseline.fetchedAt)}' : '';
      _viewingSnapshot = null;
    });
  }

  // ── Обновление с сети ─────────────────────────────────────────────────────

  Future<void> _refresh({bool silent = false}) async {
    if (_group == null || _loading) return;
    setState(() {
      _loading = true;
      if (!silent) _status = 'Загрузка…';
    });

    try {
      final fresh = await _svc.fetchSchedule(_group!.url);
      final freshSnap = ScheduleSnapshot(
        groupId: _group!.id,
        fetchedAt: DateTime.now(),
        lessons: fresh,
      );

      // Базовая линия — только первый раз за день
      final savedNew =
          await _svc.saveTodaysBaselineIfAbsent(_group!.id, freshSnap);

      // Изменения — только если базовая линия уже была
      if (!savedNew) {
        final baseline = await _svc.loadTodaysBaseline(_group!.id);
        if (baseline != null) {
          final changes = _svc.detectChanges(baseline.lessons, fresh);
          if (changes.isNotEmpty) await _svc.saveChanges(_group!.id, changes);
        }
      }

      await _svc.addToHistory(_group!.id, freshSnap);

      final allChanges = await _svc.loadChanges(_group!.id);
      final history = await _svc.loadHistory(_group!.id);

      setState(() {
        _lessons = fresh;
        _history = history;
        _changeCount = allChanges.length;
        _viewingSnapshot = null;
        _status = 'Обновлено: ${_fmtDt(DateTime.now())}';
      });
    } catch (e) {
      setState(() => _status = 'Ошибка: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  // ── Вспомогательные ───────────────────────────────────────────────────────

  String _fmtDt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  List<Lesson> get _activeLessons {
    final src = _viewingSnapshot?.lessons ?? _lessons;
    return src.where((l) => l.matches(_subgroup)).toList();
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: _buildAppBar(),
      drawer: _buildDrawer(),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _refresh(),
        icon: _loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.refresh),
        label: const Text('Обновить'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF1565C0),
      foregroundColor: Colors.white,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_group?.name ?? 'БИИК Расписание',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          if (_viewingSnapshot != null)
            Text('📅 ${_viewingSnapshot!.weekLabel}',
                style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ],
      ),
      actions: [
        if (_changeCount > 0)
          Stack(
            alignment: Alignment.topRight,
            children: [
              IconButton(
                icon: const Icon(Icons.difference_outlined),
                tooltip: 'Изменения',
                onPressed: _openChanges,
              ),
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                      color: Colors.red, shape: BoxShape.circle),
                  child: Text('$_changeCount',
                      style: const TextStyle(color: Colors.white, fontSize: 9)),
                ),
              ),
            ],
          )
        else
          IconButton(
            icon: const Icon(Icons.difference_outlined),
            tooltip: 'Изменения',
            onPressed: _openChanges,
          ),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          onPressed: _openSettings,
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(44),
        child: _buildSubgroupTabs(),
      ),
    );
  }

  Widget _buildSubgroupTabs() {
    return Container(
      color: const Color(0xFF1565C0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          _sgChip('Все', 0),
          const SizedBox(width: 8),
          _sgChip('1 п/г', 1),
          const SizedBox(width: 8),
          _sgChip('2 п/г', 2),
          const Spacer(),
          Text(_status,
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _sgChip(String label, int val) {
    final selected = _subgroup == val;
    return GestureDetector(
      onTap: () async {
        await _svc.setSubgroup(val);
        setState(() => _subgroup = val);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white24,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? const Color(0xFF1565C0) : Colors.white,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            )),
      ),
    );
  }

  Widget _buildBody() {
    if (_group == null) {
      return Center(
        child: ElevatedButton.icon(
          icon: const Icon(Icons.group),
          label: const Text('Выбрать группу'),
          onPressed: _openGroupPicker,
        ),
      );
    }

    final lessons = _activeLessons;
    if (lessons.isEmpty && !_loading) return _buildEmpty();

    final Map<String, List<Lesson>> byDate = {};
    for (final l in lessons) {
      byDate.putIfAbsent(l.date, () => []).add(l);
    }
    final dates = byDate.keys.toList();

    return CustomScrollView(
      physics: const ClampingScrollPhysics(),
      slivers: [
        // История снимков
        if (_history.isNotEmpty)
          SliverToBoxAdapter(child: _buildHistoryChips()),

        // Кнопка «вернуться к текущему»
        if (_viewingSnapshot != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: TextButton.icon(
                icon: const Icon(Icons.arrow_back),
                label: const Text('Вернуться к текущему'),
                onPressed: () => setState(() => _viewingSnapshot = null),
              ),
            ),
          ),

        // Расписание
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) {
              final date = dates[i];
              final dayLessons = byDate[date]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DayHeader(date: date, weekday: dayLessons.first.weekday),
                  ...dayLessons.map((l) => LessonCard(lesson: l)),
                  const SizedBox(height: 4),
                ],
              );
            },
            childCount: dates.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }

  Widget _buildHistoryChips() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: _history.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final snap = _history[_history.length - 1 - i];
          final selected = _viewingSnapshot?.dateKey == snap.dateKey;
          return FilterChip(
            label: Text(snap.weekLabel,
                style: TextStyle(
                    fontSize: 11, color: selected ? Colors.white : null)),
            selected: selected,
            selectedColor: const Color(0xFF1565C0),
            onSelected: (_) => setState(() {
              _viewingSnapshot = selected ? null : snap;
            }),
          );
        },
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
          Text('Нажмите «Обновить»', style: TextStyle(color: Colors.grey[400])),
        ],
      ),
    );
  }

  // ── Боковое меню ──────────────────────────────────────────────────────────

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF1565C0)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text('БИИК Расписание',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                if (_group != null)
                  Text(_group!.name,
                      style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.group),
            title: const Text('Выбрать группу'),
            onTap: () {
              Navigator.pop(context);
              _openGroupPicker();
            },
          ),
          ListTile(
            leading: const Icon(Icons.star_outline),
            title: const Text('Избранные группы'),
            onTap: () {
              Navigator.pop(context);
              _openFavorites();
            },
          ),
          ListTile(
            leading: const Icon(Icons.difference_outlined),
            title: const Text('История изменений'),
            trailing:
                _changeCount > 0 ? Badge(label: Text('$_changeCount')) : null,
            onTap: () {
              Navigator.pop(context);
              _openChanges();
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Настройки'),
            onTap: () {
              Navigator.pop(context);
              _openSettings();
            },
          ),
        ],
      ),
    );
  }

  // ── Навигация ─────────────────────────────────────────────────────────────

  Future<void> _openSettings() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    if (result != null) {
      setState(() {
        if (result['group'] != null) _group = result['group'] as Group;
        if (result['subgroup'] != null) _subgroup = result['subgroup'] as int;
      });
      await _loadCached();
      await _refresh(silent: true);
    }
  }

  Future<void> _openGroupPicker() async {
    final selected = await Navigator.push<Group>(
      context,
      MaterialPageRoute(builder: (_) => const GroupPickerScreen()),
    );
    if (selected != null) {
      await _svc.setSelectedGroup(selected);
      setState(() {
        _group = selected;
        _lessons = [];
      });
      await _refresh(silent: true);
    }
  }

  Future<void> _openFavorites() async {
    final selected = await Navigator.push<Group>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            GroupPickerScreen(favoritesOnly: true, currentGroup: _group),
      ),
    );
    if (selected != null) {
      await _svc.setSelectedGroup(selected);
      setState(() {
        _group = selected;
        _lessons = [];
      });
      await _refresh(silent: true);
    }
  }

  Future<void> _openChanges() async {
    if (_group == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ChangesScreen(groupId: _group!.id, groupName: _group!.name),
      ),
    );
    final changes = await _svc.loadChanges(_group!.id);
    setState(() => _changeCount = changes.length);
  }
}
