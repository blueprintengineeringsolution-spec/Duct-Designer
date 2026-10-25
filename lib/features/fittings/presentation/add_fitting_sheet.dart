import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hvac_engine/hvac_engine.dart';
import '../../../core/widgets/stepper_row.dart';
import '../../project_editor/domain/project_editor_state.dart';
import '../../project_editor/domain/tree_ops.dart';
import '../../project_editor/presentation/providers/project_editor_provider.dart';

void showAddFitting(BuildContext context, String nodeId) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: AddFittingSheet(nodeId: nodeId),
    ),
  );
}

enum _Kind { elbow, reducer, branch, custom, table, library }

class AddFittingSheet extends ConsumerStatefulWidget {
  final String nodeId;
  const AddFittingSheet({super.key, required this.nodeId});
  @override
  ConsumerState<AddFittingSheet> createState() => _AddFittingSheetState();
}

class _AddFittingSheetState extends ConsumerState<AddFittingSheet> {
  _Kind kind = _Kind.elbow;
  double angle = 90, radius = 1.0, reducerAngle = 30;
  ElbowStyle style = ElbowStyle.smoothRadius;
  int qty = 1;
  JunctionType junction = JunctionType.tee90;
  ReferenceVelocity refVelocity = ReferenceVelocity.downstream;
  TableInput tableInput = TableInput.flowRatio;
  int? libIndex;
  bool saveToLib = false;
  final nameCtl = TextEditingController(text: 'Fitting');
  final codeCtl = TextEditingController();
  final sourceCtl = TextEditingController();
  final cCtl = TextEditingController(text: '0.5');
  final xCtl = TextEditingController(text: '0');
  final tableCtl = TextEditingController();

  @override
  void dispose() {
    for (final t in [nameCtl, codeCtl, sourceCtl, cCtl, xCtl, tableCtl]) {
      t.dispose();
    }
    super.dispose();
  }

  String _name() =>
      nameCtl.text.trim().isEmpty ? 'Fitting' : nameCtl.text.trim();

  /// Null while the inputs are incomplete or invalid. [tableError] explains a bad table.
  String? tableError;

  Fitting? _fitting(ProjectEditorState c) {
    tableError = null;
    switch (kind) {
      case _Kind.elbow:
        return Elbow(
            angleDeg: angle, radiusRatio: radius, style: style, count: qty);
      case _Kind.reducer:
        return Reducer(angleDeg: reducerAngle, count: qty);
      case _Kind.custom:
        final cv = double.tryParse(cCtl.text.replaceAll(',', '.'));
        if (cv == null || cv < 0 || cv > 100) return null;
        return CustomFitting(
          name: _name(),
          code: codeCtl.text.trim(),
          source: sourceCtl.text.trim(),
          c: cv,
          reference: refVelocity,
          count: qty,
        );
      case _Kind.table:
        if (tableCtl.text.trim().isEmpty) return null;
        try {
          final table = parseCoefficientCsv(tableCtl.text);
          final x = double.tryParse(xCtl.text.replaceAll(',', '.')) ?? 0;
          return TableFitting(
            name: _name(),
            code: codeCtl.text.trim(),
            source: sourceCtl.text.trim(),
            table: table,
            input: tableInput,
            x: x,
            reference: refVelocity,
            count: qty,
          );
        } on FormatException catch (e) {
          tableError = e.message;
          return null;
        }
      case _Kind.library:
        final i = libIndex;
        if (i == null || i < 0 || i >= c.library.length) return null;
        return c.library[i].withCount(qty);
      case _Kind.branch:
        return null;
    }
  }

  FittingLoss? _preview(ProjectEditorState c, Fitting? f) {
    final res = c.result.nodes[widget.nodeId];
    if (f == null || res == null) return null;
    final pid = parentIdOf(c.root, widget.nodeId);
    final pres = pid == null ? null : c.result.nodes[pid];
    return f.loss(
      FittingContext(
        upstreamArea: pres?.size.area ?? res.size.area,
        downstreamArea: res.size.area,
        upstreamV: pres?.velocity ?? res.velocity,
        downstreamV: res.velocity,
        rectangular: res.size.shape == DuctShape.rectangular,
        flowRatio: pres == null || pres.flow <= 0 ? 1.0 : res.flow / pres.flow,
      ),
      c.settings.air.density,
    );
  }

