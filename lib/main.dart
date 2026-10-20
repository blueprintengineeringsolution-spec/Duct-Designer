import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'data/project_store.dart';
import 'features/network/network_page.dart';
import 'features/projects/projects_page.dart';
import 'features/report/report_page.dart';
import 'features/settings/project_settings_page.dart';
import 'state/project_library.dart';

void main() => runApp(const DuctletorApp());

class DuctletorApp extends StatefulWidget {
  const DuctletorApp({super.key});
  @override
  State<DuctletorApp> createState() => _DuctletorAppState();
}

class _DuctletorAppState extends State<DuctletorApp> with WidgetsBindingObserver {
  ProjectLibrary? lib;
  Object? startupError;
  int tab = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    try {
      final ProjectStore store;
      if (kIsWeb) {
        store = PrefsProjectStore(); // browser storage; path_provider has no web version
      } else {
        final docs = await getApplicationDocumentsDirectory();
        store = FileProjectStore(Directory('${docs.path}${Platform.pathSeparator}projects'));
      }
      final l = ProjectLibrary(store);
      await l.init();
      if (mounted) setState(() => lib = l);
    } catch (e) {
      if (mounted) setState(() => startupError = e);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) lib?.flush();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    lib?.dispose();
    super.dispose();
  }

  ThemeData _theme(Brightness b) => ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF2F6FED), brightness: b);

  @override
  Widget build(BuildContext context) {
    final l = lib;
    return MaterialApp(
      title: 'Ductletor Pro',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.dark,
      home: l == null
          ? Scaffold(
              body: Center(
                child: startupError == null
                    ? const CircularProgressIndicator()
                    : Padding(padding: const EdgeInsets.all(24), child: Text('Could not open local storage: $startupError')),
              ),
            )
          : ListenableBuilder(
              listenable: l,
              builder: (context, _) {
                final c = l.active;
                return Scaffold(
                  body: IndexedStack(index: tab, children: [
                    ProjectsPage(lib: l, onOpened: () => setState(() => tab = 1)),
                    c == null
                        ? const Center(child: CircularProgressIndicator())
                        : NetworkPage(key: ValueKey('net-${c.id}'), c: c, saveStatus: l.saver?.status),
                    c == null
                        ? const SizedBox.shrink()
                        : ReportPage(key: ValueKey('rep-${c.id}'), c: c),
                    c == null
                        ? const SizedBox.shrink()
                        : ProjectSettingsPage(key: ValueKey('set-${c.id}'), c: c),
                  ]),
                  bottomNavigationBar: NavigationBar(
                    selectedIndex: tab,
                    onDestinationSelected: (i) {
                      if (i == 0) l.refresh();
                      setState(() => tab = i);
                    },
                    destinations: const [
                      NavigationDestination(icon: Icon(Icons.folder_outlined), label: 'Projects'),
                      NavigationDestination(icon: Icon(Icons.account_tree_outlined), label: 'Network'),
                      NavigationDestination(icon: Icon(Icons.description_outlined), label: 'Report'),
                      NavigationDestination(icon: Icon(Icons.tune), label: 'Settings'),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
