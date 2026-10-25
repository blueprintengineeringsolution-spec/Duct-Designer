import 'package:hvac_engine/hvac_engine.dart';
import 'project_editor_state.dart';
import 'tree_ops.dart';

/// A mutable working copy of a [ProjectEditorState] that one edit is applied to.
/// [ProjectEditorState] makes a draft, runs the edit and turns the draft back into a new
/// immutable state. Every rule of the editor lives here. Not used outside the domain layer.
class ProjectEditorDraft {
  ProjectEditorDraft.from(ProjectEditorState s)
      : id = s.id,
        name = s.name,
        revision = s.revision,
        units = List.of(s.units),
        activeId = s.activeUnitId,
        settings = s.settings,
        imperial = s.imperial,
        info = s.info,
        library = List.of(s.library),
        selectedId = s.selectedId,
        collapsed = Set.of(s.collapsed),
        results = s.unitResults,
        seq = s.seq,
        undoStack = List.of(s.undoStack),
        redoStack = List.of(s.redoStack);

  final String id;
  String name;
  int revision;
  List<DuctNode> units;
  String activeId;
  EngineSettings settings;
  bool imperial;
  ReportInfo info;
  List<Fitting> library;
  String? selectedId;
  final Set<String> collapsed;
  Map<String, NetworkResult> results;
  int seq;
  final List<ProjectSnapshot> undoStack, redoStack;

  /// True once the edit changed anything a screen could show.
  bool changed = false;

  ProjectEditorState build() => ProjectEditorState.internal(
        id: id,
        name: name,
        revision: revision,
        units: units,
        activeUnitId: activeId,
        settings: settings,
        imperial: imperial,
        info: info,
        library: library,
        selectedId: selectedId,
        collapsed: collapsed,
        unitResults: results,
        seq: seq,
        undoStack: undoStack,
        redoStack: redoStack,
      );

  // ---- lookups ----

  DuctNode get _root => units[_unitIndexOfId(activeId)];

  int _unitIndexOfId(String unitId) {
    final i = units.indexWhere((u) => u.id == unitId);
    return i < 0 ? 0 : i;
  }

  /// Index of the unit that contains section [id] (a unit's own id counts), or -1.
  int _unitIndexContaining(String id) => unitIndexContaining(units, id);

  DuctNode? _find(String id) {
    for (final u in units) {
      final n = findNode(u, id);
      if (n != null) return n;
    }
    return null;
  }

  NodeResult? _nodeResult(String id) {
    for (final r in results.values) {
      final n = r.nodes[id];
      if (n != null) return n;
    }
    return null;
  }

  void _recompute() {
    results = ProjectEditorState.computeAll(units, settings);
  }

  void _commit() {
    if (!units.any((u) => u.id == activeId)) activeId = units.first.id;
    if (selectedId != null && findNode(_root, selectedId!) == null) selectedId = null;
    collapsed.removeWhere((id) => _find(id) == null);
    _recompute();
    revision++;
    changed = true;
  }

  // ---- undo / redo ----

  ProjectSnapshot _snap() => ProjectSnapshot(List.of(units), activeId, settings, imperial, info, name, List.of(library));

  void _restore(ProjectSnapshot s) {
    units = List.of(s.units);
    activeId = s.activeId;
    settings = s.settings;
    imperial = s.imperial;
    info = s.info;
    library = List.of(s.library);
    name = s.name;
  }

  /// Call before any change that should be undoable.
  void _record() {
    undoStack.add(_snap());
    if (undoStack.length > ProjectEditorState.maxHistory) undoStack.removeAt(0);
    redoStack.clear();
  }

  void undo() {
    if (undoStack.isEmpty) return;
    redoStack.add(_snap());
    _restore(undoStack.removeLast());
    _commit();
  }

  void redo() {
    if (redoStack.isEmpty) return;
    undoStack.add(_snap());
    _restore(redoStack.removeLast());
    _commit();
  }

  String _nextId() {
    String candidate;
    do {
      candidate = 'n${++seq}';
    } while (_find(candidate) != null);
    return candidate;
  }

  void _edit(String id, DuctNode Function(DuctNode) f) {
    final i = _unitIndexContaining(id);
    if (i < 0) return;
    _record();
    units[i] = mapNode(units[i], id, f);
    _commit();
  }

