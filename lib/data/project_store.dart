import 'dart:convert';
import 'dart:io';
import 'package:hvac_engine/hvac_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProjectMeta {
  final String id, name;
  final DateTime updatedAt;
  const ProjectMeta(this.id, this.name, this.updatedAt);
}

/// Where projects live. Everything is local, so the app works with no connection.
abstract class ProjectStore {
  Future<List<ProjectMeta>> list(); // newest first; unreadable projects are skipped
  Future<ProjectDoc?> load(String id); // null if missing; throws if unreadable
  Future<void> save(ProjectDoc doc);
  Future<void> delete(String id);
}

List<ProjectMeta> _sorted(Iterable<ProjectMeta> m) =>
    m.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

class MemoryProjectStore implements ProjectStore {
  final Map<String, String> _docs = {}; // JSON text, so tests exercise serialization

  @override
  Future<List<ProjectMeta>> list() async => _sorted([
        for (final s in _docs.values) _meta(ProjectDoc.fromJson(jsonDecode(s) as Map<String, dynamic>)),
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

ProjectMeta _meta(ProjectDoc d) => ProjectMeta(d.id, d.name, d.updatedAt);

/// One JSON file per project. Writes go to a temp file first and are renamed into
/// place, so a crash mid-save never leaves a half-written project.
class FileProjectStore implements ProjectStore {
  final Directory dir;
  FileProjectStore(this.dir);

  File _file(String id) => File('${dir.path}${Platform.pathSeparator}${id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.json');

  @override
  Future<List<ProjectMeta>> list() async {
    if (!await dir.exists()) return [];
    final out = <ProjectMeta>[];
    await for (final e in dir.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      try {
        out.add(_meta(ProjectDoc.fromJson(jsonDecode(await e.readAsString()) as Map<String, dynamic>)));
      } catch (_) {
        // skip unreadable files
      }
    }
    return _sorted(out);
  }

  @override
  Future<ProjectDoc?> load(String id) async {
    final f = _file(id);
    if (!await f.exists()) return null;
    return ProjectDoc.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
  }

  @override
  Future<void> save(ProjectDoc doc) async {
    await dir.create(recursive: true);
    final f = _file(doc.id);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(doc.toJson()), flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> delete(String id) async {
    final f = _file(id);
    if (await f.exists()) await f.delete();
    final tmp = File('${f.path}.tmp');
    if (await tmp.exists()) await tmp.delete();
  }
}

/// Browser storage (works on every platform, used for web). Browsers keep roughly 5 MB per
/// site and clear it with site data, so export important projects.
class PrefsProjectStore implements ProjectStore {
  static const _prefix = 'ductletor.project.';
  String _key(String id) => '$_prefix${id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';

  @override
  Future<List<ProjectMeta>> list() async {
    final p = await SharedPreferences.getInstance();
    final out = <ProjectMeta>[];
    for (final k in p.getKeys().where((k) => k.startsWith(_prefix))) {
      try {
        out.add(_meta(ProjectDoc.fromJson(jsonDecode(p.getString(k)!) as Map<String, dynamic>)));
      } catch (_) {
        // skip unreadable entries
      }
    }
    return _sorted(out);
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
