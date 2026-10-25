import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/navigation/home_tab_provider.dart';
import '../../project_editor/presentation/providers/project_editor_provider.dart';
import '../../share/presentation/share_actions.dart';
import '../domain/project_meta.dart';
import 'providers/project_library_notifier.dart';

String _stamp(DateTime t) {
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

class ProjectsPage extends ConsumerWidget {
  const ProjectsPage({super.key});

  Future<String?> _askName(BuildContext context, String title, String initial) {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Project name'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Save')),
        ],
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, String name) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete project?'),
        content: Text('"$name" will be removed from this device. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    return r ?? false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(projectLibraryProvider);
    final lib = ref.read(projectLibraryProvider.notifier);
    final tab = ref.read(homeTabProvider.notifier);
    final activeId = ref.watch(projectEditorProvider.select((e) => e?.id));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Import a project',
            icon: const Icon(Icons.download_outlined),
            onSelected: (v) async {
              switch (v) {
                case 'file':
                  await importFromFile(context, ref);
                case 'scan':
                  await importFromScan(context, ref);
                case 'paste':
                  await importFromPaste(context, ref);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'file', child: Text('Import from file')),
              PopupMenuItem(value: 'scan', child: Text('Scan QR code')),
              PopupMenuItem(value: 'paste', child: Text('Paste code')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New project'),
        onPressed: () async {
          final name = await _askName(context, 'New project', '');
          if (name != null) {
            await lib.create(name);
            tab.select(1);
          }
        },
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          if (library.loadError != null)
            MaterialBanner(
              content: Text(library.loadError!),
              actions: [TextButton(onPressed: lib.clearError, child: const Text('Dismiss'))],
            ),
          for (final p in library.projects) _tile(context, ref, p, p.id == activeId),
          if (library.projects.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No projects yet.')),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, ProjectMeta p, bool isActive) {
    final lib = ref.read(projectLibraryProvider.notifier);
    final tab = ref.read(homeTabProvider.notifier);
    return ListTile(
      selected: isActive,
      leading: Icon(isActive ? Icons.folder_open : Icons.folder_outlined),
      title: Text(p.name),
      subtitle: Text('Updated ${_stamp(p.updatedAt)}'),
      onTap: () async {
        if (await lib.open(p.id)) tab.select(1);
      },
      trailing: PopupMenuButton<String>(
        tooltip: 'Actions for ${p.name}',
        onSelected: (v) async {
          switch (v) {
            case 'rename':
              final n = await _askName(context, 'Rename project', p.name);
              if (n != null) await lib.rename(p.id, n);
            case 'file':
              await shareProjectFile(context, ref, p.id);
            case 'qr':
              await showProjectQr(context, ref, p.id);
            case 'dup':
              await lib.duplicate(p.id);
            case 'del':
              if (await _confirmDelete(context, p.name)) await lib.delete(p.id);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(value: 'file', child: Text('Share as file')),
          PopupMenuItem(value: 'qr', child: Text('Show QR code')),
          PopupMenuItem(value: 'dup', child: Text('Duplicate')),
          PopupMenuItem(value: 'del', child: Text('Delete')),
        ],
      ),
    );
  }
}
