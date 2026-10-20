import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/project_store.dart';
import 'project_controller.dart';

enum SaveStatus { saved, pending, saving, error }

/// Saves a project shortly after it changes. Selection and collapse changes don't count.
class AutoSaver {
  AutoSaver(this.controller, this.store, {this.debounce = const Duration(milliseconds: 600)})
      : _lastRevision = controller.revision {
    controller.addListener(_onChange);
  }

  final ProjectController controller;
  final ProjectStore store;
  final Duration debounce;
  final ValueNotifier<SaveStatus> status = ValueNotifier(SaveStatus.saved);

  Timer? _timer;
  Future<void>? _inflight;
  int _lastRevision;
  bool _dirty = false;
  bool _closed = false;

  void _onChange() {
    if (_closed || controller.revision == _lastRevision) return;
    _lastRevision = controller.revision;
    _dirty = true;
    status.value = SaveStatus.pending;
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
    status.value = SaveStatus.saving;
    final doc = controller.toDoc();
    final run = store.save(doc).then<void>((_) {
      if (!_dirty) status.value = SaveStatus.saved;
    }).catchError((Object _) {
      _dirty = true;
      status.value = SaveStatus.error;
    });
    _inflight = run;
    await run;
    _inflight = null;
  }

  /// Stop watching and flush pending changes.
  Future<void> close() async {
    controller.removeListener(_onChange);
    await saveNow();
    _closed = true;
  }

  /// Stop watching without saving (used when the project is being deleted).
  void discard() {
    _closed = true;
    _timer?.cancel();
    controller.removeListener(_onChange);
  }
}
