import 'package:hvac_engine/hvac_engine.dart';
import '../domain/project_meta.dart';
import '../domain/project_repository.dart';
import 'project_data_source.dart';

class ProjectRepositoryImpl implements ProjectRepository {
  const ProjectRepositoryImpl(this._source);
  final ProjectDataSource _source;

  @override
  Future<List<ProjectMeta>> list() => _source.list();

  @override
  Future<ProjectDoc?> load(String id) => _source.load(id);

  @override
  Future<void> save(ProjectDoc doc) => _source.save(doc);

  @override
  Future<void> delete(String id) => _source.delete(id);
}
