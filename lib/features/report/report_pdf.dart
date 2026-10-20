import 'dart:typed_data';
import 'package:hvac_engine/hvac_engine.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../core/fmt.dart';
import '../../state/project_controller.dart';

/// One unit's network, its results and its own take-off.
class ReportUnit {
  final DuctNode root;
  final NetworkResult result;
  final BoqSummary boq;
  const ReportUnit({required this.root, required this.result, required this.boq});
}

/// Everything the printed sheet needs. Built from the open project.
class ReportData {
  final String projectName;
  final ReportInfo info;
  final EngineSettings settings;
  final Fmt fmt;
  final List<ReportUnit> units;
  final BoqSummary boq; // all units added together
  final DateTime when;
  const ReportData({
    required this.projectName,
    required this.info,
    required this.settings,
    required this.fmt,
    required this.units,
    required this.boq,
    required this.when,
  });

  factory ReportData.fromController(ProjectController c, {DateTime? when}) {
    final opts = BoqOptions(wastePercent: c.info.wastePercent);
    final units = [
      for (final u in c.units)
        ReportUnit(
          root: u,
          result: c.unitResults[u.id]!,
          boq: computeBoq(u, c.unitResults[u.id]!, c.settings, options: opts),
        ),
    ];
    return ReportData(
      projectName: c.name,
      info: c.info,
      settings: c.settings,
      fmt: c.fmt,
      units: units,
      boq: mergeBoq([for (final u in units) u.boq], wastePercent: c.info.wastePercent),
      when: when ?? DateTime.now(),
    );
  }
}

String _date(DateTime t) {
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)}';
}

String _target(EngineSettings s, Fmt f) {
  switch (s.method) {
    case SizingMethod.equalFriction:
      return '${methodLabel(s.method)}, ${f.friction(s.frictionPaPerM)}';
    case SizingMethod.constantVelocity:
      return '${methodLabel(s.method)}, ${f.velocity(s.constantVelocity)}';
    default:
      return methodLabel(s.method);
  }
}

String _statusText(NodeStatus s) {
  switch (s) {
    case NodeStatus.optimal:
      return 'OK';
    case NodeStatus.caution:
      return 'Caution';
    case NodeStatus.critical:
      return 'Over limit';
  }
}

List<(DuctNode, int)> _dfs(DuctNode n, [int depth = 0]) => [
      (n, depth),
      for (final c in n.children) ..._dfs(c, depth + 1),
    ];

