import 'acoustics.dart';
import 'duct_math.dart';
import 'fittings.dart';
import 'network.dart';
import 'sizing.dart';

/// Bump when the saved shape changes; add a migration in [ProjectDoc.fromJson].
const int projectSchemaVersion = 2;

/// Deepest nesting accepted when reading a network (guards against hostile files).
const int maxNodeDepth = 64;

/// Most reusable fittings a project may keep in its library.
const int maxLibraryEntries = 200;

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

double _d(Object? v, double fallback) => v is num ? v.toDouble() : fallback;
double? _dn(Object? v) => v is num ? v.toDouble() : null;
int _i(Object? v, int fallback) => v is num ? v.toInt() : fallback;
bool _b(Object? v, bool fallback) => v is bool ? v : fallback;
String _s(Object? v) => v is String ? v : '';

Map<String, dynamic> sizeToJson(DuctSize s) => s.shape == DuctShape.round
    ? {'shape': 'round', 'diameterM': s.diameterM}
    : {'shape': 'rectangular', 'widthM': s.widthM, 'heightM': s.heightM};

DuctSize? sizeFromJson(Object? j) {
  if (j is! Map) return null;
  if (j['shape'] == 'rectangular') {
    final w = _dn(j['widthM']), h = _dn(j['heightM']);
    return (w == null || h == null) ? null : DuctSize.rect(w, h);
  }
  final d = _dn(j['diameterM']);
  return d == null ? null : DuctSize.round(d);
}

Map<String, dynamic> fittingToJson(Fitting f) {
  if (f is Elbow) {
    return {'type': 'elbow', 'angleDeg': f.angleDeg, 'radiusRatio': f.radiusRatio, 'style': f.style.name, 'count': f.count};
  }
  if (f is Reducer) {
    return {'type': 'reducer', 'angleDeg': f.angleDeg, 'count': f.count};
  }
  if (f is CustomFitting) {
    return {
      'type': 'custom', 'name': f.name, 'code': f.code, 'source': f.source, 'c': f.c,
      'reference': f.reference.name, 'kind': f.kind.name, 'count': f.count,
    };
  }
  if (f is TableFitting) {
    return {
      'type': 'table', 'name': f.name, 'code': f.code, 'source': f.source,
      'input': f.input.name, 'x': f.x, 'points': f.table.toJson(),
      'reference': f.reference.name, 'kind': f.kind.name, 'count': f.count,
    };
  }
  throw ArgumentError('Cannot save fitting of type ${f.runtimeType}');
}

Fitting? fittingFromJson(Object? j) {
  if (j is! Map) return null;
  final n = _i(j['count'], 1);
  final count = n < 1 ? 1 : n;
  switch (j['type']) {
    case 'elbow':
      return Elbow(
        angleDeg: _d(j['angleDeg'], 90),
        radiusRatio: _d(j['radiusRatio'], 1.0),
        style: _enum(ElbowStyle.values, j['style'], ElbowStyle.smoothRadius),
        count: count,
      );
    case 'reducer':
      return Reducer(angleDeg: _d(j['angleDeg'], 30), count: count);
    case 'custom':
      return CustomFitting(
        name: j['name'] is String ? j['name'] as String : 'Fitting',
        code: _s(j['code']),
        source: _s(j['source']),
        c: _d(j['c'], 0),
        reference: _enum(ReferenceVelocity.values, j['reference'], ReferenceVelocity.downstream),
        kind: _enum(FittingKind.values, j['kind'], FittingKind.none),
        count: count,
      );
    case 'table':
      return TableFitting(
        name: j['name'] is String ? j['name'] as String : 'Fitting',
        code: _s(j['code']),
        source: _s(j['source']),
        table: CoefficientTable.fromJson(j['points']),
        input: _enum(TableInput.values, j['input'], TableInput.value),
        x: _d(j['x'], 0),
        reference: _enum(ReferenceVelocity.values, j['reference'], ReferenceVelocity.downstream),
        kind: _enum(FittingKind.values, j['kind'], FittingKind.none),
        count: count,
      );
  }
  return null;
}

Map<String, dynamic> nodeToJson(DuctNode n) => {
      'id': n.id,
      'name': n.name,
      'kind': n.kind.name,
      'flow': n.flow,
      'lengthM': n.lengthM,
      'fittingC': n.fittingC,
      'fitting': n.fitting.name,
      'material': n.material.name,
      if (n.shape != null) 'shape': n.shape!.name,
      if (n.fixedHeightM != null) 'fixedHeightM': n.fixedHeightM,
      if (n.sizeOverride != null) 'sizeOverride': sizeToJson(n.sizeOverride!),
      'flexSlack': n.flexSlack,
      'equipmentDropPa': n.equipmentDropPa,
      'insulated': n.insulated,
      'fittings': [for (final f in n.fittings) fittingToJson(f)],
      if (n.junction != null) 'junction': n.junction!.name,
      'children': [for (final c in n.children) nodeToJson(c)],
    };

