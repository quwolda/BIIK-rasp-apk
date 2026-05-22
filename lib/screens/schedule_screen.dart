// ─────────────────────────────────────────────────────────────────────────────
// screens/schedule_screen.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/schedule_service.dart';
import '../services/notification_service.dart';
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
  List<Lesson> _lessons = []; // текущее расписание (текущая неделя)
  List<ScheduleSnapshot> _weekHistory = []; // история по неделям
  int _changeCount = 0;

  bool _loading = false;
  bool _homeToday = false;
  String _status = '';

  ScheduleSnapshot? _viewingSnapshot; // просматриваемая неделя из истории

  @override
  void initState() {
    super.initState();
    _init();
  }

  // ── Инициализация ──────────────────────────────────────────────────────────

  Future<void> _init() async {
    _group = await _svc.getSelectedGroup();
    _subgroup = await _svc.getSubgroup();
    _homeToday = await NotificationService.isHomeTodayEnabled();

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
      await NotificationService.requestPermission();
    } else {
      setState(() => _status = '');
    }
  }

  // ── Загрузка кэша текущей недели ──────────────────────────────────────────

  Future<void> _loadCached() async {
    if (_group == null) return;
    final wKey = _svc.weekKey(DateTime.now());
    final snap = await _svc.loadWeekSnapshot(_group!.id, wKey);
    final history = await _svc.loadWeekHistory(_group!.id);
    final changes = await _svc.loadChanges(_group!.id);
    setState(() {
      _lessons = snap?.lessons ?? [];
      _weekHistory = history;
      _changeCount = changes.length;
      _status = snap != null ? 'Кэш от ${_fmtDt(snap.fetchedAt)}' : '';
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
      final result = await _svc.refreshSchedule(_group!.id, _group!.url);

      // Сохраняем изменения если есть
      if (result.changes.isNotEmpty) {
        await _svc.saveChanges(_group!.id, result.changes);
      }

      final allChanges = await _svc.loadChanges(_group!.id);
      final history = await _svc.loadWeekHistory(_group!.id);

      setState(() {
        _lessons = result.lessons;
        _weekHistory = history;
        _changeCount = allChanges.length;
        _viewingSnapshot = null;
        _status = 'Обновлено: ${_fmtDt(DateTime.now())}';
      });

      if (!_homeToday) {
        await NotificationService.scheduleAll(result.lessons, _subgroup);
      }
    } catch (e) {
      setState(() => _status = 'Ошибка: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  // ── "Сегодня дома" ────────────────────────────────────────────────────────

  Future<void> _toggleHomeToday() async {
    final newVal = !_homeToday;
    await NotificationService.setHomeToday(newVal);
    setState(() => _homeToday = newVal);

    if (!newVal && _lessons.isNotEmpty) {
      await NotificationService.scheduleAll(_lessons, _subgroup);
    }

    _showSnack(
        newVal ? 'Уведомления на сегодня отключены' : 'Уведомления включены');
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
        IconButton(
          icon: Icon(_homeToday ? Icons.home : Icons.home_outlined),
          tooltip: _homeToday ? 'Уведомления отключены' : 'Сегодня дома',
          onPressed: _toggleHomeToday,
        ),
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
          if (_homeToday)
            const Row(children: [
              Icon(Icons.notifications_off, size: 12, color: Colors.white54),
              SizedBox(width: 4),
              Text('Дома',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
              SizedBox(width: 8),
            ]),
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
        if (!_homeToday && _lessons.isNotEmpty) {
          await NotificationService.scheduleAll(_lessons, val);
        }
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
        // Чипы истории недель
        if (_weekHistory.length > 1)
          SliverToBoxAdapter(child: _buildWeekHistoryChips()),

        if (_viewingSnapshot != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: TextButton.icon(
                icon: const Icon(Icons.arrow_back),
                label: const Text('Вернуться к текущей неделе'),
                onPressed: () => setState(() => _viewingSnapshot = null),
              ),
            ),
          ),

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

  /// Чипы с диапазонами недель (например "19.05 – 25.05")
  Widget _buildWeekHistoryChips() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: _weekHistory.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          // Показываем от новых к старым
          final snap = _weekHistory[_weekHistory.length - 1 - i];
          final selected = _viewingSnapshot != null &&
              _viewingSnapshot!.weekLabel == snap.weekLabel;
          final isCurrent = i == 0; // самый первый = текущая неделя

          return FilterChip(
            label: Text(
              isCurrent ? '${snap.weekLabel} (тек.)' : snap.weekLabel,
              style: TextStyle(
                  fontSize: 11, color: selected ? Colors.white : null),
            ),
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
            leading: Icon(
              _homeToday ? Icons.home : Icons.home_outlined,
              color: _homeToday ? Colors.orange : null,
            ),
            title: Text(_homeToday ? 'Уведомления отключены' : 'Сегодня дома'),
            subtitle: Text(_homeToday
                ? 'Нажмите чтобы включить'
                : 'Отключить уведомления на сегодня'),
            onTap: () {
              Navigator.pop(context);
              _toggleHomeToday();
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
