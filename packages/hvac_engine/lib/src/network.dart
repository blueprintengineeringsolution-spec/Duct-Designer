import 'dart:math' as math;
import 'acoustics.dart';
import 'duct_math.dart';
import 'fittings.dart';
import 'sizing.dart';

enum SizingMethod { equalFriction, staticRegain, velocityReduction, constantVelocity }
enum NodeKind { ahu, trunk, branch, terminal }
enum NodeStatus { optimal, caution, critical }

String methodLabel(SizingMethod m) {
  switch (m) {
    case SizingMethod.equalFriction:
      return 'Constant pressure drop per length';
    case SizingMethod.staticRegain:
      return 'Static regain';
    case SizingMethod.velocityReduction:
      return 'Velocity reduction';
    case SizingMethod.constantVelocity:
      return 'Constant velocity';
  }
}

/// The junction used where [n] splits into two or more children: its own choice, else the
/// project default (a 90° tee unless changed). Always JunctionType.none when it has fewer
/// than two children, because nothing splits.
JunctionType effectiveJunction(DuctNode n, EngineSettings s) =>
    n.children.length < 2 ? JunctionType.none : (n.junction ?? s.defaultJunction);

/// Project-level calculation settings.
class EngineSettings {
  final SizingMethod method;
  final double frictionPaPerM; // equalFriction target (Pa/m)
  final double constantVelocity; // constantVelocity target (m/s)
  final List<double> velocitySteps; // velocityReduction, by tree depth
  final DuctShape defaultShape;
  final bool useStandardSizes;
  final SizeCatalog catalog;
  final double? maxRectHeightM;
  final bool autoReducers; // add a reducer where an inline section changes size
  final bool requireSourcedFittings; // warn when built-in screening coefficients are used
  final JunctionType defaultJunction; // fitting added where a node splits and sets none of its own
  final Air air;
  final double maxVelocity, ncLimit, maxAspect, regainFactor, ncAttenuationDb;
  const EngineSettings({
    this.method = SizingMethod.equalFriction,
    this.frictionPaPerM = 0.8,
    this.constantVelocity = 6.0,
    this.velocitySteps = const [9, 7.5, 6, 5, 4],
    this.defaultShape = DuctShape.round,
    this.useStandardSizes = true,
    this.catalog = SizeCatalog.metric,
    this.maxRectHeightM,
    this.autoReducers = true,
    this.requireSourcedFittings = false,
    this.defaultJunction = JunctionType.tee90,
    this.air = const Air(),
    this.maxVelocity = 10.0,
    this.ncLimit = 35,
    this.maxAspect = 4,
    this.regainFactor = 0.75,
    this.ncAttenuationDb = 15,
  });

  EngineSettings copyWith({
    SizingMethod? method,
    double? frictionPaPerM,
    double? constantVelocity,
    List<double>? velocitySteps,
    DuctShape? defaultShape,
    bool? useStandardSizes,
    SizeCatalog? catalog,
    double? maxRectHeightM,
    bool clearMaxRectHeight = false,
    bool? autoReducers,
    bool? requireSourcedFittings,
    JunctionType? defaultJunction,
    Air? air,
    double? maxVelocity,
    double? ncLimit,
    double? maxAspect,
    double? regainFactor,
    double? ncAttenuationDb,
  }) =>
      EngineSettings(
        method: method ?? this.method,
        frictionPaPerM: frictionPaPerM ?? this.frictionPaPerM,
        constantVelocity: constantVelocity ?? this.constantVelocity,
        velocitySteps: velocitySteps ?? this.velocitySteps,
        defaultShape: defaultShape ?? this.defaultShape,
        useStandardSizes: useStandardSizes ?? this.useStandardSizes,
        catalog: catalog ?? this.catalog,
        maxRectHeightM: clearMaxRectHeight ? null : (maxRectHeightM ?? this.maxRectHeightM),
        autoReducers: autoReducers ?? this.autoReducers,
        requireSourcedFittings: requireSourcedFittings ?? this.requireSourcedFittings,
        defaultJunction: defaultJunction ?? this.defaultJunction,
        air: air ?? this.air,
        maxVelocity: maxVelocity ?? this.maxVelocity,
        ncLimit: ncLimit ?? this.ncLimit,
        maxAspect: maxAspect ?? this.maxAspect,
        regainFactor: regainFactor ?? this.regainFactor,
        ncAttenuationDb: ncAttenuationDb ?? this.ncAttenuationDb,
      );
}

