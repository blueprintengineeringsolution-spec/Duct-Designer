import 'package:hvac_engine/hvac_engine.dart';
import '../../../core/formatting/fmt.dart';
import 'project_editor_draft.dart';

/// One undo step: everything an edit can change.
class ProjectSnapshot {
  final List<DuctNode> units;
  final String activeId;
  final EngineSettings settings;
  final bool imperial;
  final ReportInfo info;
  final String name;
  final List<Fitting> library;
  const ProjectSnapshot(this.units, this.activeId, this.settings, this.imperial, this.info, this.name, this.library);
}

/// What a library merge did, with the project as it is afterwards.
class LibraryImportOutcome {
  final ProjectEditorState state;
  final int added, replaced, skipped;
  const LibraryImportOutcome(this.state, {required this.added, required this.replaced, required this.skipped});
}

/// The open project as an immutable value: every unit's tree, the settings, the fitting
/// library, the selection, the calculated results and the undo history. Each edit returns a
/// new state with the whole network recomputed. Pure Dart, so it is easy to test.
class ProjectEditorState {
  /// Used by [ProjectEditorDraft]. Prefer [ProjectEditorState.create] or [ProjectEditorState.fromDoc].
  ProjectEditorState.internal({
    required this.id,
    required this.name,
    required this.revision,
    required List<DuctNode> units,
    required this.activeUnitId,
    required this.settings,
    required this.imperial,
    required this.info,
    required List<Fitting> library,
    required this.selectedId,
    required Set<String> collapsed,
    required Map<String, NetworkResult> unitResults,
    required this.seq,
    required List<ProjectSnapshot> undoStack,
    required List<ProjectSnapshot> redoStack,
  })  : units = List.unmodifiable(units),
        library = List.unmodifiable(library),
        collapsed = Set.unmodifiable(collapsed),
        unitResults = Map.unmodifiable(unitResults),
        undoStack = List.unmodifiable(undoStack),
        redoStack = List.unmodifiable(redoStack);

  factory ProjectEditorState.create({
    String? id,
    DuctNode? root,
    List<DuctNode>? units,
    String name = 'Untitled project',
    EngineSettings settings = const EngineSettings(),
    bool imperial = false,
    ReportInfo info = const ReportInfo(),
    List<Fitting> library = const [],
  }) {
    assert(root != null || (units != null && units.isNotEmpty), 'A project needs at least one unit');
    final list = List<DuctNode>.of(units ?? [root!]);
    return ProjectEditorState.internal(
      id: id ?? newProjectId(),
      name: name,
      revision: 0,
      units: list,
      activeUnitId: list.first.id,
      settings: settings,
      imperial: imperial,
      info: info,
      library: library,
      selectedId: null,
      collapsed: const {},
      unitResults: computeAll(list, settings),
      seq: 0,
      undoStack: const [],
      redoStack: const [],
    );
  }

  factory ProjectEditorState.fromDoc(ProjectDoc d) => ProjectEditorState.create(
        id: d.id,
        name: d.name,
        units: d.units,
        settings: d.settings,
        imperial: d.imperial,
        info: d.info,
        library: d.library,
      );

  static const int maxHistory = 100;

  static Map<String, NetworkResult> computeAll(List<DuctNode> units, EngineSettings settings) =>
      {for (final u in units) u.id: computeNetwork(u, settings)};

  final String id;
  final String name;

  /// Bumps on every change that must be saved (not on selection or collapse).
  final int revision;
  final List<DuctNode> units;
  final String activeUnitId;
  final EngineSettings settings;
  final bool imperial;
  final ReportInfo info;
  final List<Fitting> library;
  final String? selectedId;
  final Set<String> collapsed;

  /// Results for every unit, by unit id.
  final Map<String, NetworkResult> unitResults;

  /// Counter behind new section ids. Used by [ProjectEditorDraft].
  final int seq;

  /// Undo and redo history. Used by [ProjectEditorDraft].
  final List<ProjectSnapshot> undoStack, redoStack;

  // ---- reading ----

  /// The unit being viewed and edited. Screens that show one network use this.
  DuctNode get root {
    final i = units.indexWhere((u) => u.id == activeUnitId);
    return units[i < 0 ? 0 : i];
  }

  /// Results for the active unit.
  NetworkResult get result => unitResults[activeUnitId]!;

  /// The calculated result of any section in any unit.
  NodeResult? nodeResult(String id) {
    for (final r in unitResults.values) {
      final n = r.nodes[id];
      if (n != null) return n;
    }
    return null;
  }

  Fmt get fmt => Fmt(imperial);
  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;

