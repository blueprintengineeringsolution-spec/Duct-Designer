import 'package:ductletor_pro/features/project_editor/domain/project_editor_state.dart';
import 'package:ductletor_pro/features/project_editor/presentation/providers/project_editor_provider.dart';
import 'package:ductletor_pro/features/projects/data/memory_project_data_source.dart';
import 'package:ductletor_pro/features/projects/data/project_data_source.dart';
import 'package:ductletor_pro/features/projects/domain/project_meta.dart';
import 'package:ductletor_pro/features/projects/presentation/providers/project_library_notifier.dart';
import 'package:ductletor_pro/features/projects/presentation/providers/project_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hvac_engine/hvac_engine.dart';

/// Test handle on an open project: the same calls and reads the old controller had, backed by
/// the real editor provider in a [ProviderContainer].
class TestProject {
  TestProject({
    String? id,
    DuctNode? root,
    List<DuctNode>? units,
    String name = 'Untitled project',
    EngineSettings settings = const EngineSettings(),
    bool imperial = false,
    ReportInfo info = const ReportInfo(),
    List<Fitting> library = const [],
  }) : this.fromState(ProjectEditorState.create(
          id: id, root: root, units: units, name: name, settings: settings,
          imperial: imperial, info: info, library: library,
        ));

  TestProject.fromDoc(ProjectDoc d) : this.fromState(ProjectEditorState.fromDoc(d));

  TestProject.fromState(ProjectEditorState s)
      : container = ProviderContainer(overrides: [
          projectEditorProvider.overrideWith(() => ProjectEditorNotifier(initial: s)),
        ]);

  /// The project open in an existing container.
  TestProject.of(this.container);

  final ProviderContainer container;

  ProjectEditorNotifier get _n => container.read(projectEditorProvider.notifier);
  ProjectEditorState get s => container.read(projectEditorProvider)!;

  /// Wraps [child] so it reads this project.
  Widget app(Widget child) => UncontrolledProviderScope(container: container, child: MaterialApp(home: child));

  // reads
  String get id => s.id;
  String get name => s.name;
  int get revision => s.revision;
  DuctNode get root => s.root;
  List<DuctNode> get units => s.units;
  String get activeUnitId => s.activeUnitId;
  EngineSettings get settings => s.settings;
  NetworkResult get result => s.result;
  Map<String, NetworkResult> get unitResults => s.unitResults;
  NodeResult? nodeResult(String id) => s.nodeResult(id);
  bool get imperial => s.imperial;
  get fmt => s.fmt;
  ReportInfo get info => s.info;
  List<Fitting> get library => s.library;
  String? get selectedId => s.selectedId;
  Set<String> get collapsed => s.collapsed;
  bool get canUndo => s.canUndo;
  bool get canRedo => s.canRedo;
  ProjectDoc toDoc() => s.toDoc();
  int countLibraryConflicts(List<Fitting> f) => s.countLibraryConflicts(f);

  // edits
  void undo() => _n.undo();
  void redo() => _n.redo();
  void select(String? id) => _n.select(id);
  void toggleCollapsed(String id) => _n.toggleCollapsed(id);
  void updateNode(String id, {String? name, double? flow, double? lengthM, DuctShape? shape, DuctMaterial? material, double? fixedHeightM, bool clearFixedHeight = false}) =>
      _n.updateNode(id, name: name, flow: flow, lengthM: lengthM, shape: shape, material: material, fixedHeightM: fixedHeightM, clearFixedHeight: clearFixedHeight);
  void setInsulated(String id, bool v) => _n.setInsulated(id, v);
  void setJunction(String id, JunctionType? t) => _n.setJunction(id, t);
  void chooseSize(String id, DuctSize size) => _n.chooseSize(id, size);
  void clearSize(String id) => _n.clearSize(id);
  void stepRoundSize(String id, int dir) => _n.stepRoundSize(id, dir);
  void addChild(String id) => _n.addChild(id);
  void duplicate(String id) => _n.duplicate(id);
  void delete(String id) => _n.delete(id);
  void setActiveUnit(String id) => _n.setActiveUnit(id);
  String? addUnit() => _n.addUnit();
  void renameUnit(String id, String n) => _n.renameUnit(id, n);
  String? duplicateUnit(String id) => _n.duplicateUnit(id);
  void deleteUnit(String id) => _n.deleteUnit(id);
  void addFitting(String id, Fitting f) => _n.addFitting(id, f);
  void removeFitting(String id, int i) => _n.removeFitting(id, i);
  void saveToLibrary(Fitting f) => _n.saveToLibrary(f);
  void removeFromLibrary(int i) => _n.removeFromLibrary(i);
  void addFromLibrary(String id, int i, {int count = 1}) => _n.addFromLibrary(id, i, count: count);
  ({int added, int replaced, int skipped}) importLibrary(List<Fitting> f, {required bool overwrite}) =>
      _n.importLibrary(f, overwrite: overwrite);
  void setSettings(EngineSettings v) => _n.setSettings(v);
  void setImperial(bool v) => _n.setImperial(v);
  void setInfo(ReportInfo v) => _n.setInfo(v);
  void rename(String v) => _n.rename(v);
}

/// Test handle on the project library, backed by an in-memory store.
class TestLibrary {
  TestLibrary({ProjectDataSource? source, Duration debounce = const Duration(milliseconds: 10)})
      : this._(source ?? MemoryProjectDataSource(), debounce);

  TestLibrary._(this.source, Duration debounce)
      : container = ProviderContainer(overrides: [
          projectDataSourceProvider.overrideWithValue(source),
          saveDebounceProvider.overrideWithValue(debounce),
        ]);

  final ProjectDataSource source;
  final ProviderContainer container;

  ProjectLibraryNotifier get _n => container.read(projectLibraryProvider.notifier);
  List<ProjectMeta> get projects => container.read(projectLibraryProvider).projects;
  TestProject? get active => container.read(projectEditorProvider) == null ? null : TestProject.of(container);

  Future<void> init() => _n.init();
  Future<bool> open(String id) => _n.open(id);
  Future<void> create(String name, {bool sample = false}) => _n.create(name, sample: sample);
  Future<void> rename(String id, String name) => _n.rename(id, name);
  Future<void> duplicate(String id) => _n.duplicate(id);
  Future<void> delete(String id) => _n.delete(id);
  Future<void> flush() => _n.flush();
  Future<ProjectDoc?> docFor(String id) => _n.docFor(id);
  Future<void> importShared(ProjectDoc d) => _n.importShared(d);
}
