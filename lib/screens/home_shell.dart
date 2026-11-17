import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/platform_services.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import 'transcribe_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    ShareIntake.listen((items) {
      state.addAudio(items);
      if (mounted) setState(() => _tab = 0);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final items = await ShareIntake.initial();
      if (items.isNotEmpty) state.addAudio(items);
    });
  }

  @override
  Widget build(BuildContext context) {
    final processing =
        context.select<AppState, bool>((s) => s.status == AppStatus.processing);
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          TranscribeScreen(onOpenSettings: () => setState(() => _tab = 2)),
          const HistoryScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: Badge(
                isLabelVisible: processing,
                child: const Icon(Icons.graphic_eq_outlined)),
            selectedIcon: const Icon(Icons.graphic_eq),
            label: 'Расшифровка',
          ),
          const NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'История',
          ),
          const NavigationDestination(
            icon: Icon(Icons.key_outlined),
            selectedIcon: Icon(Icons.key),
            label: 'Ключи и модели',
          ),
        ],
      ),
    );
  }
}
