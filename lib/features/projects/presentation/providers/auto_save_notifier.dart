import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../project_editor/domain/project_editor_state.dart';
import '../../../project_editor/presentation/providers/project_editor_provider.dart';
import '../../domain/auto_saver.dart';
import 'project_providers.dart';

/// Keeps the open project saved. The state is the save status, or null while no project is
/// attached. Edits are picked up from the editor; selection and collapse don't trigger a save.
class AutoSaveNotifier extends Notifier<SaveStatus?> {
  AutoSaver? _saver;
  ProjectEditorState? _latest;
  bool _alive = true;

  @override
  SaveStatus? build() {
    ref.onDispose(() {
      _alive = false;
      final saver = _saver;
      _saver = null;
      if (saver != null) unawaited(saver.close());
    });
    ref.listen<ProjectEditorState?>(projectEditorProvider, (previous, next) {
      if (next != null) _latest = next;
      _saver?.notifyChanged();
    });
    return null;
  }

  void _publish(SaveStatus status) {
    if (_alive) state = status;
  }

  /// Starts watching the project that is open now.
  void attach() {
    final editor = ref.read(projectEditorProvider);
    if (editor == null) return;
    _latest = editor;
    _saver = AutoSaver(
      repository: ref.read(projectRepositoryProvider),
      readDoc: () => _latest!.toDoc(),
      readRevision: () => _latest!.revision,
      debounce: ref.read(saveDebounceProvider),
      onStatus: _publish,
    );
    state = SaveStatus.saved;
  }

  void _sync(AutoSaver saver) {
    if (_alive) {
      final current = ref.read(projectEditorProvider);
      if (current != null) _latest = current;
    }
    saver.notifyChanged();
  }

  /// Writes now if there are unsaved changes. Safe to call at any time (e.g. on app pause).
  Future<void> saveNow() async {
    final saver = _saver;
    if (saver == null) return;
    _sync(saver);
    await saver.saveNow();
  }

  /// Stops watching. Pending changes are saved first unless [save] is false (used when the
  /// project is being deleted).
  Future<void> close({bool save = true}) async {
    final saver = _saver;
    _saver = null;
    if (saver == null) return;
    if (save) {
      _sync(saver);
      await saver.close();
    } else {
      saver.discard();
    }
    if (_alive) state = null;
  }
}

final autoSaveProvider = NotifierProvider<AutoSaveNotifier, SaveStatus?>(AutoSaveNotifier.new);
