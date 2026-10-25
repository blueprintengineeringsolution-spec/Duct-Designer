import 'dart:convert';
import 'dart:io';
import 'package:hvac_engine/hvac_engine.dart';
import '../domain/project_meta.dart';
import 'project_data_source.dart';

/// One JSON file per project. Writes go to a temp file first and are renamed into
/// place, so a crash mid-save never leaves a half-written project.
class FileProjectDataSource implements ProjectDataSource {
  /// Stores projects in [dir].
  FileProjectDataSource(Directory dir) : _resolve = (() async => dir);

  /// Works out the folder on first use (for example from the app's documents folder).
  FileProjectDataSource.lazy(Future<Directory> Function() resolve) : _resolve = resolve;

  final Future<Directory> Function() _resolve;
  Directory? _dir;

  Future<Directory> _directory() async => _dir ??= await _resolve();

  File _file(Directory dir, String id) =>
      File('${dir.path}${Platform.pathSeparator}${id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.json');

  @override
  Future<List<ProjectMeta>> list() async {
    final dir = await _directory();
    if (!await dir.exists()) return [];
    final out = <ProjectMeta>[];
    await for (final e in dir.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      try {
        out.add(metaOf(ProjectDoc.fromJson(jsonDecode(await e.readAsString()) as Map<String, dynamic>)));
      } catch (_) {
        // skip unreadable files
      }
    }
    return sortedNewestFirst(out);
  }

  @override
  Future<ProjectDoc?> load(String id) async {
    final f = _file(await _directory(), id);
    if (!await f.exists()) return null;
    return ProjectDoc.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
  }

  @override
  Future<void> save(ProjectDoc doc) async {
    final dir = await _directory();
    await dir.create(recursive: true);
    final f = _file(dir, doc.id);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(doc.toJson()), flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> delete(String id) async {
    final f = _file(await _directory(), id);
    if (await f.exists()) await f.delete();
    final tmp = File('${f.path}.tmp');
    if (await tmp.exists()) await tmp.delete();
  }
}
