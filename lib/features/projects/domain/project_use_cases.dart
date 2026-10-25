import 'package:hvac_engine/hvac_engine.dart';
import 'project_meta.dart';
import 'project_repository.dart';
import 'sample_projects.dart';

class ListProjects {
  const ListProjects(this._repository);
  final ProjectRepository _repository;
  Future<List<ProjectMeta>> call() => _repository.list();
}

class LoadProject {
  const LoadProject(this._repository);
  final ProjectRepository _repository;
  Future<ProjectDoc?> call(String id) => _repository.load(id);
}

class DeleteProject {
  const DeleteProject(this._repository);
  final ProjectRepository _repository;
  Future<void> call(String id) => _repository.delete(id);
}

/// Saves a brand new project (blank, or the sample) and returns it.
class CreateProject {
  const CreateProject(this._repository);
  final ProjectRepository _repository;

  Future<ProjectDoc> call(String name, {bool sample = false}) async {
    final trimmed = name.trim();
    final doc = ProjectDoc(
      id: newProjectId(),
      name: trimmed.isEmpty ? 'Untitled project' : trimmed,
      imperial: false,
      settings: const EngineSettings(),
      root: sample ? sampleProject() : blankProject(),
      updatedAt: DateTime.now().toUtc(),
    );
    await _repository.save(doc);
    return doc;
  }
}

/// Renames a project that is not open (the open one is renamed through the editor).
class RenameStoredProject {
  const RenameStoredProject(this._repository);
  final ProjectRepository _repository;

  Future<void> call(String id, String name) async {
    final d = await _repository.load(id);
    if (d == null) return;
    await _repository.save(ProjectDoc(
      id: d.id,
      name: name,
      imperial: d.imperial,
      settings: d.settings,
      units: d.units,
      updatedAt: DateTime.now().toUtc(),
      info: d.info,
      library: d.library,
    ));
  }
}

/// Saves a copy of a stored project under a new id.
class DuplicateProject {
  const DuplicateProject(this._repository);
  final ProjectRepository _repository;

  Future<void> call(String id) async {
    final d = await _repository.load(id);
    if (d == null) return;
    await _repository.save(ProjectDoc(
      id: newProjectId(),
      name: '${d.name} copy',
      imperial: d.imperial,
      settings: d.settings,
      units: d.units,
      updatedAt: DateTime.now().toUtc(),
      info: d.info,
      library: d.library,
    ));
  }
}

/// Adds a project that came from outside as a new local copy and returns it.
class ImportSharedProject {
  const ImportSharedProject(this._repository);
  final ProjectRepository _repository;

  Future<ProjectDoc> call(ProjectDoc d) async {
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
    await _repository.save(doc);
    return doc;
  }
}