  // ---- selection / view ----

  void select(String? id) {
    selectedId = id;
    changed = true;
  }

  void toggleCollapsed(String id) {
    if (!collapsed.remove(id)) collapsed.add(id);
    changed = true;
  }

  // ---- node edits ----

  /// Sizing-affecting fields (flow, shape, material, height) clear a picked size.
  void updateNode(
    String id, {
    String? name,
    double? flow,
    double? lengthM,
    DuctShape? shape,
    DuctMaterial? material,
    double? fixedHeightM,
    bool clearFixedHeight = false,
  }) {
    final resets = flow != null || shape != null || material != null || fixedHeightM != null || clearFixedHeight;
    _edit(
      id,
      (n) => n.copyWith(
        name: name,
        flow: flow == null ? null : (flow < 0 ? 0 : flow),
        lengthM: lengthM == null ? null : (lengthM < 0 ? 0 : lengthM),
        shape: shape,
        material: material,
        fixedHeightM: fixedHeightM,
        clearFixedHeight: clearFixedHeight,
        clearSizeOverride: resets,
      ),
    );
  }

  void setInsulated(String id, bool v) => _edit(id, (n) => n.copyWith(insulated: v));

  void setJunction(String id, JunctionType? type) =>
      _edit(id, (n) => type == null ? n.copyWith(clearJunction: true) : n.copyWith(junction: type));

  void chooseSize(String id, DuctSize size) {
    _edit(id, (n) => n.copyWith(
          sizeOverride: size,
          shape: size.shape,
          clearFixedHeight: size.shape == DuctShape.round,
        ));
  }

  void clearSize(String id) => _edit(id, (n) => n.copyWith(clearSizeOverride: true));

  void stepRoundSize(String id, int dir) {
    final cur = _nodeResult(id)?.size.diameterM;
    if (cur == null) return;
    final list = settings.catalog.roundM;
    var best = 0;
    for (var i = 0; i < list.length; i++) {
      if ((list[i] - cur).abs() < (list[best] - cur).abs()) best = i;
    }
    final next = (best + dir).clamp(0, list.length - 1);
    chooseSize(id, DuctSize.round(list[next]));
  }

  // ---- tree structure ----

  void addChild(String parentId) {
    final ui = _unitIndexContaining(parentId);
    if (ui < 0) return;
    _record();
    final childId = _nextId();
    units[ui] = mapNode(units[ui], parentId, (p) {
      final first = p.children.isEmpty;
      final child = DuctNode(
        id: childId,
        name: first ? 'Section ${p.children.length + 1}' : 'Branch ${p.children.length + 1}',
        kind: NodeKind.terminal,
        flow: first && p.flow > 0 ? p.flow : 0.1,
        lengthM: 5,
        material: p.material,
      );
      return p.copyWith(
        kind: p.kind == NodeKind.terminal ? NodeKind.branch : p.kind,
        children: [...p.children, child],
      );
    });
    collapsed.remove(parentId);
    selectedId = childId;
    _commit();
  }

  void duplicate(String id) {
    final ui = _unitIndexContaining(id);
    if (ui < 0) return;
    final pid = parentIdOf(units[ui], id); // null for a unit's own root: use duplicateUnit
    final node = findNode(units[ui], id);
    if (pid == null || node == null) return;
    _record();
    final copy = cloneWithNewIds(node, _nextId);
    units[ui] = mapNode(units[ui], pid, (p) => p.copyWith(children: [...p.children, copy]));
    selectedId = copy.id;
    _commit();
  }

  void delete(String id) {
    final ui = _unitIndexContaining(id);
    if (ui < 0 || units[ui].id == id) return; // a unit is removed with deleteUnit
    _record();
    units[ui] = removeNode(units[ui], id);
    _commit();
  }

  // ---- units (separate air handling units / duct networks) ----

  void setActiveUnit(String unitId) {
    if (!units.any((u) => u.id == unitId) || unitId == activeId) return;
    activeId = unitId;
    selectedId = null;
    changed = true;
  }