DuctNode nodeFromJson(Map<String, dynamic> j, {int depth = 0}) {
  if (depth > maxNodeDepth) throw const FormatException('Network is nested too deeply');
  final id = j['id'];
  if (id is! String || id.isEmpty) throw const FormatException('Node without an id');
  final shapeName = j['shape'];
  final junctionName = j['junction'];
  return DuctNode(
    id: id,
    name: j['name'] is String ? j['name'] as String : id,
    kind: _enum(NodeKind.values, j['kind'], NodeKind.branch),
    flow: _d(j['flow'], 0),
    lengthM: _d(j['lengthM'], 0),
    fittingC: _d(j['fittingC'], 0),
    fitting: _enum(FittingKind.values, j['fitting'], FittingKind.none),
    material: _enum(DuctMaterial.values, j['material'], DuctMaterial.galvanized),
    shape: shapeName == null ? null : _enum(DuctShape.values, shapeName, DuctShape.round),
    fixedHeightM: _dn(j['fixedHeightM']),
    sizeOverride: sizeFromJson(j['sizeOverride']),
    flexSlack: _d(j['flexSlack'], 0),
    equipmentDropPa: _d(j['equipmentDropPa'], 0),
    insulated: _b(j['insulated'], true),
    fittings: ((j['fittings'] as List?) ?? const []).map(fittingFromJson).whereType<Fitting>().toList(),
    junction: junctionName == null ? null : _enum(JunctionType.values, junctionName, JunctionType.tee90),
    children: [
      for (final c in ((j['children'] as List?) ?? const []).whereType<Map>())
        nodeFromJson(Map<String, dynamic>.from(c), depth: depth + 1),
    ],
  );
}

Map<String, dynamic> settingsToJson(EngineSettings s) => {
      'method': s.method.name,
      'frictionPaPerM': s.frictionPaPerM,
      'constantVelocity': s.constantVelocity,
      'velocitySteps': s.velocitySteps,
      'defaultShape': s.defaultShape.name,
      'useStandardSizes': s.useStandardSizes,
      'catalog': identical(s.catalog, SizeCatalog.imperial) ? 'imperial' : 'metric',
      if (s.maxRectHeightM != null) 'maxRectHeightM': s.maxRectHeightM,
      'autoReducers': s.autoReducers,
      'requireSourcedFittings': s.requireSourcedFittings,
      'defaultJunction': s.defaultJunction.name,
      'air': {'density': s.air.density, 'dynamicViscosity': s.air.dynamicViscosity},
      'maxVelocity': s.maxVelocity,
      'ncLimit': s.ncLimit,
      'maxAspect': s.maxAspect,
      'regainFactor': s.regainFactor,
      'ncAttenuationDb': s.ncAttenuationDb,
    };

EngineSettings settingsFromJson(Map<String, dynamic> j) {
  const d = EngineSettings();
  final air = j['air'] is Map ? Map<String, dynamic>.from(j['air'] as Map) : const <String, dynamic>{};
  final steps = j['velocitySteps'];
  return EngineSettings(
    method: _enum(SizingMethod.values, j['method'], d.method),
    frictionPaPerM: _d(j['frictionPaPerM'], d.frictionPaPerM),
    constantVelocity: _d(j['constantVelocity'], d.constantVelocity),
    velocitySteps: steps is List && steps.isNotEmpty
        ? [for (final v in steps) _d(v, 6)]
        : d.velocitySteps,
    defaultShape: _enum(DuctShape.values, j['defaultShape'], d.defaultShape),
    useStandardSizes: _b(j['useStandardSizes'], d.useStandardSizes),
    catalog: j['catalog'] == 'imperial' ? SizeCatalog.imperial : SizeCatalog.metric,
    maxRectHeightM: _dn(j['maxRectHeightM']),
    autoReducers: _b(j['autoReducers'], d.autoReducers),
    requireSourcedFittings: _b(j['requireSourcedFittings'], d.requireSourcedFittings),
    defaultJunction: _enum(JunctionType.values, j['defaultJunction'], d.defaultJunction),
    air: Air(
      density: _d(air['density'], d.air.density),
      dynamicViscosity: _d(air['dynamicViscosity'], d.air.dynamicViscosity),
    ),
    maxVelocity: _d(j['maxVelocity'], d.maxVelocity),
    ncLimit: _d(j['ncLimit'], d.ncLimit),
    maxAspect: _d(j['maxAspect'], d.maxAspect),
    regainFactor: _d(j['regainFactor'], d.regainFactor),
    ncAttenuationDb: _d(j['ncAttenuationDb'], d.ncAttenuationDb),
  );
}

