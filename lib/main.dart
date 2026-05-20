// ─────────────────────────────────────────────────────────────────────────────
// main.dart  —  точка входа
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'screens/schedule_screen.dart';

void main() {
  runApp(const BiikApp());
}

class BiikApp extends StatelessWidget {
  const BiikApp({super.key});

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
        cardTheme: const CardThemeData(surfaceTintColor: Colors.white),
      ),
      home: const ScheduleScreen(),
    );
  }
}