/// A4 landscape: summary, calculation table, bill of quantities, notes.
Future<Uint8List> buildReportPdf(ReportData d) async {
  final f = d.fmt;
  final info = d.info;

  pw.Widget heading(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
        child: pw.Text(t, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget kv(String k, String v) => pw.Container(
        width: 250,
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 78, child: pw.Text(k, style: pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700))),
          pw.Expanded(child: pw.Text(v.isEmpty ? '-' : v, style: const pw.TextStyle(fontSize: 8.5))),
        ]),
      );

  pw.Widget table(
    List<String> headers,
    List<List<String>> rows, {
    Map<int, pw.TableColumnWidth>? widths,
    bool boldLast = false,
  }) =>
      pw.TableHelper.fromTextArray(
        headers: headers,
        data: rows,
        headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 8),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
        cellAlignment: pw.Alignment.centerRight,
        headerAlignment: pw.Alignment.centerRight,
        cellAlignments: {0: pw.Alignment.centerLeft},
        headerAlignments: {0: pw.Alignment.centerLeft},
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        columnWidths: widths,
        border: const pw.TableBorder(
          bottom: pw.BorderSide(color: PdfColors.grey600, width: 0.6),
          horizontalInside: pw.BorderSide(color: PdfColors.grey400, width: 0.3),
        ),
      );

  // One block per unit. * marks the critical path.
  final multi = d.units.length > 1;
  var anyScreening = false;
  final fanLines = <pw.Widget>[];
  final unitSections = <pw.Widget>[];
  for (final u in d.units) {
    final critical = u.result.criticalPath.toSet();
    final names = {for (final (n, _) in _dfs(u.root)) n.id: n.name};
    final calcRows = <List<String>>[];
    final fitRows = <List<String>>[];
    final warnings = <String>[];
    for (final (n, depth) in _dfs(u.root)) {
      final r = u.result.nodes[n.id];
      if (r == null) continue;
      final mark = critical.contains(n.id) ? '*' : '';
      calcRows.add([
        '${'\u00A0\u00A0' * depth}${n.name}$mark',
        f.size(r.size),
        f.flow(r.flow),
        f.velocity(r.velocity),
        f.friction(r.frictionPaPerM),
        f.length(n.lengthM),
        f.pressure(r.frictionLossPa),
        f.pressure(r.fittingLossPa),
        f.pressure(r.equipmentPa),
        f.pressure(r.totalLossPa),
        f.pressure(r.cumulativePa),
        _statusText(r.status),
      ]);
      for (final w in r.warnings) {
        warnings.add('${n.name}: $w');
      }
      for (final b in r.fittingBreakdown) {
        if (b.screening) anyScreening = true;
        final src = b.screening ? 'Built-in screening value' : (b.source.isEmpty ? 'User entered' : b.source);
        fitRows.add([n.name, b.label, b.c.toStringAsFixed(2), f.pressure(b.pa), b.note.isEmpty ? src : '$src (${b.note})']);
      }
    }

    fanLines.add(pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey600, width: 0.6)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('${multi ? '${u.root.name}: r' : 'R'}equired fan static pressure: ${f.pressure(u.result.requiredFanPa)}',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 3),
        pw.Text('Critical path: ${u.result.criticalPath.map((id) => names[id] ?? id).join(' > ')}',
            style: const pw.TextStyle(fontSize: 8.5)),
      ]),
    ));

    unitSections.addAll([
      heading(multi ? '${u.root.name}: section calculations' : 'Section calculations'),
      table(
        ['Section', 'Size', 'Flow', 'Velocity', 'Friction', 'Length', 'Fric. loss', 'Fitting loss', 'Equip.', 'Section', 'Cumulative', 'Status'],
        calcRows,
        widths: {0: const pw.FlexColumnWidth(2.6), 1: const pw.FlexColumnWidth(1.5), 4: const pw.FlexColumnWidth(1.5)},
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 3),
        child: pw.Text('* on the critical path (the run that sets the fan pressure). Cumulative is measured from the first section.',
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
      ),
      if (warnings.isNotEmpty) ...[
        heading(multi ? '${u.root.name}: warnings' : 'Warnings'),
        for (final w in warnings) pw.Text('- $w', style: const pw.TextStyle(fontSize: 8.5)),
      ],
      if (fitRows.isNotEmpty) ...[
        heading(multi ? '${u.root.name}: fitting coefficients and sources' : 'Fitting coefficients and sources'),
        table(
          ['Section', 'Fitting', 'C', 'Pressure loss', 'Source'],
          fitRows,
          widths: {0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(2.4), 4: const pw.FlexColumnWidth(3)},
        ),
      ],
    ]);
  }

  final b = d.boq;
  final doc = pw.Document(
    title: '${d.projectName} - duct calculation summary',
    creator: 'Ductletor Pro',
  );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(28),
    header: (ctx) => pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey600, width: 0.6))),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(info.company.isEmpty ? 'Ductletor Pro' : info.company,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.Text('Duct calculation summary', style: const pw.TextStyle(fontSize: 10)),
      ]),
    ),
    footer: (ctx) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text('${d.projectName}  |  ${_date(d.when)}', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
      pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
    ]),
    build: (ctx) => [
      pw.SizedBox(height: 8),
      pw.Text(d.projectName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 8),
      pw.Wrap(children: [
        kv('Client', info.client),
        kv('Location', info.location),
        kv('Reference', info.reference),
        kv('Prepared by', info.preparedBy),
        kv('Date', _date(d.when)),
        kv('Units', f.imperial ? 'Imperial' : 'SI'),
        kv('Method', _target(d.settings, f)),
        kv('Sizes', d.settings.useStandardSizes ? 'Standard sizes' : 'Calculated (not rounded)'),
        kv('Air density', '${d.settings.air.density.toStringAsFixed(3)} kg/m3'),
        kv('Limits', 'max ${f.velocity(d.settings.maxVelocity)}, aspect ${d.settings.maxAspect.toStringAsFixed(1)}:1, NC ${d.settings.ncLimit.toStringAsFixed(0)}'),
      ]),
      pw.SizedBox(height: 8),
      ...fanLines,
      ...unitSections,
      if (multi) ...[
        heading('Bill of quantities by unit'),
        table(
          ['Unit', 'Fan pressure', 'Duct length', 'Surface area', 'Insulated length', 'Fittings'],
          [
            for (final u in d.units)
              [
                u.root.name,
                f.pressure(u.result.requiredFanPa),
                f.length(u.boq.totalLengthM),
                f.area(u.boq.netAreaM2),
                f.length(u.boq.insulatedLengthM),
                '${u.boq.fittingCount}',
              ],
          ],
          widths: {0: const pw.FlexColumnWidth(2)},
        ),
      ],
      heading(multi ? 'Bill of quantities: duct (all units)' : 'Bill of quantities: duct'),
      table(
        ['Material', 'Size', 'Sections', 'Length', 'Surface area', 'Insulated length', 'Insulated area'],
        [
          for (final g in b.groups)
            [
              materialLibrary[g.material]!.label,
              f.size(g.size),
              '${g.sections}',
              f.length(g.lengthM),
              f.area(g.areaM2),
              f.length(g.insulatedLengthM),
              f.area(g.insulatedAreaM2),
            ],
          [
            'Total', '', '${b.sections.length}', f.length(b.totalLengthM), f.area(b.netAreaM2),
            f.length(b.insulatedLengthM), f.area(b.insulatedAreaM2),
          ],
        ],
        widths: {0: const pw.FlexColumnWidth(2)},
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4),
        child: pw.Text(
          'With ${b.wastePercent.toStringAsFixed(b.wastePercent == b.wastePercent.roundToDouble() ? 0 : 1)}% waste: '
          'surface area ${f.area(b.grossAreaM2)}, insulated area ${f.area(b.grossInsulatedAreaM2)}.',
          style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
        ),
      ),
      heading(multi ? 'Bill of quantities: fittings (all units)' : 'Bill of quantities: fittings'),
      b.fittings.isEmpty
          ? pw.Text('No fittings.', style: const pw.TextStyle(fontSize: 8.5))
          : table(
              ['Fitting', 'Size', 'Quantity'],
              [
                for (final x in b.fittings) [x.description, x.size, '${x.count}'],
                ['Total', '', '${b.fittingCount}'],
              ],
              widths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(2)},
            ),
      heading('Notes'),
      pw.Text(
        (anyScreening
                ? 'Some fitting loss coefficients are built-in screening values, as listed above. '
                    'Replace them with values from your licensed database or manufacturer data before issue. '
                : 'Fitting loss coefficients are as entered by the designer, with the sources listed above. ') +
            'Noise (NC) figures are screening estimates. Areas are duct surface areas from the calculated sizes; '
                'fitting areas are not added.',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
      ),
    ],
  ));

  return doc.save();
}
