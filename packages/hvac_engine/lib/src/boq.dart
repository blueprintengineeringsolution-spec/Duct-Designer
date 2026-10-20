import 'dart:math' as math;
import 'duct_math.dart';
import 'fittings.dart';
import 'network.dart';
import 'sizing.dart';

class BoqOptions {
  final double wastePercent; // added to areas for ordering
  const BoqOptions({this.wastePercent = 5});
}

/// Duct surface area per metre of length (m2/m).
double surfaceAreaPerMeter(DuctSize s) => s.shape == DuctShape.round
    ? math.pi * s.diameterM!
    : 2 * (s.widthM! + s.heightM!);

class DuctLine {
  final String nodeId, name;
  final DuctMaterial material;
  final DuctSize size;
  final double lengthM, areaM2;
  final bool insulated;
  const DuctLine({
    required this.nodeId,
    required this.name,
    required this.material,
    required this.size,
    required this.lengthM,
    required this.areaM2,
    required this.insulated,
  });
}

/// Sections of the same material and size, added up.
class DuctGroup {
  final DuctMaterial material;
  final DuctSize size;
  final int sections;
  final double lengthM, areaM2, insulatedLengthM, insulatedAreaM2;
  const DuctGroup({
    required this.material,
    required this.size,
    required this.sections,
    required this.lengthM,
    required this.areaM2,
    required this.insulatedLengthM,
    required this.insulatedAreaM2,
  });
}

class FittingLine {
  final String description, size;
  final int count;
  const FittingLine(this.description, this.size, this.count);
}

class BoqSummary {
  final List<DuctLine> sections;
  final List<DuctGroup> groups;
  final List<FittingLine> fittings;
  final double wastePercent;
  const BoqSummary({
    required this.sections,
    required this.groups,
    required this.fittings,
    required this.wastePercent,
  });

  double get totalLengthM => sections.fold(0.0, (a, s) => a + s.lengthM);
  double get netAreaM2 => sections.fold(0.0, (a, s) => a + s.areaM2);
  double get insulatedLengthM => sections.where((s) => s.insulated).fold(0.0, (a, s) => a + s.lengthM);
  double get insulatedAreaM2 => sections.where((s) => s.insulated).fold(0.0, (a, s) => a + s.areaM2);
  double get grossAreaM2 => netAreaM2 * (1 + wastePercent / 100);
  double get grossInsulatedAreaM2 => insulatedAreaM2 * (1 + wastePercent / 100);
  int get fittingCount => fittings.fold(0, (a, f) => a + f.count);
}

class _Acc {
  final DuctMaterial material;
  final DuctSize size;
  int sections = 0;
  double length = 0, area = 0, insLength = 0, insArea = 0;
  _Acc(this.material, this.size);
}

String _elbowText(Elbow e, bool rect) {
  final a = '${e.angleDeg.round()}° elbow';
  switch (e.style) {
    case ElbowStyle.smoothRadius:
      return '$a, r/${rect ? 'W' : 'D'} ${e.radiusRatio.toStringAsFixed(2)}';
    case ElbowStyle.mitered:
      return '$a, mitered';
    case ElbowStyle.miteredVanes:
      return '$a, mitered with vanes';
  }
}

/// Material take-off from a calculated network: duct area and length by material and
/// size, insulation length and area, and fitting counts.
BoqSummary computeBoq(
  DuctNode root,
  NetworkResult result,
  EngineSettings settings, {
  BoqOptions options = const BoqOptions(),
}) {
  final sections = <DuctLine>[];
  final accs = <String, _Acc>{};
  final fits = <String, FittingLine>{};

  void addFit(String description, String size, int n) {
    if (n <= 0) return;
    final k = '$description|$size';
    fits[k] = FittingLine(description, size, (fits[k]?.count ?? 0) + n);
  }

  void visit(DuctNode n, DuctNode? parent) {
    final r = result.nodes[n.id];
    if (r != null) {
      final area = surfaceAreaPerMeter(r.size) * n.lengthM;
      sections.add(DuctLine(
        nodeId: n.id, name: n.name, material: n.material, size: r.size,
        lengthM: n.lengthM, areaM2: area, insulated: n.insulated,
      ));
      final acc = accs.putIfAbsent('${n.material.name}|${r.size.label}', () => _Acc(n.material, r.size));
      acc.sections++;
      acc.length += n.lengthM;
      acc.area += area;
      if (n.insulated) {
        acc.insLength += n.lengthM;
        acc.insArea += area;
      }

      final here = r.size.label;
      final rect = r.size.shape == DuctShape.rectangular;
      final pr = parent == null ? null : result.nodes[parent.id];
      final reducerSize = pr == null ? here : '${pr.size.label} to $here';

      if (n.fittingC > 0) addFit('Fitting (C=${n.fittingC})', here, 1);
      for (final f in n.fittings) {
        if (f is Elbow) {
          addFit(_elbowText(f, rect), here, f.count);
        } else if (f is Reducer) {
          addFit('Reducer', reducerSize, f.count);
        } else {
          addFit(f.label, here, f.count);
        }
      }
      if (settings.autoReducers &&
          parent != null &&
          parent.children.length == 1 &&
          !n.fittings.any((f) => f is Reducer) &&
          r.fittingBreakdown.any((b) => b.label == 'Reducer')) {
        addFit('Reducer', reducerSize, 1);
      }
      final jt = effectiveJunction(n, settings);
      if (jt != JunctionType.none) {
        addFit(jt == JunctionType.tee90 ? '90° tee' : '45° wye', here, n.children.length - 1);
      }
    }
    for (final c in n.children) {
      visit(c, n);
    }
  }

  visit(root, null);

  final groups = accs.values.toList()
    ..sort((a, b) {
      final m = a.material.index.compareTo(b.material.index);
      return m != 0 ? m : a.size.area.compareTo(b.size.area);
    });
  final fitList = fits.values.toList()
    ..sort((a, b) {
      final d = a.description.compareTo(b.description);
      return d != 0 ? d : a.size.compareTo(b.size);
    });

  return BoqSummary(
    sections: sections,
    groups: [
      for (final g in groups)
        DuctGroup(
          material: g.material, size: g.size, sections: g.sections,
          lengthM: g.length, areaM2: g.area,
          insulatedLengthM: g.insLength, insulatedAreaM2: g.insArea,
        ),
    ],
    fittings: fitList,
    wastePercent: options.wastePercent,
  );
}

