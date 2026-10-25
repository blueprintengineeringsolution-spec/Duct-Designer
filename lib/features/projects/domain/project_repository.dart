import 'package:hvac_engine/hvac_engine.dart';
import 'project_meta.dart';

/// Where projects live. Everything is local, so the app works with no connection.
abstract class ProjectRepository {
  Future<List<ProjectMeta>> list(); // newest first; unreadable projects are skipped
  Future<ProjectDoc?> load(String id); // null if missing; throws if unreadable
  Future<void> save(ProjectDoc doc);
  Future<void> delete(String id);
}
