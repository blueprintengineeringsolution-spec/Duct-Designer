import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hvac_engine/hvac_engine.dart';
import '../../domain/project_editor_state.dart';

/// Owns the open project. The state is null while no project is open. Every edit goes
/// through here, and the whole network is recomputed by the domain state on each one.
class ProjectEditorNotifier extends Notifier<ProjectEditorState?> {
  /// [initial] opens a project straight away (used by tests); the app opens one through
  /// the project library.
  ProjectEditorNotifier({ProjectEditorState? initial}) : _initial = initial;

  final ProjectEditorState? _initial;

  @override
  ProjectEditorState? build() => _initial;

  void activate(ProjectDoc doc) => state = ProjectEditorState.fromDoc(doc);

  void close() => state = null;

  void _apply(ProjectEditorState Function(ProjectEditorState s) edit) {
    final s = state;
    if (s == null) return;
    final next = edit(s);
    if (!identical(next, s)) state = next;
  }

  // ---- history ----
  void undo() => _apply((s) => s.undo());
  void redo() => _apply((s) => s.redo());

  // ---- selection / view ----
  void select(String? id) => _apply((s) => s.select(id));
  void toggleCollapsed(String id) => _apply((s) => s.toggleCollapsed(id));

  // ---- node edits ----
  void updateNode(
    String id, {
    String? name,
    double? flow,
    double? lengthM,
    DuctShape? shape,
    DuctMaterial? material,
    double? fixedHeightM,
    bool clearFixedHeight = false,
  }) =>
      _apply((s) => s.updateNode(
            id,
            name: name,
            flow: flow,
            lengthM: lengthM,
            shape: shape,
            material: material,
            fixedHeightM: fixedHeightM,
            clearFixedHeight: clearFixedHeight,
          ));

  void setInsulated(String id, bool v) => _apply((s) => s.setInsulated(id, v));
  void setJunction(String id, JunctionType? type) => _apply((s) => s.setJunction(id, type));
  void chooseSize(String id, DuctSize size) => _apply((s) => s.chooseSize(id, size));
  void clearSize(String id) => _apply((s) => s.clearSize(id));
  void stepRoundSize(String id, int dir) => _apply((s) => s.stepRoundSize(id, dir));

  // ---- tree structure ----
  void addChild(String parentId) => _apply((s) => s.addChild(parentId));
  void duplicate(String id) => _apply((s) => s.duplicate(id));
  void delete(String id) => _apply((s) => s.delete(id));

  // ---- units ----
  void setActiveUnit(String unitId) => _apply((s) => s.setActiveUnit(unitId));

  /// Returns the new unit's id, or null if the project already has the most units allowed.
  String? addUnit() {
    final s = state;
    if (s == null) return null;
    final next = s.addUnit();
    if (next == null) return null;
    state = next;
    return next.activeUnitId;
  }

  void renameUnit(String unitId, String newName) => _apply((s) => s.renameUnit(unitId, newName));

  String? duplicateUnit(String unitId) {
    final s = state;
    if (s == null) return null;
    final next = s.duplicateUnit(unitId);
    if (next == null) return null;
    state = next;
    return next.activeUnitId;
  }

  void deleteUnit(String unitId) => _apply((s) => s.deleteUnit(unitId));

  // ---- fittings ----
  void addFitting(String id, Fitting f) => _apply((s) => s.addFitting(id, f));
  void removeFitting(String id, int index) => _apply((s) => s.removeFitting(id, index));

  // ---- fitting library ----
  void saveToLibrary(Fitting f) => _apply((s) => s.saveToLibrary(f));
  void removeFromLibrary(int index) => _apply((s) => s.removeFromLibrary(index));
  void addFromLibrary(String nodeId, int index, {int count = 1}) =>
      _apply((s) => s.addFromLibrary(nodeId, index, count: count));

  ({int added, int replaced, int skipped}) importLibrary(List<Fitting> incoming, {required bool overwrite}) {
    final s = state;
    if (s == null) return (added: 0, replaced: 0, skipped: incoming.length);
    final outcome = s.importLibrary(incoming, overwrite: overwrite);
    if (!identical(outcome.state, s)) state = outcome.state;
    return (added: outcome.added, replaced: outcome.replaced, skipped: outcome.skipped);
  }

  // ---- project settings, details and name ----
  void setSettings(EngineSettings settings) => _apply((s) => s.setSettings(settings));
  void setImperial(bool v) => _apply((s) => s.setImperial(v));
  void setInfo(ReportInfo info) => _apply((s) => s.setInfo(info));
  void rename(String newName) => _apply((s) => s.rename(newName));
}

final projectEditorProvider =
    NotifierProvider<ProjectEditorNotifier, ProjectEditorState?>(ProjectEditorNotifier.new);

/// The open project, for screens that are only shown while one is open.
final currentProjectProvider = Provider<ProjectEditorState>((ref) {
  final s = ref.watch(projectEditorProvider);
  if (s == null) throw StateError('No project is open');
  return s;
});
