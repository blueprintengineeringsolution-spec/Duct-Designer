import 'dart:ui';
import 'package:hvac_engine/hvac_engine.dart';

Color statusColor(NodeStatus s) {
  switch (s) {
    case NodeStatus.optimal:
      return const Color(0xFF2E9E5B);
    case NodeStatus.caution:
      return const Color(0xFFE0A100);
    case NodeStatus.critical:
      return const Color(0xFFD64545);
  }
}