class DuctNode {
  final String id;
  final String name;
  final NodeKind kind;
  final double flow; // m3/s on leaves; internal nodes sum children
  final double lengthM;
  final double fittingC;
  final FittingKind fitting;
  final DuctMaterial material;
  final DuctShape? shape; // null = project default
  final double? fixedHeightM; // rectangular only
  final DuctSize? sizeOverride; // user-picked size (e.g. from recommendations)
  final double flexSlack;
  final double equipmentDropPa;
  final bool insulated; // counted in the insulation take-off
  final List<Fitting> fittings; // elbows, reducers, custom
  final JunctionType? junction; // how this node splits into its children
  final List<DuctNode> children;
  const DuctNode({
    required this.id,
    required this.name,
    this.kind = NodeKind.branch,
    this.flow = 0,
    this.lengthM = 0,
    this.fittingC = 0,
    this.fitting = FittingKind.none,
    this.material = DuctMaterial.galvanized,
    this.shape,
    this.fixedHeightM,
    this.sizeOverride,
    this.flexSlack = 0,
    this.equipmentDropPa = 0,
    this.insulated = true,
    this.fittings = const [],
    this.junction,
    this.children = const [],
  });

  double get totalFlow =>
      children.isEmpty ? flow : children.fold(0.0, (s, c) => s + c.totalFlow);

  DuctNode copyWith({
    String? id,
    String? name,
    NodeKind? kind,
    double? flow,
    double? lengthM,
    double? fittingC,
    FittingKind? fitting,
    DuctMaterial? material,
    DuctShape? shape,
    double? fixedHeightM,
    DuctSize? sizeOverride,
    double? flexSlack,
    double? equipmentDropPa,
    bool? insulated,
    List<Fitting>? fittings,
    JunctionType? junction,
    List<DuctNode>? children,
    bool clearFixedHeight = false,
    bool clearSizeOverride = false,
    bool clearJunction = false,
  }) =>
      DuctNode(
        id: id ?? this.id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        flow: flow ?? this.flow,
        lengthM: lengthM ?? this.lengthM,
        fittingC: fittingC ?? this.fittingC,
        fitting: fitting ?? this.fitting,
        material: material ?? this.material,
        shape: shape ?? this.shape,
        fixedHeightM: clearFixedHeight ? null : (fixedHeightM ?? this.fixedHeightM),
        sizeOverride: clearSizeOverride ? null : (sizeOverride ?? this.sizeOverride),
        flexSlack: flexSlack ?? this.flexSlack,
        equipmentDropPa: equipmentDropPa ?? this.equipmentDropPa,
        insulated: insulated ?? this.insulated,
        fittings: fittings ?? this.fittings,
        junction: clearJunction ? null : (junction ?? this.junction),
        children: children ?? this.children,
      );
}

class NodeResult {
  final String id;
  final double flow, velocity, frictionPaPerM;
  final DuctSize size;
  final List<SizeOption> options;
  final List<FittingLoss> fittingBreakdown;
  final double frictionLossPa, fittingLossPa, regainPa, equipmentPa;
  final double totalLossPa, cumulativePa, noiseLw, ncEstimate;
  final NodeStatus status;
  final List<String> warnings;
  const NodeResult({
    required this.id,
    required this.flow,
    required this.velocity,
    required this.frictionPaPerM,
    required this.size,
    required this.options,
    required this.fittingBreakdown,
    required this.frictionLossPa,
    required this.fittingLossPa,
    required this.regainPa,
    required this.equipmentPa,
    required this.totalLossPa,
    required this.cumulativePa,
    required this.noiseLw,
    required this.ncEstimate,
    required this.status,
    required this.warnings,
  });

  double get diameterM => size.equivalentDiameterM; // round Ø, or equivalent for rect
  double? get widthM => size.widthM;
  double? get heightM => size.heightM;
  double? get aspect => size.aspect;
}

/// Quick facts about a calculated unit, for overviews.
extension NetworkSummary on NetworkResult {
  int get sectionCount => nodes.length;
  int get warningCount => nodes.values.fold(0, (a, n) => a + n.warnings.length);

