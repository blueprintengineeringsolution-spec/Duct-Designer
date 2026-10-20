import 'dart:async';
import 'package:ar_flutter_plugin/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin/models/ar_hittest_result.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:hvac_engine/hvac_engine.dart';

/// The only file that touches the AR plugin. Reports each tapped surface point (metres).
/// If AR can't start, calls [onUnavailable] and the page falls back to typed readings.
/// To drop AR entirely, replace this widget's body with a call to onUnavailable.
class ArMeasureView extends StatefulWidget {
  final void Function(Point3) onPoint;
  final void Function(String) onUnavailable;
  const ArMeasureView({super.key, required this.onPoint, required this.onUnavailable});

  @override
  State<ArMeasureView> createState() => _ArMeasureViewState();
}

class _ArMeasureViewState extends State<ArMeasureView> {
  ARSessionManager? _session;
  Timer? _watchdog;
  final bool _supported = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    if (!_supported) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => widget.onUnavailable('AR measuring needs a phone or tablet with AR support.'));
    } else {
      _watchdog = Timer(const Duration(seconds: 8), () {
        widget.onUnavailable('AR did not start on this device. Use typed readings instead.');
      });
    }
  }

  void _created(ARSessionManager session, ARObjectManager objects, ARAnchorManager anchors, ARLocationManager location) {
    _watchdog?.cancel();
    _session = session;
    session.onInitialize(showFeaturePoints: true, showPlanes: true, showWorldOrigin: false, handleTaps: true);
    objects.onInitialize();
    session.onPlaneOrPointTap = (List<ARHitTestResult> hits) {
      if (hits.isEmpty) return;
      final p = hits.first.worldTransform.getTranslation();
      widget.onPoint(Point3(p.x, p.y, p.z));
    };
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) return const Center(child: Text('AR is not available here.'));
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ARView(
        onARViewCreated: _created,
        planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
      ),
    );
  }
}
