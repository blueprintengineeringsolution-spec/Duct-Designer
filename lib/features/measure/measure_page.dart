import 'package:flutter/material.dart';
import 'package:hvac_engine/hvac_engine.dart';
import '../../core/fmt.dart';
import 'ar_measure_view.dart';

typedef ArBuilder = Widget Function(
  BuildContext context,
  void Function(Point3) onPoint,
  void Function(String) onUnavailable,
);

enum _Mode { ar, tape }

/// Measures a run by AR taps or typed tape / laser readings. Pops the rounded total
/// (metres) when the user confirms, or null if they cancel.
class MeasurePage extends StatefulWidget {
  final String title;
  final double currentLengthM;
  final Fmt fmt;
  final ArBuilder? arBuilder; // for tests; defaults to the real AR view
  const MeasurePage({
    super.key,
    required this.title,
    required this.currentLengthM,
    required this.fmt,
    this.arBuilder,
  });

  @override
  State<MeasurePage> createState() => _MeasurePageState();
}

class _MeasurePageState extends State<MeasurePage> {
  LengthRun _run = const LengthRun();
  final List<bool> _fromAr = []; // parallel to run segments
  final List<Point3> _pts = []; // current AR chain
  _Mode _mode = _Mode.ar;
  String? _note;
  final _tape = TextEditingController();

  bool get _hasAr => _fromAr.any((b) => b);

  @override
  void dispose() {
    _tape.dispose();
    super.dispose();
  }

  void _onPoint(Point3 p) {
    if (_pts.isEmpty) {
      setState(() => _pts.add(p));
      return;
    }
    final d = _pts.last.distanceTo(p);
    if (!LengthRun.isValidSegment(d)) return; // tapped the same spot
    setState(() {
      _run = _run.add(d);
      _fromAr.add(true);
      _pts.add(p);
    });
  }

  void _onUnavailable(String why) {
    if (!mounted) return;
    setState(() {
      _mode = _Mode.tape;
      _note = why;
    });
  }

  void _addTape() {
    final v = double.tryParse(_tape.text.trim().replaceAll(',', '.'));
    final m = v == null ? null : (widget.fmt.imperial ? v * 0.3048 : v);
    if (m == null || !LengthRun.isValidSegment(m)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a length greater than 0.')));
      return;
    }
    setState(() {
      _run = _run.add(m);
      _fromAr.add(false);
      _tape.clear();
    });
  }

  void _undo() {
    setState(() {
      if (_run.segmentsM.isEmpty) {
        if (_pts.isNotEmpty) _pts.removeLast();
        return;
      }
      final wasAr = _fromAr.removeLast();
      _run = _run.undo();
      if (wasAr && _pts.isNotEmpty) _pts.removeLast();
    });
  }

  Widget _arView(BuildContext context) {
    final custom = widget.arBuilder;
    if (custom != null) return custom(context, _onPoint, _onUnavailable);
    return ArMeasureView(onPoint: _onPoint, onUnavailable: _onUnavailable);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = widget.fmt;
    final t = Theme.of(context).textTheme;
    final total = _run.totalM;
    final rounded = roundLength(total, imperial: fmt.imperial);
    final warnings = _run.warnings(fromAr: _hasAr);
    final segs = _run.segmentsM;

    return Scaffold(
      appBar: AppBar(title: Text('Measure: ${widget.title}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SegmentedButton<_Mode>(
            segments: const [
              ButtonSegment(value: _Mode.ar, label: Text('AR'), icon: Icon(Icons.view_in_ar_outlined)),
              ButtonSegment(value: _Mode.tape, label: Text('Tape'), icon: Icon(Icons.straighten)),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() {
              _mode = s.first;
              _note = null;
            }),
          ),
          if (_note != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_note!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 12),
          if (_mode == _Mode.ar) ...[
            SizedBox(
              height: 300,
              child: _arView(context),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Text(_pts.isEmpty
                    ? 'Tap the start of the run.'
                    : 'Tap the next point. ${_pts.length} placed.'),
              ),
              if (_pts.isNotEmpty) TextButton(onPressed: () => setState(_pts.clear), child: const Text('New start point')),
            ]),
          ] else ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: TextField(
                  controller: _tape,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Reading (${fmt.imperial ? 'ft' : 'm'})'),
                  onSubmitted: (_) => _addTape(),
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: FilledButton(onPressed: _addTape, child: const Text('Add')),
              ),
            ]),
            const SizedBox(height: 4),
            const Text('Add each tape or laser reading. They are summed.'),
          ],
          const Divider(height: 28),
          if (segs.isEmpty) const Text('No segments yet.'),
          for (var i = 0; i < segs.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(_fromAr[i] ? Icons.view_in_ar_outlined : Icons.straighten, size: 20),
              title: Text('Segment ${i + 1}'),
              trailing: Text(fmt.length(segs[i])),
            ),
          const SizedBox(height: 8),
          Text('Total ${fmt.length(total)}', style: t.titleLarge),
          Text('Section length now ${fmt.length(widget.currentLengthM)}', style: t.bodySmall),
          if (_hasAr)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'AR estimate, typically within about ${fmt.length(_run.estimatedErrorM(fromAr: true))}. '
                'Check against a tape before ordering material.',
              ),
            ),
          for (final w in warnings)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.warning_amber_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(w)),
              ]),
            ),
          const SizedBox(height: 16),
          Row(children: [
            OutlinedButton.icon(
              onPressed: (segs.isEmpty && _pts.isEmpty) ? null : _undo,
              icon: const Icon(Icons.undo),
              label: const Text('Undo'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: total > 0 ? () => Navigator.pop(context, rounded) : null,
                child: Text('Use ${fmt.length(rounded)}'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
