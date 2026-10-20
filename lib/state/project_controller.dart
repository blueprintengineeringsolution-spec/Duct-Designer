import 'package:flutter/foundation.dart';
import 'package:hvac_engine/hvac_engine.dart';
import '../core/fmt.dart';
import 'tree_ops.dart';

/// Single source of truth: edits rebuild the immutable tree and recompute the whole network.
class ProjectController extends ChangeNotifier {
  ProjectController({
    String? id,
    DuctNode? root,
    List<DuctNode>? units,
    this.name = 'Untitled project',
    EngineSettings settings = const EngineSettings(),
    bool imperial = false,
    ReportInfo info = const ReportInfo(),
    List<Fitting> library = const [],
  })  : assert(root != null || (units != null && units.isNotEmpty), 'A project needs at least one unit'),
        id = id ?? newProjectId(),
        _units = List.of(units ?? [root!]),
        _settings = settings,
        _imperial = imperial,
        _info = info,
        _library = List.of(library) {
    _activeId = _units.first.id;
    _recompute();
  }

  factory ProjectController.fromDoc(ProjectDoc d) => ProjectController(
        id: d.id,
        name: d.name,
        units: d.units,
        settings: d.settings,
        imperial: d.imperial,
        info: d.info,
        library: d.library,
      );

  final String id;
  String name;
  int _revision = 0;
  List<DuctNode> _units;
  late String _activeId;
  EngineSettings _settings;
  bool _imperial;
  ReportInfo _info;
  List<Fitting> _library;
  String? _selectedId;
  final Set<String> _collapsed = {};
  late Map<String, NetworkResult> _results;
  int _seq = 0;

  /// Bumps on every change that must be saved (not on selection or collapse).
  int get revision => _revision;

  ProjectDoc toDoc() => ProjectDoc(
        id: id,
        name: name,
        imperial: _imperial,
        info: _info,
        library: List.of(_library),
        settings: _settings,
        units: List.of(_units),
        updatedAt: DateTime.now().toUtc(),
      );

  ReportInfo get info => _info;

  void setInfo(ReportInfo i) {
    _record();
    _info = i;
    _revision++;
    notifyListeners();
  }

  void setInsulated(String id, bool v) => _edit(id, (n) => n.copyWith(insulated: v));

  void rename(String newName) {
    final n = newName.trim();
    if (n.isEmpty || n == name) return;
    _record();
    name = n;
    _revision++;
    notifyListeners();
  }

  /// The unit being viewed and edited. Screens that show one network use this.
  DuctNode get root => _units[_unitIndexOfId(_activeId)];
  List<DuctNode> get units => List.unmodifiable(_units);
  String get activeUnitId => _activeId;
  EngineSettings get settings => _settings;

  /// Results for the active unit.
  NetworkResult get result => _results[_activeId]!;

  /// Results for every unit, by unit id.
  Map<String, NetworkResult> get unitResults => Map.unmodifiable(_results);

  /// The calculated result of any section in any unit.
  NodeResult? nodeResult(String id) {
    for (final r in _results.values) {
      final n = r.nodes[id];
      if (n != null) return n;
    }
    return null;
  }
  bool get imperial => _imperial;
  Fmt get fmt => Fmt(_imperial);
  String? get selectedId => _selectedId;
  Set<String> get collapsed => Set.unmodifiable(_collapsed);

  int _unitIndexOfId(String unitId) {
    final i = _units.indexWhere((u) => u.id == unitId);
    return i < 0 ? 0 : i;
  }

  /// Index of the unit that contains section [id] (a unit's own id counts), or -1.
  int _unitIndexContaining(String id) => unitIndexContaining(_units, id);

  DuctNode? _find(String id) {
    for (final u in _units) {
      final n = findNode(u, id);
      if (n != null) return n;
    }
    return null;
  }

  void _recompute() {
    _results = {for (final u in _units) u.id: computeNetwork(u, _settings)};
  }

  void _commit() {
    if (!_units.any((u) => u.id == _activeId)) _activeId = _units.first.id;
    if (_selectedId != null && findNode(root, _selectedId!) == null) _selectedId = null;
    _collapsed.removeWhere((id) => _find(id) == null);
    _recompute();
    _revision++;
    notifyListeners();
  }

  // ---- undo / redo ----
  final List<_Snapshot> _undoStack = [];
  final List<_Snapshot> _redoStack = [];
  static const int _maxHistory = 100;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  _Snapshot _snap() => _Snapshot(List.of(_units), _activeId, _settings, _imperial, _info, name, List.of(_library));

  void _restore(_Snapshot s) {
    _units = List.of(s.units);
    _activeId = s.activeId;
    _settings = s.settings;
    _imperial = s.imperial;
    _info = s.info;
    _library = List.of(s.library);
    name = s.name;
  }