/// Adds several take-offs together (one per unit): sections are listed one after another,
/// and groups and fittings of the same kind and size are summed.
BoqSummary mergeBoq(List<BoqSummary> parts, {double? wastePercent}) {
  final accs = <String, _Acc>{};
  final fits = <String, FittingLine>{};
  for (final p in parts) {
    for (final g in p.groups) {
      final a = accs.putIfAbsent('${g.material.name}|${g.size.label}', () => _Acc(g.material, g.size));
      a.sections += g.sections;
      a.length += g.lengthM;
      a.area += g.areaM2;
      a.insLength += g.insulatedLengthM;
      a.insArea += g.insulatedAreaM2;
    }
    for (final f in p.fittings) {
      final k = '${f.description}|${f.size}';
      fits[k] = FittingLine(f.description, f.size, (fits[k]?.count ?? 0) + f.count);
    }
  }
  final groups = accs.values.toList()
    ..sort((a, b) {
      final m = a.material.index.compareTo(b.material.index);
      return m != 0 ? m : a.size.area.compareTo(b.size.area);
    });
  final fitList = fits.values.toList()
    ..sort((a, b) {
      final d = a.description.compareTo(b.description);
      return d != 0 ? d : a.size.compareTo(b.size);
    });
  return BoqSummary(
    sections: [for (final p in parts) ...p.sections],
    groups: [
      for (final g in groups)
        DuctGroup(
          material: g.material, size: g.size, sections: g.sections,
          lengthM: g.length, areaM2: g.area,
          insulatedLengthM: g.insLength, insulatedAreaM2: g.insArea,
        ),
    ],
    fittings: fitList,
    wastePercent: wastePercent ?? (parts.isEmpty ? 5 : parts.first.wastePercent),
  );
}

String _csv(Object? v) {
  final s = '$v';
  return s.contains(',') || s.contains('"') || s.contains('\n') ? '"${s.replaceAll('"', '""')}"' : s;
}

/// SI units, one table per block, blank line between blocks.
String boqToCsv(BoqSummary b) {
  final out = StringBuffer();
  void row(List<Object?> cells) => out.writeln(cells.map(_csv).join(','));

  row(['Duct sections']);
  row(['Section', 'Material', 'Size', 'Length (m)', 'Surface area (m2)', 'Insulated']);
  for (final s in b.sections) {
    row([s.name, materialLibrary[s.material]!.label, s.size.label, s.lengthM.toStringAsFixed(2), s.areaM2.toStringAsFixed(2), s.insulated ? 'yes' : 'no']);
  }
  out.writeln();
  row(['Duct by material and size']);
  row(['Material', 'Size', 'Sections', 'Length (m)', 'Surface area (m2)', 'Insulated length (m)', 'Insulated area (m2)']);
  for (final g in b.groups) {
    row([materialLibrary[g.material]!.label, g.size.label, g.sections, g.lengthM.toStringAsFixed(2), g.areaM2.toStringAsFixed(2), g.insulatedLengthM.toStringAsFixed(2), g.insulatedAreaM2.toStringAsFixed(2)]);
  }
  out.writeln();
  row(['Fittings']);
  row(['Fitting', 'Size', 'Quantity']);
  for (final f in b.fittings) {
    row([f.description, f.size, f.count]);
  }
  out.writeln();
  row(['Totals']);
  row(['Total length (m)', b.totalLengthM.toStringAsFixed(2)]);
  row(['Surface area, net (m2)', b.netAreaM2.toStringAsFixed(2)]);
  row(['Waste allowance (%)', b.wastePercent.toStringAsFixed(1)]);
  row(['Surface area, with waste (m2)', b.grossAreaM2.toStringAsFixed(2)]);
  row(['Insulated length (m)', b.insulatedLengthM.toStringAsFixed(2)]);
  row(['Insulated area, net (m2)', b.insulatedAreaM2.toStringAsFixed(2)]);
  row(['Insulated area, with waste (m2)', b.grossInsulatedAreaM2.toStringAsFixed(2)]);
  row(['Fittings (count)', b.fittingCount]);
  return out.toString();
}
