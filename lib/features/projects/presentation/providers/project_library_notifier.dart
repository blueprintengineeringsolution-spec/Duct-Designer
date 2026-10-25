import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hvac_engine/hvac_engine.dart';
import '../../../project_editor/presentation/providers/project_editor_provider.dart';
import '../../domain/project_meta.dart';
import 'auto_save_notifier.dart';
import 'project_providers.dart';

/// The saved projects, and the last problem opening one.
class ProjectLibraryState {
  final List<ProjectMeta> projects;
  final String? loadError;
  const ProjectLibraryState({this.projects = const [], this.loadError});

  ProjectLibraryState copyWith({List<ProjectMeta>? projects, String? loadError, bool clearError = false}) =>
      ProjectLibraryState(
        projects: projects ?? this.projects,
        loadError: clearError ? null : (loadError ?? this.loadError),
      );
}

/// The list of saved projects plus the one that is open (kept by the editor provider).
class ProjectLibraryNotifier extends Notifier<ProjectLibraryState> {
  @override
  ProjectLibraryState build() => const ProjectLibraryState();

  /// Opens the first project that can be opened, or creates the sample project.
  Future<void> init() async {
    await refresh();
    for (final m in state.projects) {
      if (await open(m.id)) return;
    }
    await create('Sample project', sample: true);
  }

  Future<void> refresh() async {
    final projects = await ref.read(listProjectsProvider)();
    state = state.copyWith(projects: projects);
  }

  void clearError() => state = state.copyWith(clearError: true);

  String? get _activeId => ref.read(projectEditorProvider)?.id;

  Future<void> _activate(ProjectDoc doc) async {
    await _closeActive();
    ref.read(projectEditorProvider.notifier).activate(doc);
    ref.read(autoSaveProvider.notifier).attach();
  }

  Future<void> _closeActive({bool save = true}) async {
    await ref.read(autoSaveProvider.notifier).close(save: save);
    ref.read(projectEditorProvider.notifier).close();
  }

  Future<bool> open(String id) async {
    try {
      if (_activeId == id) return true;
      final doc = await ref.read(loadProjectProvider)(id);
      if (doc == null) {
        state = state.copyWith(loadError: 'That project could not be found.');
        return false;
      }
      await _activate(doc);
      state = state.copyWith(clearError: true);
      return true;
    } catch (e) {
      state = state.copyWith(loadError: 'Could not open the project: $e');
      return false;
    }
  }

  Future<void> create(String name, {bool sample = false}) async {
    final doc = await ref.read(createProjectProvider)(name, sample: sample);
    await _activate(doc);
    await refresh();
  }

  Future<void> rename(String id, String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    if (_activeId == id) {
      ref.read(projectEditorProvider.notifier).rename(n);
      await ref.read(autoSaveProvider.notifier).saveNow();
    } else {
      await ref.read(renameStoredProjectProvider)(id, n);
    }
    await refresh();
  }

  /// Latest saved copy of a project (flushes pending edits first). Used for sharing.
  Future<ProjectDoc?> docFor(String id) async {
    if (_activeId == id) await ref.read(autoSaveProvider.notifier).saveNow();
    return ref.read(loadProjectProvider)(id);
  }

  /// Adds a project that came from outside as a new local copy and opens it.
  Future<void> importShared(ProjectDoc d) async {
    final doc = await ref.read(importSharedProjectProvider)(d);
    await _activate(doc);
    await refresh();
  }

  Future<void> duplicate(String id) async {
    if (_activeId == id) await ref.read(autoSaveProvider.notifier).saveNow();
    await ref.read(duplicateProjectProvider)(id);
    await refresh();
  }

  Future<void> delete(String id) async {
    final wasActive = _activeId == id;
    if (wasActive) await _closeActive(save: false);
    await ref.read(deleteProjectProvider)(id);
    await refresh();
    if (wasActive) {
      for (final m in state.projects) {
        if (await open(m.id)) return;
      }
      await create('New project');
    }
  }

  /// Flush unsaved changes (call when the app goes to the background).
  Future<void> flush() => ref.read(autoSaveProvider.notifier).saveNow();
}

final projectLibraryProvider =
    NotifierProvider<ProjectLibraryNotifier, ProjectLibraryState>(ProjectLibraryNotifier.new);
