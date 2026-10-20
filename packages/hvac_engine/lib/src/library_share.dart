import 'dart:convert';
import 'fittings.dart';
import 'project_codec.dart';
import 'project_share.dart';

const String libraryFormat = 'ductletor-library';
const int librarySchemaVersion = 1;

/// Text for a fitting library file (.ductlib): readable JSON.
String encodeLibraryFile(List<Fitting> fittings, {String name = ''}) => jsonEncode({
      'format': libraryFormat,
      'schema': librarySchemaVersion,
      'name': name,
      'fittings': [
        for (final f in fittings)
          if (f is CustomFitting || f is TableFitting) fittingToJson(f.withCount(1)),
      ],
    });

/// Reads a fitting library from a library file, or from a project file (its library is used).
/// Input is untrusted. Only sourced fittings (custom or table) are kept. Throws [FormatException].
List<Fitting> parseLibraryFile(String text) {
  try {
    final t = text.trim();
    if (t.length > maxSharedBytes) throw const FormatException('The file is too large to be a fitting library');
    final raw = jsonDecode(t);
    if (raw is! Map) throw const FormatException('This is not a Ductletor fitting library');
    final List<Fitting> out;
    if (raw['format'] == libraryFormat) {
      final schema = raw['schema'];
      if (schema is num && schema > librarySchemaVersion) {
        throw FormatException('Library was saved by a newer app version (schema $schema)');
      }
      final list = raw['fittings'];
      if (list is! List) throw const FormatException('The library has no fittings list');
      out = list
          .map(fittingFromJson)
          .whereType<Fitting>()
          .where((f) => f is CustomFitting || f is TableFitting)
          .toList();
    } else if (raw['units'] is List || raw['root'] is Map) {
      out = ProjectDoc.fromJson(Map<String, dynamic>.from(raw)).library;
    } else {
      throw const FormatException('This is not a Ductletor fitting library');
    }
    if (out.isEmpty) throw const FormatException('The file has no sourced fittings');
    final problems = validateLibrary(out);
    if (problems.isNotEmpty) throw FormatException(problems.first);
    return out;
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('Could not read the fitting library');
  }
}
