import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hvac_engine/hvac_engine.dart';
import '../core/sample_project.dart';
import '../data/project_store.dart';
import 'auto_saver.dart';
import 'project_controller.dart';

/// The list of saved projects plus the one that is open.
class ProjectLibrary extends ChangeNotifier {
  ProjectLibrary(this.store, {this.saveDebounce = const Duration(milliseconds: 600)});

  final ProjectStore store;
  final Duration saveDebounce;

  List<ProjectMeta> projects = [];
  ProjectController? _active;
  AutoSaver? _saver;
  String? loadError;

  ProjectController? get active => _active;
  AutoSaver? get saver => _saver;

  Future<void> init() async {
    await refresh();
    for (final m in projects) {
      if (await open(m.id)) return;
    }
    await create('Sample project', sample: true);
  }

  Future<void> refresh() async {
    projects = await store.list();
    notifyListeners();
  }

  void clearError() {
    loadError = null;
    notifyListeners();
  }

  Future<void> _activate(ProjectDoc doc) async {
    await _closeActive();
    final c = ProjectController.fromDoc(doc);
    _active = c;
    _saver = AutoSaver(c, store, debounce: saveDebounce);
    notifyListeners();
  }

  Future<void> _closeActive({bool save = true}) async {
    final s = _saver;
    _saver = null;
    _active = null;
    if (s != null) {
      if (save) {
        await s.close();
      } else {
        s.discard();
      }
    }
  }

  Future<bool> open(String id) async {
    try {
      if (_active?.id == id) return true;
      final doc = await store.load(id);
      if (doc == null) {
        loadError = 'That project could not be found.';
        notifyListeners();
        return false;
      }
      await _activate(doc);
      loadError = null;
      return true;
    } catch (e) {
      loadError = 'Could not open the project: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> create(String name, {bool sample = false}) async {
    final trimmed = name.trim();
    final doc = ProjectDoc(
      id: newProjectId(),
      name: trimmed.isEmpty ? 'Untitled project' : trimmed,
      imperial: false,
      settings: const EngineSettings(),
      root: sample ? sampleProject() : blankProject(),
      updatedAt: DateTime.now().toUtc(),
    );
    await store.save(doc);
    await _activate(doc);
    await refresh();
  }

  Future<void> rename(String id, String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    if (_active?.id == id) {
      _active!.rename(n);
      await _saver?.saveNow();
    } else {
      final d = await store.load(id);
      if (d != null) {
        await store.save(ProjectDoc(
          id: d.id, name: n, imperial: d.imperial, settings: d.settings,
          units: d.units, updatedAt: DateTime.now().toUtc(), info: d.info,
      library: d.library,
        ));
      }
    }
    await refresh();
  }

  /// Latest saved copy of a project (flushes pending edits first). Used for sharing.
  Future<ProjectDoc?> docFor(String id) async {
    if (_active?.id == id) await _saver?.saveNow();
    return store.load(id);
  }

  /// Adds a project that came from outside as a new local copy and opens it.
  Future<void> importShared(ProjectDoc d) async {
    final doc = ProjectDoc(
      id: newProjectId(),
      name: d.name.endsWith(' (imported)') ? d.name : '${d.name} (imported)',
      imperial: d.imperial,
      settings: d.settings,
      units: d.units,
      updatedAt: DateTime.now().toUtc(),
      info: d.info,
      library: d.library,
    );
    await store.save(doc);
    await _activate(doc);
    await refresh();
  }

  Future<void> duplicate(String id) async {
    if (_active?.id == id) await _saver?.saveNow();
    final d = await store.load(id);
    if (d == null) return;
    await store.save(ProjectDoc(
      id: newProjectId(), name: '${d.name} copy', imperial: d.imperial,
      settings: d.settings, units: d.units, updatedAt: DateTime.now().toUtc(), info: d.info,
      library: d.library,
    ));
    await refresh();
  }

  Future<void> delete(String id) async {
    final wasActive = _active?.id == id;
    if (wasActive) await _closeActive(save: false);
    await store.delete(id);
    await refresh();
    if (wasActive) {
      for (final m in projects) {
        if (await open(m.id)) return;
      }
      await create('New project');
    }
  }

  /// Flush unsaved changes (call when the app goes to the background).
  Future<void> flush() async => _saver?.saveNow();

  @override
  void dispose() {
    unawaited(_closeActive());
    super.dispose();
  }
}