  Widget _sourceFields() => Column(children: [
        TextField(
            controller: nameCtl,
            decoration: const InputDecoration(labelText: 'Name'),
            onChanged: (_) => setState(() {})),
        Row(children: [
          Expanded(
            child: TextField(
              controller: codeCtl,
              decoration: const InputDecoration(
                  labelText: 'Code (optional)', hintText: 'e.g. CR3-1'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: TextField(
              controller: sourceCtl,
              decoration: const InputDecoration(
                  labelText: 'Source', hintText: 'Database, maker, report'),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ]),
      ]);

  Widget _refChoice() => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SegmentedButton<ReferenceVelocity>(
          segments: const [
            ButtonSegment(
                value: ReferenceVelocity.upstream, label: Text('Upstream V')),
            ButtonSegment(
                value: ReferenceVelocity.downstream,
                label: Text('Downstream V')),
          ],
          selected: {refVelocity},
          onSelectionChanged: (s) => setState(() => refVelocity = s.first),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(currentProjectProvider);
    final n = ref.read(projectEditorProvider.notifier);
    final node = findNode(c.root, widget.nodeId);
    if (node == null) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final f = _fitting(c);
    final p = _preview(c, f);

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text('Add fitting', style: t.titleLarge),
        Text(node.name, style: t.bodySmall),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<_Kind>(
            segments: const [
              ButtonSegment(value: _Kind.elbow, label: Text('Elbow')),
              ButtonSegment(value: _Kind.reducer, label: Text('Reducer')),
              ButtonSegment(value: _Kind.branch, label: Text('Branch')),
              ButtonSegment(value: _Kind.custom, label: Text('Sourced C')),
              ButtonSegment(value: _Kind.table, label: Text('Table')),
              ButtonSegment(value: _Kind.library, label: Text('Library')),
            ],
            selected: {kind},
            onSelectionChanged: (s) => setState(() => kind = s.first),
          ),
        ),
        const SizedBox(height: 12),
        if (kind == _Kind.elbow) ...[
          Wrap(spacing: 8, children: [
            for (final a in [30.0, 45.0, 60.0, 90.0])
              ChoiceChip(
                  label: Text('${a.round()}°'),
                  selected: angle == a,
                  onSelected: (_) => setState(() => angle = a)),
          ]),
          const SizedBox(height: 8),
          SegmentedButton<ElbowStyle>(
            segments: const [
              ButtonSegment(
                  value: ElbowStyle.smoothRadius, label: Text('Radius')),
              ButtonSegment(value: ElbowStyle.mitered, label: Text('Mitered')),
              ButtonSegment(
                  value: ElbowStyle.miteredVanes, label: Text('Vanes')),
            ],
            selected: {style},
            onSelectionChanged: (s) => setState(() => style = s.first),
          ),
          if (style == ElbowStyle.smoothRadius)
            StepperRow(
              label: 'Radius ratio',
              value: radius.toStringAsFixed(2),
              onMinus: () =>
                  setState(() => radius = (radius - 0.25).clamp(0.5, 2.0)),
              onPlus: () =>
                  setState(() => radius = (radius + 0.25).clamp(0.5, 2.0)),
            ),
        ],
        if (kind == _Kind.reducer) ...[
          const Text(
              'Contraction or expansion is picked from the size change against the parent section.'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final a in [15.0, 30.0, 45.0, 60.0, 90.0])
              ChoiceChip(
                  label: Text('${a.round()}°'),
                  selected: reducerAngle == a,
                  onSelected: (_) => setState(() => reducerAngle = a)),
          ]),
        ],
        if (kind == _Kind.branch) ...[
          const Text(
              'A tee is added automatically wherever a section splits into two or more children. Use this to choose a wye for this split instead (built-in screening values). The largest flow takes the main loss, the others take the branch loss. For sourced values, add a Table or Sourced C fitting on the branch section.'),
          const SizedBox(height: 8),
          SegmentedButton<JunctionType>(
            segments: const [
              ButtonSegment(value: JunctionType.tee90, label: Text('90° tee')),
              ButtonSegment(value: JunctionType.wye45, label: Text('45° wye')),
            ],
            selected: {junction},
            onSelectionChanged: (s) => setState(() => junction = s.first),
          ),
          if (node.children.length < 2)
            const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                    'Takes effect once this node has two or more children.')),
        ],
        if (kind == _Kind.custom) ...[
          const Text(
              'Enter the loss coefficient from a source you are licensed to use, such as your fitting database subscription or manufacturer data.'),
          const SizedBox(height: 8),
          _sourceFields(),
          TextField(
            controller: cCtl,
            decoration: const InputDecoration(labelText: 'Loss coefficient C'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          _refChoice(),
        ],
        if (kind == _Kind.table) ...[
          const Text(
              'Paste a table of input and coefficient pairs from your own source. The app interpolates between the rows.'),
          const SizedBox(height: 8),
          _sourceFields(),
          const SizedBox(height: 8),
          DropdownButtonFormField<TableInput>(
            initialValue: tableInput,
            decoration: const InputDecoration(labelText: 'Table input'),
            onChanged: (v) => setState(() => tableInput = v ?? tableInput),
            items: const [
              DropdownMenuItem(
                  value: TableInput.flowRatio,
                  child: Text('Flow ratio (this section / parent)')),
              DropdownMenuItem(
                  value: TableInput.areaRatio,
                  child: Text('Area ratio (this / parent)')),
              DropdownMenuItem(
                  value: TableInput.velocityRatio,
                  child: Text('Velocity ratio (this / parent)')),
              DropdownMenuItem(
                  value: TableInput.value, child: Text('A value I enter')),
            ],
          ),
          if (tableInput == TableInput.value)
            TextField(
              controller: xCtl,
              decoration: const InputDecoration(labelText: 'Input value'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: tableCtl,
            maxLines: 6,
            minLines: 4,
            decoration: InputDecoration(
              labelText: 'Rows: input, coefficient',
              hintText: '0.2, 0.9\n0.5, 0.7\n0.8, 0.6',
              errorText: tableError,
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          _refChoice(),
        ],
        if (kind == _Kind.library) ...[
          if (c.library.isEmpty)
            const Text(
                'Nothing saved yet. Tick "Save to project library" when adding a Sourced C or Table fitting.'),
          for (var i = 0; i < c.library.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              selected: libIndex == i,
              leading: Icon(libIndex == i
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off),
              title: Text(c.library[i].label),
              subtitle: Text(
                  '${c.library[i] is CustomFitting ? 'C ${(c.library[i] as CustomFitting).c.toStringAsFixed(2)}' : 'Table'} · ${c.library[i].dataSource}'),
              onTap: () => setState(() => libIndex = i),
              trailing: IconButton(
                tooltip: 'Remove ${c.library[i].label} from the library',
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  n.removeFromLibrary(i);
                  setState(() => libIndex = null);
                },
              ),
            ),
        ],
        if (kind == _Kind.custom || kind == _Kind.table)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Save to project library'),
            value: saveToLib,
            onChanged: (v) => setState(() => saveToLib = v ?? false),
          ),
        if (kind != _Kind.branch)
          StepperRow(
            label: 'Quantity',
            value: '$qty',
            onMinus: qty > 1 ? () => setState(() => qty--) : null,
            onPlus: () => setState(() => qty++),
          ),
        if (p != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('C ${p.c.toStringAsFixed(2)}',
                                style: t.titleMedium),
                            Text(c.fmt.pressure(p.pa), style: t.titleMedium),
                          ]),
                      if (p.note.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(p.note)),
                    ]),
              ),
            ),
          ),
        if (kind == _Kind.elbow || kind == _Kind.reducer)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
                'Built-in screening value, not database data. Use Sourced C or Table for design values.'),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: kind == _Kind.branch
              ? () {
                  n.setJunction(widget.nodeId, junction);
                  Navigator.pop(context);
                }
              : f == null
                  ? null
                  : () {
                      if (saveToLib &&
                          (kind == _Kind.custom || kind == _Kind.table))
                        n.saveToLibrary(f);
                      n.addFitting(widget.nodeId, f);
                      Navigator.pop(context);
                    },
          child: Text(kind == _Kind.branch ? 'Set split type' : 'Add fitting'),
        ),
      ],
    );
  }
}
