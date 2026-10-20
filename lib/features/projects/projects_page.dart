import 'package:flutter/material.dart';
import '../../data/project_store.dart';
import '../../state/project_library.dart';
import '../share/share_actions.dart';

String _stamp(DateTime t) {
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

class ProjectsPage extends StatelessWidget {
  final ProjectLibrary lib;
  final VoidCallback onOpened;
  const ProjectsPage({super.key, required this.lib, required this.onOpened});

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
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) {
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
                      await importFromFile(context, lib, onOpened);
                    case 'scan':
                      await importFromScan(context, lib, onOpened);
                    case 'paste':
                      await importFromPaste(context, lib, onOpened);
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
                onOpened();
              }
            },
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              if (lib.loadError != null)
                MaterialBanner(
                  content: Text(lib.loadError!),
                  actions: [TextButton(onPressed: lib.clearError, child: const Text('Dismiss'))],
                ),
              for (final p in lib.projects) _tile(context, p),
              if (lib.projects.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No projects yet.')),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(BuildContext context, ProjectMeta p) {
    final isActive = lib.active?.id == p.id;
    return ListTile(
      selected: isActive,
      leading: Icon(isActive ? Icons.folder_open : Icons.folder_outlined),
      title: Text(p.name),
      subtitle: Text('Updated ${_stamp(p.updatedAt)}'),
      onTap: () async {
        if (await lib.open(p.id)) onOpened();
      },
      trailing: PopupMenuButton<String>(
        tooltip: 'Actions for ${p.name}',
        onSelected: (v) async {
          switch (v) {
            case 'rename':
              final n = await _askName(context, 'Rename project', p.name);
              if (n != null) await lib.rename(p.id, n);
            case 'file':
              await shareProjectFile(context, lib, p.id);
            case 'qr':
              await showProjectQr(context, lib, p.id);
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