  /// The most serious status of any section (over limit beats caution beats OK).
  NodeStatus get worstStatus {
    var w = NodeStatus.optimal;
    for (final n in nodes.values) {
      if (n.status.index > w.index) w = n.status;
    }
    return w;
  }
}

String statusWord(NodeStatus s) {
  switch (s) {
    case NodeStatus.optimal:
      return 'OK';
    case NodeStatus.caution:
      return 'Caution';
    case NodeStatus.critical:
      return 'Over limit';
  }
}

class NetworkResult {
  final Map<String, NodeResult> nodes;
  final List<String> criticalPath; // root -> critical terminal
  final double requiredFanPa;
  const NetworkResult(this.nodes, this.criticalPath, this.requiredFanPa);
}

NetworkResult computeNetwork(DuctNode root, EngineSettings s) {
  final results = <String, NodeResult>{};
  final parentOf = <String, String?>{};
  String? bestLeaf;
  var bestCum = -double.infinity;

  void visit(DuctNode n, int depth, DuctNode? parent, double? parentV, double? parentArea, double parentCum) {
    parentOf[n.id] = parent?.id;
    final q = n.totalFlow;
    final rho = s.air.density;

    // 1. Required equivalent round diameter from the project method.
    double d;
    switch (s.method) {
      case SizingMethod.velocityReduction:
        d = sizeRoundForVelocity(q, s.velocitySteps[math.min(depth, s.velocitySteps.length - 1)]);
        break;
      case SizingMethod.constantVelocity:
        d = sizeRoundForVelocity(q, s.constantVelocity);
        break;
      case SizingMethod.staticRegain:
        d = parentV == null
            ? sizeRoundForFriction(flow: q, targetPaPerM: s.frictionPaPerM, material: n.material, air: s.air, flexSlack: n.flexSlack)
            : sizeRoundStaticRegain(flow: q, v1: parentV, lengthM: n.lengthM, r: s.regainFactor, material: n.material, air: s.air);
        break;
      case SizingMethod.equalFriction:
        d = sizeRoundForFriction(flow: q, targetPaPerM: s.frictionPaPerM, material: n.material, air: s.air, flexSlack: n.flexSlack);
        break;
    }

    // 2. Shape and recommended standard sizes.
    final shape = n.shape ?? s.defaultShape;
    final limits = SizeLimits(
      maxVelocity: s.maxVelocity,
      maxAspect: s.maxAspect,
      maxHeightM: n.fixedHeightM == null ? s.maxRectHeightM : null,
    );
    final options = shape == DuctShape.round
        ? recommendRound(requiredDe: d, flow: q, catalog: s.catalog, material: n.material, air: s.air, flexSlack: n.flexSlack, limits: limits)
        : recommendRect(requiredDe: d, flow: q, catalog: s.catalog, material: n.material, air: s.air, flexSlack: n.flexSlack, limits: limits, fixedHeightM: n.fixedHeightM);
    final recommended = options.firstWhere((o) => o.recommended, orElse: () => options.first).size;

    DuctSize size;
    if (n.sizeOverride != null) {
      size = n.sizeOverride!;
    } else if (s.useStandardSizes) {
      size = recommended;
    } else if (shape == DuctShape.round) {
      size = DuctSize.round(d);
    } else {
      final h = n.fixedHeightM ?? recommended.heightM!;
      size = DuctSize.rect(rectWidthFor(d, h), h);
    }

    // 3. Actual performance of the chosen size.
    final area = size.area;
    final de = size.equivalentDiameterM;
    final asp = size.aspect;
    final v = q / area;
    final fr = frictionRate(flow: q, diameter: de, material: n.material, air: s.air, flexSlack: n.flexSlack);
    final fricLoss = fr * n.lengthM;
    final ctx = FittingContext(
      upstreamArea: parentArea ?? area,
      downstreamArea: area,
      upstreamV: parentV ?? v,
      downstreamV: v,
      rectangular: size.shape == DuctShape.rectangular,
      flowRatio: parent == null || parent.totalFlow <= 0 ? 1.0 : q / parent.totalFlow,
    );
    final breakdown = <FittingLoss>[];
    if (n.fittingC > 0) {
      breakdown.add(FittingLoss(label: 'Fitting (C=${n.fittingC})', c: n.fittingC, pa: dynamicLoss(n.fittingC, v, rho)));
    }
    for (final f in n.fittings) {
      breakdown.add(f.loss(ctx, rho));
    }
    if (s.autoReducers &&
        parent != null &&
        parent.children.length == 1 &&
        !n.fittings.any((f) => f is Reducer)) {
      final r = const Reducer().loss(ctx, rho);
      if (r.pa > 0) breakdown.add(r);
    }
    var junctionKind = FittingKind.none;
    final pj = parent == null ? null : effectiveJunction(parent, s);
    if (pj != null && pj != JunctionType.none && parent != null && parentV != null) {
      final isMain =
          parent.children.reduce((a, b) => a.totalFlow >= b.totalFlow ? a : b).id == n.id;
      breakdown.add(junctionLoss(pj, isMain: isMain, velocityRatio: v / parentV, velocity: v, rho: rho));
      junctionKind = FittingKind.tee;
    }
    final fitLoss = breakdown.fold(0.0, (a, b) => a + b.pa);
    final regain = (s.method == SizingMethod.staticRegain && parentV != null)
        ? math.max(0.0, s.regainFactor * (velocityPressure(parentV, rho) - velocityPressure(v, rho)))
        : 0.0;
    final total = fricLoss + fitLoss + n.equipmentDropPa - regain;
    final cum = parentCum + total;

    var noiseKind = n.fitting;
    for (final k in [junctionKind, ...n.fittings.map((f) => f.noiseKind)]) {
      if ((fittingNoisePenaltyDb[k] ?? 0) > (fittingNoisePenaltyDb[noiseKind] ?? 0)) noiseKind = k;
    }
    final lw = flowNoiseLw(velocity: v, areaM2: area, fitting: noiseKind);
    final nc = estimateNc(lw, attenuationDb: s.ncAttenuationDb);

    final warns = <String>[];
    var status = NodeStatus.optimal;
    if (v > s.maxVelocity) {
      warns.add('Velocity ${v.toStringAsFixed(1)} m/s exceeds ${s.maxVelocity} m/s');
      status = NodeStatus.critical;
    } else if (v > 0.85 * s.maxVelocity) {
      status = NodeStatus.caution;
    }
    if (nc > s.ncLimit) {
      warns.add('Estimated NC ${nc.toStringAsFixed(0)} exceeds limit ${s.ncLimit.toStringAsFixed(0)}');
      status = NodeStatus.critical;
    }
    if (asp != null && asp > s.maxAspect + 1e-9) {
      warns.add('Aspect ratio ${asp.toStringAsFixed(1)}:1 exceeds ${s.maxAspect}:1');
      if (status == NodeStatus.optimal) status = NodeStatus.caution;
    }

    for (final b in breakdown) {
      if (b.note.isNotEmpty) {
        warns.add('${b.label}: ${b.note}');
        if (status == NodeStatus.optimal) status = NodeStatus.caution;
      }
    }
    if (s.requireSourcedFittings) {
      final names = [for (final b in breakdown) if (b.screening) b.label];
      if (names.isNotEmpty) {
        warns.add('Built-in screening coefficients used: ${names.join(', ')}');
        if (status == NodeStatus.optimal) status = NodeStatus.caution;
      }
    }

    results[n.id] = NodeResult(
      id: n.id, flow: q, velocity: v, frictionPaPerM: fr, size: size, options: options, fittingBreakdown: breakdown,
      frictionLossPa: fricLoss, fittingLossPa: fitLoss, regainPa: regain,
      equipmentPa: n.equipmentDropPa, totalLossPa: total, cumulativePa: cum,
      noiseLw: lw, ncEstimate: nc, status: status, warnings: warns,
    );

    if (n.children.isEmpty) {
      if (cum > bestCum) {
        bestCum = cum;
        bestLeaf = n.id;
      }
    } else {
      for (final c in n.children) {
        visit(c, depth + 1, n, v, area, cum);
      }
    }
  }

  visit(root, 0, null, null, null, 0);

  final path = <String>[];
  String? cur = bestLeaf;
  while (cur != null) {
    path.insert(0, cur);
    cur = parentOf[cur];
  }
  return NetworkResult(results, path, bestCum.isFinite ? bestCum : 0);
}
