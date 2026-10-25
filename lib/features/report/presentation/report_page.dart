import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hvac_engine/hvac_engine.dart';
import 'package:printing/printing.dart';
import '../../../core/utils/safe_file_name.dart';
import '../../inspector/presentation/critical_path_card.dart';
import '../../project_editor/domain/project_editor_state.dart';
import '../../project_editor/presentation/providers/project_editor_provider.dart';
import '../../schematic/presentation/status_colors.dart';
import '../../share/presentation/share_actions.dart';
import '../data/report_pdf_builder.dart';
import '../domain/report_data.dart';

class ReportPage extends ConsumerWidget {
  const ReportPage({super.key});

  Future<Uint8List> _pdf(ProjectEditorState c) => buildReportPdf(ReportData.fromEditor(c));

  String _fileName(ProjectEditorState c) => '${safeFileName(c.name)}-calculation.pdf';

  void _say(BuildContext context, String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _onMenu(BuildContext context, WidgetRef ref, String v) async {
    final c = ref.read(currentProjectProvider);
    final n = ref.read(projectEditorProvider.notifier);
    BoqSummary boq() => ReportData.fromEditor(c).boq;
    try {
      switch (v) {
        case 'share':
          await Printing.sharePdf(bytes: await _pdf(c), filename: _fileName(c));
        case 'print':
          await Printing.layoutPdf(name: _fileName(c), onLayout: (_) => _pdf(c));
        case 'csvfile':
          await shareTextFile(context, ref, boqToCsv(boq()), '${safeFileName(c.name)}-boq.csv', '${c.name} bill of quantities', mimeType: 'text/csv');
        case 'csv':
          await Clipboard.setData(ClipboardData(text: boqToCsv(boq())));
          if (context.mounted) _say(context, 'BOQ copied as CSV');
        case 'details':
          final r = await _editDetails(context, c);
          if (r != null) n.setInfo(r);
      }
    } catch (e) {
      if (context.mounted) _say(context, 'Could not create the report: $e');
    }
  }

  Future<ReportInfo?> _editDetails(BuildContext context, ProjectEditorState c) {
    final i = c.info;
    final company = TextEditingController(text: i.company);
    final client = TextEditingController(text: i.client);
    final location = TextEditingController(text: i.location);
    final reference = TextEditingController(text: i.reference);
    final by = TextEditingController(text: i.preparedBy);
    final waste = TextEditingController(text: i.wastePercent.toStringAsFixed(i.wastePercent == i.wastePercent.roundToDouble() ? 0 : 1));
    Widget field(TextEditingController t, String label, {bool number = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            controller: t,
            decoration: InputDecoration(labelText: label),
            keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          ),
        );
    return showDialog<ReportInfo>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report details'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            field(company, 'Company'),
            field(client, 'Client'),
            field(location, 'Location'),
            field(reference, 'Project reference'),
            field(by, 'Prepared by'),
            field(waste, 'Waste allowance (%)', number: true),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              ReportInfo(
                company: company.text.trim(),
                client: client.text.trim(),
                location: location.text.trim(),
                reference: reference.text.trim(),
                preparedBy: by.text.trim(),
                wastePercent: (double.tryParse(waste.text.replaceAll(',', '.')) ?? 5).clamp(0.0, 50.0),
              ),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(currentProjectProvider);
    final n = ref.read(projectEditorProvider.notifier);
    final data = ReportData.fromEditor(c);
    final b = data.boq;
    final f = c.fmt;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Report actions',
            onSelected: (v) => _onMenu(context, ref, v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'share', child: Text('Share PDF')),
              PopupMenuItem(value: 'print', child: Text('Print or preview')),
              PopupMenuItem(value: 'csvfile', child: Text('Save BOQ as CSV file')),
              PopupMenuItem(value: 'csv', child: Text('Copy BOQ as CSV')),
              PopupMenuItem(value: 'details', child: Text('Report details')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (data.units.length > 1) ...[
            Text('Units', style: t.titleSmall),
            for (final u in data.units)
              ListTile(
                key: ValueKey('overview-${u.root.id}'),
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(radius: 6, backgroundColor: statusColor(u.result.worstStatus)),
                title: Text(u.root.name),
                subtitle: Text(
                  'Fan ${f.pressure(u.result.requiredFanPa)} · ${f.length(u.boq.totalLengthM)} duct · '
                  '${u.result.warningCount == 0 ? 'no warnings' : '${u.result.warningCount} warning${u.result.warningCount == 1 ? '' : 's'}'}',
                ),
                trailing: u.root.id == c.activeUnitId ? const Text('Showing') : const Icon(Icons.chevron_right),
                onTap: () => n.setActiveUnit(u.root.id),
              ),
            const Divider(height: 24),
          ],
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final u in c.units)
              _Card(c.units.length > 1 ? '${u.name} fan' : 'Fan pressure', f.pressure(c.unitResults[u.id]!.requiredFanPa)),
            _Card('Duct length', f.length(b.totalLengthM)),
            _Card('Surface area', f.area(b.netAreaM2)),
            _Card('With waste', f.area(b.grossAreaM2)),
            _Card('Insulation', f.length(b.insulatedLengthM)),
            _Card('Insulated area', f.area(b.insulatedAreaM2)),
            _Card('Fittings', '${b.fittingCount}'),
          ]),
          const SizedBox(height: 12),
          for (final u in c.units) ...[
            CriticalPathCard(unitId: u.id, title: c.units.length > 1 ? u.name : null),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => _onMenu(context, ref, 'share'),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Export PDF'),
          ),
          const Divider(height: 32),
          Text('Duct', style: t.titleSmall),
          for (final g in b.groups)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${f.size(g.size)} · ${materialLibrary[g.material]!.label}'),
              subtitle: Text('${g.sections} section${g.sections == 1 ? '' : 's'} · ${f.length(g.lengthM)} · insulated ${f.length(g.insulatedLengthM)}'),
              trailing: Text(f.area(g.areaM2)),
            ),
          const Divider(height: 32),
          Text('Fittings', style: t.titleSmall),
          if (b.fittings.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('No fittings yet.')),
          for (final x in b.fittings)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(x.description),
              subtitle: Text(x.size),
              trailing: Text('× ${x.count}', style: t.titleMedium),
            ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String label, value;
  const _Card(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 112,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
