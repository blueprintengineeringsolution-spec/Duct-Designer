import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_shell.dart';
import 'providers/app_startup_provider.dart';
import 'theme/app_theme.dart';

class DuctletorApp extends ConsumerWidget {
  const DuctletorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(appStartupProvider);
    return MaterialApp(
      title: 'Ductletor Pro',
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: ThemeMode.dark,
      home: startup.when(
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(
          body: Center(
            child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not open local storage: $e')),
          ),
        ),
        data: (_) => const AppShell(),
      ),
    );
  }
}
