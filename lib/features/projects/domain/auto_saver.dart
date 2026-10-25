import 'dart:async';
import 'package:hvac_engine/hvac_engine.dart';
import 'project_repository.dart';

enum SaveStatus { saved, pending, saving, error }

/// Saves a project shortly after it changes. Selection and collapse changes don't count:
/// only a new revision does. Call [notifyChanged] after every change to the project.
class AutoSaver {
  AutoSaver({
    required this.repository,
    required this.readDoc,
    required this.readRevision,
    this.onStatus,
    this.debounce = const Duration(milliseconds: 600),
  }) : _lastRevision = readRevision();

  final ProjectRepository repository;

  /// The project as it is right now.
  final ProjectDoc Function() readDoc;

  /// The project's current revision (it goes up with every change that must be saved).
  final int Function() readRevision;
  final void Function(SaveStatus status)? onStatus;
  final Duration debounce;

  SaveStatus _status = SaveStatus.saved;
  Timer? _timer;
  Future<void>? _inflight;
  int _lastRevision;
  bool _dirty = false;
  bool _closed = false;

  SaveStatus get status => _status;

  void _setStatus(SaveStatus s) {
    if (s == _status) return;
    _status = s;
    onStatus?.call(s);
  }

  void notifyChanged() {
    if (_closed) return;
    final r = readRevision();
    if (r == _lastRevision) return;
    _lastRevision = r;
    _dirty = true;
    _setStatus(SaveStatus.pending);
    _timer?.cancel();
    _timer = Timer(debounce, saveNow);
  }

  /// Writes now if there are unsaved changes. Safe to call at any time (e.g. on app pause).
  Future<void> saveNow() async {
    _timer?.cancel();
    while (_inflight != null) {
      await _inflight;
    }
    if (!_dirty) return;
    _dirty = false;
    _setStatus(SaveStatus.saving);
    final doc = readDoc();
    final run = repository.save(doc).then<void>((_) {
      if (!_dirty) _setStatus(SaveStatus.saved);
    }).catchError((Object _) {
      _dirty = true;
      _setStatus(SaveStatus.error);
    });
    _inflight = run;
    await run;
    _inflight = null;
  }

  /// Stop watching and flush pending changes.
  Future<void> close() async {
    _closed = true;
    await saveNow();
  }

  /// Stop watching without saving (used when the project is being deleted).
  void discard() {
    _closed = true;
    _timer?.cancel();
  }
}