String newProjectId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

/// Project details printed on reports, plus the take-off waste allowance.
class ReportInfo {
  final String company, client, location, reference, preparedBy;
  final double wastePercent;
  const ReportInfo({
    this.company = '',
    this.client = '',
    this.location = '',
    this.reference = '',
    this.preparedBy = '',
    this.wastePercent = 5,
  });

  ReportInfo copyWith({
    String? company,
    String? client,
    String? location,
    String? reference,
    String? preparedBy,
    double? wastePercent,
  }) =>
      ReportInfo(
        company: company ?? this.company,
        client: client ?? this.client,
        location: location ?? this.location,
        reference: reference ?? this.reference,
        preparedBy: preparedBy ?? this.preparedBy,
        wastePercent: wastePercent ?? this.wastePercent,
      );

  Map<String, dynamic> toJson() => {
        'company': company,
        'client': client,
        'location': location,
        'reference': reference,
        'preparedBy': preparedBy,
        'wastePercent': wastePercent,
      };

  factory ReportInfo.fromJson(Map<String, dynamic> j) {
    String s(String k) => j[k] is String ? j[k] as String : '';
    final w = _d(j['wastePercent'], 5);
    return ReportInfo(
      company: s('company'),
      client: s('client'),
      location: s('location'),
      reference: s('reference'),
      preparedBy: s('preparedBy'),
      wastePercent: w < 0 ? 0 : (w > 50 ? 50 : w),
    );
  }
}

/// Most air handling units (separate duct networks) one project may hold.
const int maxUnits = 50;

/// One saved project: one or more units (each a separate duct network with its own fan).
class ProjectDoc {
  final String id, name;
  final bool imperial;
  final EngineSettings settings;
  final List<DuctNode> units;
  final DateTime updatedAt;
  final ReportInfo info;
  final List<Fitting> library; // reusable sourced fittings (custom or table)

  /// Pass [units], or [root] for a project with a single unit.
  ProjectDoc({
    required this.id,
    required this.name,
    required this.imperial,
    required this.settings,
    DuctNode? root,
    List<DuctNode>? units,
    required this.updatedAt,
    this.info = const ReportInfo(),
    this.library = const [],
  })  : assert(root != null || (units != null && units.isNotEmpty), 'A project needs at least one unit'),
        units = List.unmodifiable(units ?? [root!]);

  /// The first unit.
  DuctNode get root => units.first;

  Map<String, dynamic> toJson() => {
        'schema': projectSchemaVersion,
        'id': id,
        'name': name,
        'imperial': imperial,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'settings': settingsToJson(settings),
        'units': [for (final u in units) nodeToJson(u)],
        'info': info.toJson(),
        'library': [for (final f in library) fittingToJson(f)],
      };

  factory ProjectDoc.fromJson(Map<String, dynamic> j) {
    final schema = _i(j['schema'], 1);
    if (schema > projectSchemaVersion) {
      throw FormatException('Project was saved by a newer app version (schema $schema)');
    }
    final id = j['id'];
    if (id is! String || id.isEmpty) throw const FormatException('Project without an id');
    final List<DuctNode> units;
    if (j['units'] is List) {
      final raw = (j['units'] as List).whereType<Map>().toList();
      if (raw.isEmpty) throw const FormatException('Project without a network');
      if (raw.length > maxUnits) throw const FormatException('The project has too many units');
      units = [for (final u in raw) nodeFromJson(Map<String, dynamic>.from(u))];
    } else if (j['root'] is Map) {
      units = [nodeFromJson(Map<String, dynamic>.from(j['root'] as Map))]; // schema 1: one unit
    } else {
      throw const FormatException('Project without a network');
    }
    return ProjectDoc(
      id: id,
      name: j['name'] is String && (j['name'] as String).isNotEmpty ? j['name'] as String : 'Untitled project',
      imperial: _b(j['imperial'], false),
      settings: j['settings'] is Map
          ? settingsFromJson(Map<String, dynamic>.from(j['settings'] as Map))
          : const EngineSettings(),
      units: units,
      library: ((j['library'] as List?) ?? const [])
          .map(fittingFromJson)
          .whereType<Fitting>()
          .where((f) => f is CustomFitting || f is TableFitting)
          .toList(),
      info: j['info'] is Map ? ReportInfo.fromJson(Map<String, dynamic>.from(j['info'] as Map)) : const ReportInfo(),
      updatedAt: DateTime.tryParse(j['updatedAt'] is String ? j['updatedAt'] as String : '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}
