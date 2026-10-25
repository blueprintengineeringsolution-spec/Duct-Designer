import 'dart:convert';
import 'package:hvac_engine/hvac_engine.dart';
import '../domain/project_meta.dart';
import 'project_data_source.dart';

class MemoryProjectDataSource implements ProjectDataSource {
  final Map<String, String> _docs = {}; // JSON text, so tests exercise serialization

  @override
  Future<List<ProjectMeta>> list() async => sortedNewestFirst([
        for (final s in _docs.values) metaOf(ProjectDoc.fromJson(jsonDecode(s) as Map<String, dynamic>)),
      ]);

  @override
  Future<ProjectDoc?> load(String id) async {
    final s = _docs[id];
    return s == null ? null : ProjectDoc.fromJson(jsonDecode(s) as Map<String, dynamic>);
  }

  @override
  Future<void> save(ProjectDoc doc) async => _docs[doc.id] = jsonEncode(doc.toJson());

  @override
  Future<void> delete(String id) async => _docs.remove(id);
}
