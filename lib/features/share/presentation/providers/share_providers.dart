import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hvac_engine/hvac_engine.dart';
import '../../data/platform_text_file_gateway.dart';
import '../../domain/text_file_gateway.dart';

final textFileGatewayProvider = Provider<TextFileGateway>((ref) => const PlatformTextFileGateway());

/// The QR / paste code for a project. Built once per project shown.
final shareCodeProvider = FutureProvider.autoDispose.family<String, ProjectDoc>(
  (ref, doc) => encodeShareCode(doc),
);