  /// Call before any change that should be undoable.
  void _record() {
    _undoStack.add(_snap());
    if (_undoStack.length > _maxHistory) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_snap());
    _restore(_undoStack.removeLast());
    _commit();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_snap());
    _restore(_redoStack.removeLast());
    _commit();
  }

  String _nextId() {
    String id;
    do {
      id = 'n${++_seq}';
    } while (_find(id) != null);
    return id;
  }

  void _edit(String id, DuctNode Function(DuctNode) f) {
    final i = _unitIndexContaining(id);
    if (i < 0) return;
    _record();
    _units[i] = mapNode(_units[i], id, f);
    _commit();
  }

  // ---- selection / view ----
  void select(String? id) {
    _selectedId = id;
    notifyListeners();
  }

  void toggleCollapsed(String id) {
    if (!_collapsed.remove(id)) _collapsed.add(id);
    notifyListeners();
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

  /// Step a round duct through the standard catalog (dir = -1 / +1).
  void stepRoundSize(String id, int dir) {
    final cur = nodeResult(id)?.size.diameterM;
    if (cur == null) return;
    final list = _settings.catalog.roundM;
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
    final id = _nextId();
    _units[ui] = mapNode(_units[ui], parentId, (p) {
      final first = p.children.isEmpty;
      final child = DuctNode(
        id: id,
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
    _collapsed.remove(parentId);
    _selectedId = id;
    _commit();
  }

  void duplicate(String id) {
    final ui = _unitIndexContaining(id);
    if (ui < 0) return;
    final pid = parentIdOf(_units[ui], id); // null for a unit's own root: use duplicateUnit
    final node = findNode(_units[ui], id);
    if (pid == null || node == null) return;
    _record();
    final copy = cloneWithNewIds(node, _nextId);
    _units[ui] = mapNode(_units[ui], pid, (p) => p.copyWith(children: [...p.children, copy]));
    _selectedId = copy.id;
    _commit();
  }

  void delete(String id) {
    final ui = _unitIndexContaining(id);
    if (ui < 0 || _units[ui].id == id) return; // a unit is removed with deleteUnit
    _record();
    _units[ui] = removeNode(_units[ui], id);
    _commit();
  }

  // ---- units (separate air handling units / duct networks) ----
  void setActiveUnit(String unitId) {
    if (!_units.any((u) => u.id == unitId) || unitId == _activeId) return;
    _activeId = unitId;
    _selectedId = null;
    notifyListeners();
  }

  /// Adds a new unit with one trunk section and makes it the active one. Returns its id,
  /// or null if the project already has the most units allowed.
  String? addUnit() {
    if (_units.length >= maxUnits) return null;
    _record();
    final names = _units.map((u) => u.name).toSet();
    var k = 1;
    String name;
    do {
      name = 'AHU-${k.toString().padLeft(2, '0')}';
      k++;
    } while (names.contains(name));
    final uid = _nextId();
    final tid = _nextId();
    _units.add(DuctNode(
      id: uid,
      name: name,
      kind: NodeKind.ahu,
      lengthM: 3,
      children: [DuctNode(id: tid, name: 'Trunk', kind: NodeKind.terminal, flow: 0.5, lengthM: 10)],
    ));
    _activeId = uid;
    _selectedId = null;
    _commit();
    return uid;
  }

  void renameUnit(String unitId, String newName) {
    final n = newName.trim();
    if (n.isEmpty || !_units.any((u) => u.id == unitId)) return;
    updateNode(unitId, name: n);
  }

  String? duplicateUnit(String unitId) {
    final i = _units.indexWhere((u) => u.id == unitId);
    if (i < 0 || _units.length >= maxUnits) return null;
    _record();
    final copy = cloneWithNewIds(_units[i], _nextId);
    _units.insert(i + 1, copy);
    _activeId = copy.id;
    _selectedId = null;
    _commit();
    return copy.id;
  }

  /// Removes a whole unit. The last remaining unit can't be removed.
  void deleteUnit(String unitId) {
    final i = _units.indexWhere((u) => u.id == unitId);
    if (i < 0 || _units.length <= 1) return;
    _record();
    _units.removeAt(i);
    if (_activeId == unitId) {
      _activeId = _units[i < _units.length ? i : _units.length - 1].id;
      _selectedId = null;
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
  List<Fitting> get library => List.unmodifiable(_library);

  /// Saves a sourced fitting for reuse. An entry with the same name and code is replaced.
  void saveToLibrary(Fitting f) {
    if (f is! CustomFitting && f is! TableFitting) return;
    final entry = f.withCount(1);
    final i = _library.indexWhere((e) => e.label == entry.label);
    if (i < 0 && _library.length >= maxLibraryEntries) return;
    _record();
    if (i >= 0) {
      _library[i] = entry;
    } else {
      _library.add(entry);
    }
    _commit();
  }

  /// How many of [incoming] have the same name and code as an entry already in the library.
  int countLibraryConflicts(List<Fitting> incoming) =>
      incoming.where((f) => _library.any((e) => e.label == f.label)).length;

  /// Merges fittings from a library file as one undoable step. Entries with the same name
  /// and code are kept as they are unless [overwrite] is true.
  ({int added, int replaced, int skipped}) importLibrary(List<Fitting> incoming, {required bool overwrite}) {
    var added = 0, replaced = 0, skipped = 0;
    final next = List<Fitting>.of(_library);
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
      _library = next;
      _commit();
    }
    return (added: added, replaced: replaced, skipped: skipped);
  }

  void removeFromLibrary(int index) {
    if (index < 0 || index >= _library.length) return;
    _record();
    _library.removeAt(index);
    _commit();
  }

  /// Adds a copy of a library fitting to a section. Later library edits don't change it.
  void addFromLibrary(String nodeId, int index, {int count = 1}) {
    if (index < 0 || index >= _library.length) return;
    addFitting(nodeId, _library[index].withCount(count < 1 ? 1 : count));
  }

  // ---- project settings ----
  void setSettings(EngineSettings s) {
    _record();
    _settings = s;
    _commit();
  }

  void setImperial(bool v) {
    _record();
    _imperial = v;
    _settings = _settings.copyWith(catalog: v ? SizeCatalog.imperial : SizeCatalog.metric);
    _commit();
  }
}

class _Snapshot {
  final List<DuctNode> units;
  final String activeId;
  final EngineSettings settings;
  final bool imperial;
  final ReportInfo info;
  final String name;
  final List<Fitting> library;
  const _Snapshot(this.units, this.activeId, this.settings, this.imperial, this.info, this.name, this.library);
}
