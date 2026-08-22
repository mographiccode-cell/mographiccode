import 'dart:async';

import 'package:flutter/material.dart';

import 'core/controller.dart';
import 'screens/activity_screen.dart';
import 'screens/apps_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PrivacyShieldApp());
}

class PrivacyShieldApp extends StatefulWidget {
  const PrivacyShieldApp({super.key});

  @override
  State<PrivacyShieldApp> createState() => _PrivacyShieldAppState();
}

class _PrivacyShieldAppState extends State<PrivacyShieldApp>
    with WidgetsBindingObserver {
  late final PrivacyController controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller = PrivacyController();
    unawaited(controller.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(controller.refreshAll());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Privacy Shield',
        locale: const Locale('ar'),
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF087B58),
          ),
          scaffoldBackgroundColor: const Color(0xFFF4F7F6),
          cardTheme: const CardThemeData(
            elevation: 0,
            margin: EdgeInsets.symmetric(vertical: 6),
          ),
          inputDecorationTheme: const InputDecorationTheme(
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF4DDBA8),
            brightness: Brightness.dark,
          ),
        ),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: HomeShell(controller: controller),
        ),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({required this.controller, super.key});
  final PrivacyController controller;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          if (widget.controller.loading) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          final pages = <Widget>[
            DashboardScreen(controller: widget.controller),
            AppsScreen(controller: widget.controller),
            ActivityScreen(controller: widget.controller),
            SettingsScreen(controller: widget.controller),
          ];
          return Scaffold(
            appBar: AppBar(
              title: const Text('Privacy Shield',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              actions: [
                if (widget.controller.busy)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    onPressed: widget.controller.refreshAll,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
              ],
            ),
            body: Column(
              children: [
                if (widget.controller.error != null)
                  MaterialBanner(
                    content: Text(widget.controller.error!),
                    actions: [
                      TextButton(
                        onPressed: widget.controller.refreshAll,
                        child: const Text('إعادة الفحص'),
                      ),
                    ],
                  ),
                Expanded(child: IndexedStack(index: index, children: pages)),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (value) => setState(() => index = value),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.shield_outlined),
                  selectedIcon: Icon(Icons.shield),
                  label: 'الحماية',
                ),
                NavigationDestination(
                  icon: Icon(Icons.apps_outlined),
                  selectedIcon: Icon(Icons.apps),
                  label: 'التطبيقات',
                ),
                NavigationDestination(
                  icon: Icon(Icons.history),
                  label: 'السجل',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'الإعدادات',
                ),
              ],
            ),
          );
        },
      );
}
