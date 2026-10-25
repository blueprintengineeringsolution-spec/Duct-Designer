import 'package:hvac_engine/hvac_engine.dart';
import '../domain/project_meta.dart';

/// Raw project storage behind the repository. Same contract as the repository:
/// `list` is newest first and skips unreadable projects; `load` returns null if missing
/// and throws if unreadable.
abstract class ProjectDataSource {
  Future<List<ProjectMeta>> list();
  Future<ProjectDoc?> load(String id);
  Future<void> save(ProjectDoc doc);
  Future<void> delete(String id);
}

List<ProjectMeta> sortedNewestFirst(Iterable<ProjectMeta> m) =>
    m.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

ProjectMeta metaOf(ProjectDoc d) => ProjectMeta(d.id, d.name, d.updatedAt);
