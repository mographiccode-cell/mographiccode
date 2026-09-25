import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/migration_screen.dart';
import 'screens/projects_screen.dart';
import 'screens/tasks_screen.dart';
import 'screens/settings_screen.dart';
import 'services/database_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProjectOrganizerApp());
}

class ProjectOrganizerApp extends StatelessWidget {
  const ProjectOrganizerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ProjectDesk Next',
      theme: AppTheme.light(),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const StartupGate(),
    );
  }
}

class StartupGate extends StatefulWidget {
  const StartupGate({super.key});
  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  bool loading = true;
  bool migration = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final projects = await DatabaseService.instance.allProjects();
      final done = await DatabaseService.instance.getSetting('migration_done');
      if (mounted) {
        setState(() {
          migration = projects.isEmpty && done != '1';
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (migration) {
      return MigrationScreen(onDone: () => setState(() => migration = false));
    }
    return const HomeShell();
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 1;
  int refreshToken = 0;

  void refresh() => setState(() => refreshToken++);

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(key: ValueKey('dash$refreshToken'), onChanged: refresh, onOpenProjects: () => setState(() => index = 1), onOpenTasks: () => setState(() => index = 2)),
      ProjectsScreen(key: ValueKey('projects$refreshToken'), onChanged: refresh),
      TasksScreen(key: ValueKey('tasks$refreshToken'), onChanged: refresh),
      SettingsScreen(key: ValueKey('settings$refreshToken'), onRestored: refresh),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: index, children: screens)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'المشاريع'),
          NavigationDestination(icon: Icon(Icons.rule_folder_outlined), selectedIcon: Icon(Icons.rule_folder), label: 'التعديلات'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'الإعدادات'),
        ],
      ),
    );
  }
}
