import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hvac_engine/hvac_engine.dart';
import '../../../core/formatting/fmt.dart';
import '../../../core/widgets/stepper_row.dart';
import '../../fittings/presentation/add_fitting_sheet.dart';
import '../../measure/presentation/measure_page.dart';
import '../../project_editor/domain/project_editor_state.dart';
import '../../project_editor/domain/tree_ops.dart';
import '../../project_editor/presentation/providers/project_editor_provider.dart';
import '../../schematic/presentation/status_colors.dart';
import 'critical_path_card.dart';
import 'nc_gauge.dart';

/// Selects section [id] and opens its editor. [ref] is only used before this returns.
void showNodeInspector(BuildContext context, WidgetRef ref, String id) {
  ref.read(projectEditorProvider.notifier).select(id);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scroll) => NodeInspectorSheet(nodeId: id, scroll: scroll),
    ),
  );
}

class NodeInspectorSheet extends ConsumerWidget {
  final String nodeId;
  final ScrollController? scroll;
  const NodeInspectorSheet({super.key, required this.nodeId, this.scroll});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(currentProjectProvider);
    final n = ref.read(projectEditorProvider.notifier);
    final node = findNode(c.root, nodeId);
    final res = c.result.nodes[nodeId];
    if (node == null || res == null) return const SizedBox.shrink();
    final fmt = c.fmt;
    final t = Theme.of(context).textTheme;
    final shape = node.shape ?? c.settings.defaultShape;
    final isLeaf = node.children.isEmpty;
    final isUnit = c.units.any((u) => u.id == nodeId);
    final h = res.size.heightM ?? 0.0;
    final w = res.size.widthM ?? 0.0;

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        Row(children: [
          CircleAvatar(radius: 6, backgroundColor: statusColor(res.status)),
          const SizedBox(width: 10),
          Expanded(
            child: _NameField(
              key: ValueKey('name-$nodeId'),
              name: node.name,
              onSave: (v) => n.updateNode(nodeId, name: v),
            ),
          ),
          Text(fmt.pressure(res.cumulativePa), style: t.titleMedium),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(spacing: 4, children: [
            TextButton.icon(
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add child'),
              onPressed: () {
                Navigator.of(context).pop();
                n.addChild(nodeId);
              },
            ),
            TextButton.icon(
              icon: const Icon(Icons.turn_right, size: 20),
              label: const Text('Add fitting'),
              onPressed: () => showAddFitting(context, nodeId),
            ),
            if (node.children.isNotEmpty)
              TextButton.icon(
                icon: Icon(c.collapsed.contains(nodeId) ? Icons.unfold_more : Icons.unfold_less, size: 20),
                label: Text(c.collapsed.contains(nodeId) ? 'Expand' : 'Collapse'),
                onPressed: () => n.toggleCollapsed(nodeId),
              ),
            if (!isUnit)
              TextButton.icon(
                icon: const Icon(Icons.copy_outlined, size: 20),
                label: const Text('Duplicate'),
                onPressed: () {
                  Navigator.of(context).pop();
                  n.duplicate(nodeId);
                },
              ),
            if (!isUnit)
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, size: 20),
                label: const Text('Delete'),
                onPressed: () {
                  final messenger = ScaffoldMessenger.of(context);
                  final name = node.name;
                  Navigator.of(context).pop();
                  n.delete(nodeId);
                  messenger
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(
                      content: Text('Deleted $name'),
                      action: SnackBarAction(label: 'Undo', onPressed: n.undo),
                    ));
                },
              ),
          ]),
        ),
        for (final warn in res.warnings)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: Theme.of(context).colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(child: Text(warn, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer))),
                ]),
              ),
            ),
          ),
        const SizedBox(height: 12),
        SegmentedButton<DuctShape>(
          segments: const [
            ButtonSegment(value: DuctShape.round, label: Text('Round')),
            ButtonSegment(value: DuctShape.rectangular, label: Text('Rectangular')),
          ],
          selected: {shape},
          onSelectionChanged: (s) => n.updateNode(nodeId, shape: s.first),
        ),
        const SizedBox(height: 8),
        if (isLeaf)
          StepperRow(
            label: 'Flow',
            value: fmt.flow(node.flow),
            onMinus: () => n.updateNode(nodeId, flow: node.flow - fmt.flowStep),
            onPlus: () => n.updateNode(nodeId, flow: node.flow + fmt.flowStep),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(children: [const Expanded(child: Text('Flow (sum of branches)')), Text(fmt.flow(res.flow))]),
          ),
        StepperRow(
          label: 'Length',
          value: fmt.length(node.lengthM),
          onMinus: () => n.updateNode(nodeId, lengthM: node.lengthM - fmt.lengthStep),
          onPlus: () => n.updateNode(nodeId, lengthM: node.lengthM + fmt.lengthStep),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.straighten),
            label: const Text('Measure length'),
            onPressed: () async {
              final m = await Navigator.of(context).push<double>(MaterialPageRoute(
                builder: (_) => MeasurePage(title: node.name, currentLengthM: node.lengthM, fmt: fmt),
              ));
              if (m != null) n.updateNode(nodeId, lengthM: m);
            },
          ),
        ),
        if (res.size.shape == DuctShape.round)
          StepperRow(
            label: 'Diameter',
            value: fmt.dim(res.size.diameterM!),
            onMinus: () => n.stepRoundSize(nodeId, -1),
            onPlus: () => n.stepRoundSize(nodeId, 1),
          )
        else ...[
          StepperRow(
            label: 'Width',
            value: fmt.dim(w),
            onMinus: () => n.chooseSize(nodeId, DuctSize.rect(w - fmt.dimStep, h)),
            onPlus: () => n.chooseSize(nodeId, DuctSize.rect(w + fmt.dimStep, h)),
          ),
          StepperRow(
            label: 'Height',
            value: fmt.dim(h),
            onMinus: () => n.updateNode(nodeId, fixedHeightM: h - fmt.dimStep),
            onPlus: () => n.updateNode(nodeId, fixedHeightM: h + fmt.dimStep),
          ),
        ],
        Row(children: [
          const Expanded(child: Text('Material')),
          DropdownButton<DuctMaterial>(
            value: node.material,
            onChanged: (m) => m == null ? null : n.updateNode(nodeId, material: m),
            items: [
              for (final m in DuctMaterial.values)
                DropdownMenuItem(value: m, child: Text(materialLibrary[m]!.label)),
            ],
          ),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Insulated'),
          value: node.insulated,
          onChanged: (v) => n.setInsulated(nodeId, v),
        ),
        if (node.children.length > 1)
          Row(children: [
            const Expanded(child: Text('Split type')),
            DropdownButton<int>(
              value: node.junction == null
                  ? 0
                  : node.junction == JunctionType.tee90
                      ? 1
                      : node.junction == JunctionType.wye45
                          ? 2
                          : 3,
              onChanged: (v) => n.setJunction(nodeId, const [null, JunctionType.tee90, JunctionType.wye45, JunctionType.none][v ?? 0]),
              items: [
                DropdownMenuItem(
                  value: 0,
                  child: Text('Automatic (${c.settings.defaultJunction == JunctionType.tee90 ? '90° tee' : c.settings.defaultJunction == JunctionType.wye45 ? '45° wye' : 'none'})'),
                ),
                const DropdownMenuItem(value: 1, child: Text('90° tee')),
                const DropdownMenuItem(value: 2, child: Text('45° wye')),
                const DropdownMenuItem(value: 3, child: Text('None')),
              ],
            ),
          ]),
        const Divider(height: 28),
        Row(children: [
          Expanded(child: Text('Recommended sizes', style: t.titleSmall)),
          if (node.sizeOverride != null)
            TextButton(onPressed: () => n.clearSize(nodeId), child: const Text('Use best fit')),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final o in res.options)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _OptionCard(
                  o: o,
                  fmt: fmt,
                  selected: o.size.label == res.size.label,
                  onTap: () => n.chooseSize(nodeId, o.size),
                ),
              ),
            ),
        ]),
        const Divider(height: 28),
        Row(children: [
          Expanded(child: Text('Fittings', style: t.titleSmall)),
          TextButton.icon(
            onPressed: () => showAddFitting(context, nodeId),
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
        ]),
        if (res.fittingBreakdown.isEmpty) const Text('No fittings on this section.'),
        for (var i = 0; i < res.fittingBreakdown.length; i++) _fittingTile(c, n, node, res, i),
        const Divider(height: 28),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _Metric('Velocity', fmt.velocity(res.velocity)),
          _Metric('Friction', fmt.friction(res.frictionPaPerM)),
          _Metric('Friction loss', fmt.pressure(res.frictionLossPa)),
          _Metric('Fitting loss', fmt.pressure(res.fittingLossPa)),
          _Metric('Section total', fmt.pressure(res.totalLossPa)),
          _Metric('Cumulative', fmt.pressure(res.cumulativePa)),
          _Metric('Est. NC', res.ncEstimate.toStringAsFixed(0)),
        ]),
        const Divider(height: 28),
        Text('Acoustics (screening estimate)', style: t.titleSmall),
        const SizedBox(height: 8),
        Center(child: NcGauge(nc: res.ncEstimate, limit: c.settings.ncLimit)),
        const SizedBox(height: 16),
        CriticalPathCard(highlightId: nodeId),
      ],
    );
  }

  Widget _fittingTile(ProjectEditorState c, ProjectEditorNotifier n, DuctNode node, NodeResult res, int i) {
    final f = res.fittingBreakdown[i];
    final offset = node.fittingC > 0 ? 1 : 0;
    final explicit = i >= offset && i < offset + node.fittings.length;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(f.label),
      subtitle: Text(
        'C ${f.c.toStringAsFixed(2)} · ${f.screening ? 'built-in screening value' : (f.source.isEmpty ? 'user entered' : f.source)}'
        '${f.note.isEmpty ? '' : '\n${f.note}'}',
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(c.fmt.pressure(f.pa)),
        if (explicit)
          IconButton(
            tooltip: 'Remove ${f.label}',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => n.removeFitting(nodeId, i - offset),
          ),
      ]),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final SizeOption o;
  final Fmt fmt;
  final bool selected;
  final VoidCallback onTap;
  const _OptionCard({required this.o, required this.fmt, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final String? tag = o.recommended
        ? 'Best fit'
        : o.undersized
            ? 'Undersized'
            : o.overAspect
                ? 'Aspect'
                : o.overVelocity
                    ? 'Velocity'
                    : null;
    final tagColor = o.recommended ? const Color(0xFF2E9E5B) : scheme.error;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 16,
            child: tag == null ? null : Text(tag, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tagColor)),
          ),
          Text(fmt.size(o.size), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(fmt.velocity(o.velocity), style: Theme.of(context).textTheme.bodySmall),
          Text(fmt.friction(o.frictionPaPerM), style: Theme.of(context).textTheme.bodySmall),
          if (o.size.aspect != null)
            Text('${o.size.aspect!.toStringAsFixed(1)} : 1', style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label, value;
  const _Metric(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 108,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// The section name: edit it in place. Saved when you press done, leave the field or close
/// the sheet; an empty name is ignored.
class _NameField extends StatefulWidget {
  final String name;
  final ValueChanged<String> onSave;
  const _NameField({super.key, required this.name, required this.onSave});
  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final TextEditingController _ctl = TextEditingController(text: widget.name);
  final FocusNode _focus = FocusNode();
  late String _last = widget.name; // the last name saved, so closing the sheet doesn't save twice

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_NameField old) {
    super.didUpdateWidget(old);
    if (old.name != widget.name && !_focus.hasFocus) {
      _ctl.text = widget.name;
      _last = widget.name;
    }
  }

  void _commit() {
    final v = _ctl.text.trim();
    if (v.isEmpty) {
      _ctl.text = widget.name;
    } else if (v != _last) {
      _last = v;
      widget.onSave(v);
    }
  }

  @override
  void dispose() {
    // Closing the sheet with the keyboard still open: save after this frame, not during it.
    final v = _ctl.text.trim();
    if (v.isNotEmpty && v != _last) {
      final save = widget.onSave;
      WidgetsBinding.instance.addPostFrameCallback((_) => save(v));
    }
    _focus.dispose();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctl,
      focusNode: _focus,
      style: Theme.of(context).textTheme.titleLarge,
      textInputAction: TextInputAction.done,
      inputFormatters: [LengthLimitingTextInputFormatter(60)],
      decoration: const InputDecoration(
        hintText: 'Name',
        isDense: true,
        suffixIcon: Icon(Icons.edit_outlined, size: 18),
        suffixIconConstraints: BoxConstraints(minWidth: 28, minHeight: 28),
      ),
      onSubmitted: (_) => _commit(),
    );
  }
}