  /// Returns the new unit's id, or null if the project already has the most units allowed.
  String? addUnit() {
    if (units.length >= maxUnits) return null;
    _record();
    final names = units.map((u) => u.name).toSet();
    var k = 1;
    String unitName;
    do {
      unitName = 'AHU-${k.toString().padLeft(2, '0')}';
      k++;
    } while (names.contains(unitName));
    final uid = _nextId();
    final tid = _nextId();
    units.add(DuctNode(
      id: uid,
      name: unitName,
      kind: NodeKind.ahu,
      lengthM: 3,
      children: [DuctNode(id: tid, name: 'Trunk', kind: NodeKind.terminal, flow: 0.5, lengthM: 10)],
    ));
    activeId = uid;
    selectedId = null;
    _commit();
    return uid;
  }

  void renameUnit(String unitId, String newName) {
    final n = newName.trim();
    if (n.isEmpty || !units.any((u) => u.id == unitId)) return;
    updateNode(unitId, name: n);
  }

  String? duplicateUnit(String unitId) {
    final i = units.indexWhere((u) => u.id == unitId);
    if (i < 0 || units.length >= maxUnits) return null;
    _record();
    final copy = cloneWithNewIds(units[i], _nextId);
    units.insert(i + 1, copy);
    activeId = copy.id;
    selectedId = null;
    _commit();
    return copy.id;
  }

  void deleteUnit(String unitId) {
    final i = units.indexWhere((u) => u.id == unitId);
    if (i < 0 || units.length <= 1) return;
    _record();
    units.removeAt(i);
    if (activeId == unitId) {
      activeId = units[i < units.length ? i : units.length - 1].id;
      selectedId = null;
    }
    _commit();
  }

  // ---- fittings ----

  void addFitting(String id, Fitting f) => _edit(id, (n) => n.copyWith(fittings: [...n.fittings, f]));

  void removeFitting(String id, int index) => _edit(id, (n) {
        final list = [...n.fittings];
        if (index >= 0 && index < list.length) list.removeAt(index);
        return n.copyWith(fittings: list);
      });

  // ---- fitting library (reusable sourced fittings) ----

  /// Saves a sourced fitting for reuse. An entry with the same name and code is replaced.
  void saveToLibrary(Fitting f) {
    if (f is! CustomFitting && f is! TableFitting) return;
    final entry = f.withCount(1);
    final i = library.indexWhere((e) => e.label == entry.label);
    if (i < 0 && library.length >= maxLibraryEntries) return;
    _record();
    if (i >= 0) {
      library[i] = entry;
    } else {
      library.add(entry);
    }
    _commit();
  }

  ({int added, int replaced, int skipped}) importLibrary(List<Fitting> incoming, {required bool overwrite}) {
    var added = 0, replaced = 0, skipped = 0;
    final next = List<Fitting>.of(library);
    for (final f in incoming) {
      if (f is! CustomFitting && f is! TableFitting) {
        skipped++;
        continue;
      }
      final e = f.withCount(1);
      final i = next.indexWhere((x) => x.label == e.label);
      if (i >= 0) {
        if (overwrite) {
          next[i] = e;
          replaced++;
        } else {
          skipped++;
        }
      } else if (next.length >= maxLibraryEntries) {
        skipped++;
      } else {
        next.add(e);
        added++;
      }
    }
    if (added > 0 || replaced > 0) {
      _record();
      library = next;
      _commit();
    }
    return (added: added, replaced: replaced, skipped: skipped);
  }

  void removeFromLibrary(int index) {
    if (index < 0 || index >= library.length) return;
    _record();
    library.removeAt(index);
    _commit();
  }

  /// Adds a copy of a library fitting to a section. Later library edits don't change it.
  void addFromLibrary(String nodeId, int index, {int count = 1}) {
    if (index < 0 || index >= library.length) return;
    addFitting(nodeId, library[index].withCount(count < 1 ? 1 : count));
  }

  // ---- project settings, details and name ----

  void setSettings(EngineSettings s) {
    _record();
    settings = s;
    _commit();
  }

  void setImperial(bool v) {
    _record();
    imperial = v;
    settings = settings.copyWith(catalog: v ? SizeCatalog.imperial : SizeCatalog.metric);
    _commit();
  }

  void setInfo(ReportInfo i) {
    _record();
    info = i;
    revision++;
    changed = true;
  }

  void rename(String newName) {
    final n = newName.trim();
    if (n.isEmpty || n == name) return;
    _record();
    name = n;
    revision++;
    changed = true;
  }
}
