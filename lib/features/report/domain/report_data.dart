import 'package:hvac_engine/hvac_engine.dart';
import '../../../core/formatting/fmt.dart';
import '../../project_editor/domain/project_editor_state.dart';

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

  factory ReportData.fromEditor(ProjectEditorState c, {DateTime? when}) {
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
