// ─────────────────────────────────────────────────────────────────────────────
// screens/group_picker_screen.dart
// Выбор группы: список с поиском + избранное
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/schedule_service.dart';

class GroupPickerScreen extends StatefulWidget {
  final bool isOnboarding;
  final bool favoritesOnly;
  final Group? currentGroup;

  const GroupPickerScreen({
    super.key,
    this.isOnboarding = false,
    this.favoritesOnly = false,
    this.currentGroup,
  });

  @override
  State<GroupPickerScreen> createState() => _GroupPickerScreenState();
}

class _GroupPickerScreenState extends State<GroupPickerScreen> {
  final _svc = ScheduleService();
  final _search = TextEditingController();

  List<Group> _all = [];
  List<Group> _favorites = [];
  List<Group> _filtered = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(_filter);
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Сначала кэш
      var groups = await _svc.getCachedGroups();
      _favorites = await _svc.getFavorites();

      if (groups.isEmpty) {
        groups = await _svc.fetchGroups();
        await _svc.cacheGroups(groups);
      }

      setState(() {
        _all      = groups;
        _filtered = widget.favoritesOnly ? _favorites : groups;
        _loading  = false;
      });
    } catch (e) {
      // Попробуем кэш
      final cached = await _svc.getCachedGroups();
      if (cached.isNotEmpty) {
        setState(() { _all = cached; _filtered = cached; _loading = false; });
      } else {
        setState(() { _error = e.toString(); _loading = false; });
      }
    }
  }

  Future<void> _reload() async {
    setState(() { _loading = true; _error = null; });
    try {
      final groups = await _svc.fetchGroups();
      await _svc.cacheGroups(groups);
      _favorites = await _svc.getFavorites();
      setState(() {
        _all = groups;
        _filtered = widget.favoritesOnly ? _favorites : groups;
        _loading = false;
      });
      _filter();
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _filter() {
    final q = _search.text.toLowerCase();
    final src = widget.favoritesOnly ? _favorites : _all;
    setState(() {
      _filtered = q.isEmpty
          ? src
          : src.where((g) => g.name.toLowerCase().contains(q)).toList();
    });
  }

  Future<void> _toggleFav(Group g) async {
    final isFav = _favorites.any((f) => f.id == g.id);
    if (isFav) {
      await _svc.removeFavorite(g);
    } else {
      await _svc.addFavorite(g);
    }
    _favorites = await _svc.getFavorites();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: !widget.isOnboarding,
        title: Text(widget.favoritesOnly ? 'Избранные группы' : 'Выбор группы',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _reload),
        ],
      ),
      body: Column(
        children: [
          // Онбординг-заголовок
          if (widget.isOnboarding)
            Container(
              width: double.infinity,
              color: const Color(0xFF1565C0),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: const Text(
                'Добро пожаловать! Выберите свою группу чтобы начать.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),

          // Поиск
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Поиск группы…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () { _search.clear(); _filter(); })
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Список
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text('Ошибка загрузки', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _reload, child: const Text('Повторить')),
          ],
        ),
      );
    }

    if (_filtered.isEmpty) {
      return Center(
        child: Text(
          widget.favoritesOnly
              ? 'Нет избранных групп.\nДобавьте группы через иконку ★'
              : 'Группы не найдены',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _filtered.length,
      itemBuilder: (_, i) {
        final g = _filtered[i];
        final isFav = _favorites.any((f) => f.id == g.id);
        final isCurrent = widget.currentGroup?.id == g.id;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isCurrent
                  ? const Color(0xFF1565C0)
                  : const Color(0xFF1565C0).withOpacity(0.1),
              child: Text(
                g.name.substring(0, g.name.length.clamp(0, 2)),
                style: TextStyle(
                  color: isCurrent ? Colors.white : const Color(0xFF1565C0),
                  fontSize: 12, fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(g.name,
                style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
            subtitle: isCurrent ? const Text('Текущая группа') : null,
            trailing: IconButton(
              icon: Icon(isFav ? Icons.star : Icons.star_outline,
                  color: isFav ? Colors.amber : Colors.grey),
              onPressed: () => _toggleFav(g),
            ),
            onTap: () => Navigator.pop(context, g),
          ),
        );
      },
    );
  }
}
