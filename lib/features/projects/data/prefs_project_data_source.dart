import 'dart:convert';
import 'package:hvac_engine/hvac_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/project_meta.dart';
import 'project_data_source.dart';

/// Browser storage (works on every platform, used for web). Browsers keep roughly 5 MB per
/// site and clear it with site data, so export important projects.
class PrefsProjectDataSource implements ProjectDataSource {
  static const _prefix = 'ductletor.project.';
  String _key(String id) => '$_prefix${id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';

  @override
  Future<List<ProjectMeta>> list() async {
    final p = await SharedPreferences.getInstance();
    final out = <ProjectMeta>[];
    for (final k in p.getKeys().where((k) => k.startsWith(_prefix))) {
      try {
        out.add(metaOf(ProjectDoc.fromJson(jsonDecode(p.getString(k)!) as Map<String, dynamic>)));
      } catch (_) {
        // skip unreadable entries
      }
    }
    return sortedNewestFirst(out);
  }

  @override
  Future<ProjectDoc?> load(String id) async {
    final s = (await SharedPreferences.getInstance()).getString(_key(id));
    return s == null ? null : ProjectDoc.fromJson(jsonDecode(s) as Map<String, dynamic>);
  }

  @override
  Future<void> save(ProjectDoc doc) async {
    final ok = await (await SharedPreferences.getInstance()).setString(_key(doc.id), jsonEncode(doc.toJson()));
    if (!ok) throw StateError('The browser would not store the project (storage may be full)');
  }

  @override
  Future<void> delete(String id) async {
    await (await SharedPreferences.getInstance()).remove(_key(id));
  }
}
