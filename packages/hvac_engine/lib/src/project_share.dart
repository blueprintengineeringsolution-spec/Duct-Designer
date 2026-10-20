import 'dart:convert';
import 'gzip_io.dart' if (dart.library.js_interop) 'gzip_web.dart' if (dart.library.html) 'gzip_web.dart';
import 'project_codec.dart';
import 'network.dart';
import 'sizing.dart';
import 'fittings.dart';

/// Largest project text accepted (and the cap on what a code may expand to).
const int maxSharedBytes = 5 * 1024 * 1024;

/// Longest share code that still makes a QR code that scans reliably.
const int maxQrChars = 2300;

const String _codePrefix = 'DUCT1:';

bool fitsInQr(String code) => code.length <= maxQrChars;

/// Compact text form of a project (gzip + base64) for QR codes and pasting.
Future<String> encodeShareCode(ProjectDoc d) async {
  final bytes = utf8.encode(jsonEncode(d.toJson()));
  return '$_codePrefix${base64Url.encode(await gzipEncodeBytes(bytes))}';
}

/// Reads a project from a share code or from project file text (JSON).
/// Input is untrusted: size, depth and value ranges are checked. Throws [FormatException].
Future<ProjectDoc> parseShared(String text) async {
  try {
    final t = text.trim();
    final String json;
    if (t.startsWith('{')) {
      if (t.length > maxSharedBytes) throw const FormatException('The file is too large to be a project');
      json = t;
    } else if (t.startsWith(_codePrefix)) {
      final packed = base64Url.decode(base64Url.normalize(t.substring(_codePrefix.length)));
      if (packed.length > maxSharedBytes) throw const FormatException('The code is too large to be a project');
      json = utf8.decode(await gzipDecodeCapped(packed, maxSharedBytes));
    } else {
      throw const FormatException('This is not a Ductletor project');
    }
    final raw = jsonDecode(json);
    if (raw is! Map) throw const FormatException('This is not a Ductletor project');
    final doc = ProjectDoc.fromJson(Map<String, dynamic>.from(raw));
    final problems = validateProject(doc);
    if (problems.isNotEmpty) throw FormatException(problems.take(3).join('; '));
    return doc;
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('Could not read the shared project');
  }
}

bool _ok(double v, double lo, double hi) => v.isFinite && v >= lo && v <= hi;

/// Range and structure checks for a project that came from outside the app.
List<String> validateProject(ProjectDoc d, {int maxNodes = 2000}) {
  final problems = <String>[];
  final ids = <String>{};

  void size(String id, DuctSize? s) {
    if (s == null) return;
    final dims = s.shape == DuctShape.round ? [s.diameterM!] : [s.widthM!, s.heightM!];
    if (dims.any((v) => !_ok(v, 0.02, 5))) problems.add('Section "$id" has an unrealistic duct size');
  }

  void walk(DuctNode n) {
    if (!ids.add(n.id)) problems.add('Duplicate section id "${n.id}"');
    if (!_ok(n.flow, 0, 1000)) problems.add('Section "${n.id}" has an invalid flow');
    if (!_ok(n.lengthM, 0, 10000)) problems.add('Section "${n.id}" has an invalid length');
    if (!_ok(n.fittingC, 0, 100)) problems.add('Section "${n.id}" has an invalid fitting coefficient');
    if (!_ok(n.flexSlack, 0, 1)) problems.add('Section "${n.id}" has an invalid flex slack');
    if (!_ok(n.equipmentDropPa, 0, 100000)) problems.add('Section "${n.id}" has an invalid equipment loss');
    if (n.fixedHeightM != null && !_ok(n.fixedHeightM!, 0.02, 5)) problems.add('Section "${n.id}" has an invalid height');
    size(n.id, n.sizeOverride);
    for (final f in n.fittings) {
      if (f.count < 1 || f.count > 999) problems.add('Section "${n.id}" has an invalid fitting quantity');
      if (f is CustomFitting && !_ok(f.c, 0, 100)) problems.add('Section "${n.id}" has an invalid fitting coefficient');
      if (f is Elbow && !(_ok(f.angleDeg, 1, 180) && _ok(f.radiusRatio, 0.1, 10))) {
        problems.add('Section "${n.id}" has an invalid elbow');
      }
      if (f is Reducer && !_ok(f.angleDeg, 1, 180)) problems.add('Section "${n.id}" has an invalid reducer');
      if (f is CustomFitting && (f.name.length > 120 || f.code.length > 120 || f.source.length > 120)) {
        problems.add('Section "${n.id}" has a fitting with text that is too long');
      }
      if (f is TableFitting) {
        if (f.name.length > 120 || f.code.length > 120 || f.source.length > 120) {
          problems.add('Section "${n.id}" has a fitting with text that is too long');
        }
        if (!_ok(f.x, -1e6, 1e6)) problems.add('Section "${n.id}" has an invalid table input');
      }
    }
    for (final c in n.children) {
      if (ids.length > maxNodes) return;
      walk(c);
    }
  }

  if (d.units.length > maxUnits) problems.add('The project has too many units');
  for (final u in d.units) {
    walk(u);
  }
  if (ids.length > maxNodes) problems.add('The network has too many sections');

  final s = d.settings;
  if (!_ok(s.frictionPaPerM, 0.01, 50)) problems.add('Invalid pressure-drop target');
  if (!_ok(s.constantVelocity, 0.5, 40)) problems.add('Invalid velocity target');
  if (!_ok(s.maxVelocity, 1, 60)) problems.add('Invalid maximum velocity');
  if (!_ok(s.maxAspect, 1, 20)) problems.add('Invalid aspect-ratio limit');
  if (!_ok(s.air.density, 0.3, 3)) problems.add('Invalid air density');
  if (!_ok(s.air.dynamicViscosity, 1e-6, 1e-3)) problems.add('Invalid air viscosity');
  if (s.maxRectHeightM != null && !_ok(s.maxRectHeightM!, 0.05, 5)) problems.add('Invalid maximum height');
  if (s.velocitySteps.any((v) => !_ok(v, 0.5, 40))) problems.add('Invalid velocity steps');
  if (!_ok(d.info.wastePercent, 0, 50)) problems.add('Invalid waste allowance');
  problems.addAll(validateLibrary(d.library));
  return problems;
}

/// Size and text checks for a fitting library that came from outside the app.
List<String> validateLibrary(List<Fitting> library) {
  final problems = <String>[];
  if (library.length > maxLibraryEntries) problems.add('The fitting library has too many entries');
  for (final f in library) {
    final long = f is CustomFitting
        ? (f.name.length > 120 || f.code.length > 120 || f.source.length > 120)
        : f is TableFitting && (f.name.length > 120 || f.code.length > 120 || f.source.length > 120);
    if (long) {
      problems.add('A library fitting has text that is too long');
      break;
    }
  }
  return problems;
}