  ProjectDoc toDoc() => ProjectDoc(
        id: id,
        name: name,
        imperial: imperial,
        info: info,
        library: List.of(library),
        settings: settings,
        units: List.of(units),
        updatedAt: DateTime.now().toUtc(),
      );

  /// How many of [incoming] have the same name and code as an entry already in the library.
  int countLibraryConflicts(List<Fitting> incoming) =>
      incoming.where((f) => library.any((e) => e.label == f.label)).length;

  // ---- editing: each returns the next state (or this one if nothing changed) ----

  ProjectEditorState _run(void Function(ProjectEditorDraft d) edit) {
    final d = ProjectEditorDraft.from(this);
    edit(d);
    return d.changed ? d.build() : this;
  }

  ProjectEditorState select(String? id) => _run((d) => d.select(id));
  ProjectEditorState toggleCollapsed(String id) => _run((d) => d.toggleCollapsed(id));
  ProjectEditorState undo() => _run((d) => d.undo());
  ProjectEditorState redo() => _run((d) => d.redo());

  ProjectEditorState updateNode(
    String id, {
    String? name,
    double? flow,
    double? lengthM,
    DuctShape? shape,
    DuctMaterial? material,
    double? fixedHeightM,
    bool clearFixedHeight = false,
  }) =>
      _run((d) => d.updateNode(
            id,
            name: name,
            flow: flow,
            lengthM: lengthM,
            shape: shape,
            material: material,
            fixedHeightM: fixedHeightM,
            clearFixedHeight: clearFixedHeight,
          ));

  ProjectEditorState setInsulated(String id, bool v) => _run((d) => d.setInsulated(id, v));
  ProjectEditorState setJunction(String id, JunctionType? type) => _run((d) => d.setJunction(id, type));
  ProjectEditorState chooseSize(String id, DuctSize size) => _run((d) => d.chooseSize(id, size));
  ProjectEditorState clearSize(String id) => _run((d) => d.clearSize(id));

  /// Step a round duct through the standard catalog (dir = -1 / +1).
  ProjectEditorState stepRoundSize(String id, int dir) => _run((d) => d.stepRoundSize(id, dir));

  ProjectEditorState addChild(String parentId) => _run((d) => d.addChild(parentId));
  ProjectEditorState duplicate(String id) => _run((d) => d.duplicate(id));
  ProjectEditorState delete(String id) => _run((d) => d.delete(id));

  ProjectEditorState setActiveUnit(String unitId) => _run((d) => d.setActiveUnit(unitId));

  /// Adds a new unit with one trunk section and makes it the active one. Null if the project
  /// already has the most units allowed.
  ProjectEditorState? addUnit() {
    final d = ProjectEditorDraft.from(this);
    if (d.addUnit() == null) return null;
    return d.build();
  }

  ProjectEditorState renameUnit(String unitId, String newName) => _run((d) => d.renameUnit(unitId, newName));

  /// Copies a unit and makes the copy active. Null if the unit is unknown or the cap is reached.
  ProjectEditorState? duplicateUnit(String unitId) {
    final d = ProjectEditorDraft.from(this);
    if (d.duplicateUnit(unitId) == null) return null;
    return d.build();
  }

  /// Removes a whole unit. The last remaining unit can't be removed.
  ProjectEditorState deleteUnit(String unitId) => _run((d) => d.deleteUnit(unitId));

  ProjectEditorState addFitting(String id, Fitting f) => _run((d) => d.addFitting(id, f));
  ProjectEditorState removeFitting(String id, int index) => _run((d) => d.removeFitting(id, index));

  ProjectEditorState saveToLibrary(Fitting f) => _run((d) => d.saveToLibrary(f));
  ProjectEditorState removeFromLibrary(int index) => _run((d) => d.removeFromLibrary(index));
  ProjectEditorState addFromLibrary(String nodeId, int index, {int count = 1}) =>
      _run((d) => d.addFromLibrary(nodeId, index, count: count));

  /// Merges fittings from a library file as one undoable step. Entries with the same name
  /// and code are kept as they are unless [overwrite] is true.
  LibraryImportOutcome importLibrary(List<Fitting> incoming, {required bool overwrite}) {
    final d = ProjectEditorDraft.from(this);
    final r = d.importLibrary(incoming, overwrite: overwrite);
    return LibraryImportOutcome(
      d.changed ? d.build() : this,
      added: r.added,
      replaced: r.replaced,
      skipped: r.skipped,
    );
  }

  ProjectEditorState setSettings(EngineSettings s) => _run((d) => d.setSettings(s));
  ProjectEditorState setImperial(bool v) => _run((d) => d.setImperial(v));
  ProjectEditorState setInfo(ReportInfo i) => _run((d) => d.setInfo(i));
  ProjectEditorState rename(String newName) => _run((d) => d.rename(newName));
}
