import 'package:flutter/material.dart';
import 'package:hvac_engine/hvac_engine.dart';
import '../../state/project_controller.dart';
import '../share/share_actions.dart';
import '../../widgets/stepper_row.dart';

class ProjectSettingsPage extends StatelessWidget {
  final ProjectController c;
  const ProjectSettingsPage({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final s = c.settings;
        final fmt = c.fmt;
        final t = Theme.of(context).textTheme;
        void set(EngineSettings n) => c.setSettings(n);

        const descriptions = {
          SizingMethod.equalFriction: 'Same Pa/m on every section',
          SizingMethod.staticRegain: 'Velocity falls along the run, pressure regained',
          SizingMethod.velocityReduction: 'Stepped velocity by tree depth',
          SizingMethod.constantVelocity: 'One velocity for the whole system',
        };

        return Scaffold(
          appBar: AppBar(title: const Text('Project settings')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text('Calculation method', style: t.titleSmall),
              for (final m in SizingMethod.values)
                // ignore: deprecated_member_use
                RadioListTile<SizingMethod>(
                  value: m,
                  groupValue: s.method,
                  onChanged: (v) => v == null ? null : set(s.copyWith(method: v)),
                  title: Text(methodLabel(m)),
                  subtitle: Text(descriptions[m]!),
                  contentPadding: EdgeInsets.zero,
                ),
              if (s.method == SizingMethod.equalFriction)
                StepperRow(
                  label: 'Pressure drop',
                  value: fmt.friction(s.frictionPaPerM),
                  onMinus: () => set(s.copyWith(frictionPaPerM: (s.frictionPaPerM - fmt.frictionStep).clamp(0.05, 5.0))),
                  onPlus: () => set(s.copyWith(frictionPaPerM: (s.frictionPaPerM + fmt.frictionStep).clamp(0.05, 5.0))),
                ),
              if (s.method == SizingMethod.constantVelocity)
                StepperRow(
                  label: 'Velocity',
                  value: fmt.velocity(s.constantVelocity),
                  onMinus: () => set(s.copyWith(constantVelocity: (s.constantVelocity - fmt.velocityStep).clamp(1.0, 20.0))),
                  onPlus: () => set(s.copyWith(constantVelocity: (s.constantVelocity + fmt.velocityStep).clamp(1.0, 20.0))),
                ),
              const Divider(height: 28),
              Text('Duct shape', style: t.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<DuctShape>(
                segments: const [
                  ButtonSegment(value: DuctShape.round, label: Text('Round')),
                  ButtonSegment(value: DuctShape.rectangular, label: Text('Rectangular')),
                ],
                selected: {s.defaultShape},
                onSelectionChanged: (v) => set(s.copyWith(defaultShape: v.first)),
              ),
              StepperRow(
                label: 'Max aspect ratio',
                value: '${s.maxAspect.toStringAsFixed(1)} : 1',
                onMinus: () => set(s.copyWith(maxAspect: (s.maxAspect - 0.5).clamp(1.0, 10.0))),
                onPlus: () => set(s.copyWith(maxAspect: (s.maxAspect + 0.5).clamp(1.0, 10.0))),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Limit rectangular height'),
                value: s.maxRectHeightM != null,
                onChanged: (on) => set(on ? s.copyWith(maxRectHeightM: 0.3) : s.copyWith(clearMaxRectHeight: true)),
              ),
              if (s.maxRectHeightM != null)
                StepperRow(
                  label: 'Max height',
                  value: fmt.dim(s.maxRectHeightM!),
                  onMinus: () => set(s.copyWith(maxRectHeightM: (s.maxRectHeightM! - fmt.dimStep).clamp(0.1, 2.0))),
                  onPlus: () => set(s.copyWith(maxRectHeightM: (s.maxRectHeightM! + fmt.dimStep).clamp(0.1, 2.0))),
                ),
              const Divider(height: 28),
              Text('Where a duct splits', style: t.titleSmall),
              const SizedBox(height: 4),
              const Text('A fitting is added automatically at every split into two or more children. A section can override this.'),
              const SizedBox(height: 8),
              SegmentedButton<JunctionType>(
                segments: const [
                  ButtonSegment(value: JunctionType.tee90, label: Text('90° tee')),
                  ButtonSegment(value: JunctionType.wye45, label: Text('45° wye')),
                  ButtonSegment(value: JunctionType.none, label: Text('None')),
                ],
                selected: {s.defaultJunction},
                onSelectionChanged: (v) => set(s.copyWith(defaultJunction: v.first)),
              ),
              const Divider(height: 28),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Snap to standard sizes'),
                subtitle: const Text('Losses are calculated on the standard size'),
                value: s.useStandardSizes,
                onChanged: (v) => set(s.copyWith(useStandardSizes: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto reducers'),
                subtitle: const Text('Add a reducer where an inline section changes size'),
                value: s.autoReducers,
                onChanged: (v) => set(s.copyWith(autoReducers: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Flag built-in coefficients'),
                subtitle: const Text('Warn on sections that use screening values instead of sourced ones'),
                value: s.requireSourcedFittings,
                onChanged: (v) => set(s.copyWith(requireSourcedFittings: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Imperial units'),
                subtitle: const Text('Also switches to the imperial size catalog'),
                value: c.imperial,
                onChanged: c.setImperial,
              ),
              const Divider(height: 28),
              StepperRow(
                label: 'Max velocity',
                value: fmt.velocity(s.maxVelocity),
                onMinus: () => set(s.copyWith(maxVelocity: (s.maxVelocity - fmt.velocityStep).clamp(2.0, 30.0))),
                onPlus: () => set(s.copyWith(maxVelocity: (s.maxVelocity + fmt.velocityStep).clamp(2.0, 30.0))),
              ),
              StepperRow(
                label: 'NC limit',
                value: s.ncLimit.toStringAsFixed(0),
                onMinus: () => set(s.copyWith(ncLimit: (s.ncLimit - 5).clamp(15.0, 65.0))),
                onPlus: () => set(s.copyWith(ncLimit: (s.ncLimit + 5).clamp(15.0, 65.0))),
              ),
              const Divider(height: 28),
              Text('Fitting library', style: t.titleSmall),
              const SizedBox(height: 4),
              Wrap(spacing: 8, runSpacing: 4, children: [
                OutlinedButton.icon(
                  onPressed: c.library.isEmpty ? null : () => shareLibraryFile(context, c),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Export'),
                ),
                OutlinedButton.icon(
                  onPressed: () => importLibraryFromPaste(context, c),
                  icon: const Icon(Icons.content_paste),
                  label: const Text('Paste'),
                ),
                OutlinedButton.icon(
                  onPressed: () => importLibraryFromFile(context, c),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Import'),
                ),
              ]),
              if (c.library.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Nothing saved yet. Tick "Save to project library" when adding a Sourced C or Table fitting.'),
                ),
              for (var i = 0; i < c.library.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(c.library[i].label),
                  subtitle: Text(c.library[i].dataSource),
                  trailing: IconButton(
                    tooltip: 'Remove ${c.library[i].label}',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => c.removeFromLibrary(i),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
