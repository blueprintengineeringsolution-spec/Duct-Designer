import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/navigation/home_tab_provider.dart';
import '../features/network/presentation/network_page.dart';
import '../features/project_editor/presentation/providers/project_editor_provider.dart';
import '../features/projects/presentation/projects_page.dart';
import '../features/projects/presentation/providers/project_library_notifier.dart';
import '../features/report/presentation/report_page.dart';
import '../features/settings/presentation/project_settings_page.dart';

/// The four tabs. Saves pending edits when the app leaves the foreground.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) ref.read(projectLibraryProvider.notifier).flush();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(homeTabProvider);
    final id = ref.watch(projectEditorProvider.select((e) => e?.id));
    return Scaffold(
      body: IndexedStack(index: tab, children: [
        const ProjectsPage(),
        id == null ? const Center(child: CircularProgressIndicator()) : NetworkPage(key: ValueKey('net-$id')),
        id == null ? const SizedBox.shrink() : ReportPage(key: ValueKey('rep-$id')),
        id == null ? const SizedBox.shrink() : ProjectSettingsPage(key: ValueKey('set-$id')),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) {
          if (i == 0) ref.read(projectLibraryProvider.notifier).refresh();
          ref.read(homeTabProvider.notifier).select(i);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.folder_outlined), label: 'Projects'),
          NavigationDestination(icon: Icon(Icons.account_tree_outlined), label: 'Network'),
          NavigationDestination(icon: Icon(Icons.description_outlined), label: 'Report'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Settings'),
        ],
      ),
    );
  }
}
