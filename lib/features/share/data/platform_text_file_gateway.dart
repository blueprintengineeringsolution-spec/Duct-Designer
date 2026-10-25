import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/platform/file_download.dart';
import '../domain/text_file_gateway.dart';

class PlatformTextFileGateway implements TextFileGateway {
  const PlatformTextFileGateway();

  @override
  Future<TextFileShareOutcome> shareTextFile({
    required String text,
    required String fileName,
    required String subject,
    String mimeType = 'application/json',
  }) async {
    if (kIsWeb) {
      if (await downloadTextFile(fileName, text, mimeType: mimeType)) return TextFileShareOutcome.downloaded;
      await Clipboard.setData(ClipboardData(text: text));
      return TextFileShareOutcome.copied;
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(text, flush: true);
    await Share.shareXFiles([XFile(file.path, mimeType: mimeType)], subject: subject);
    return TextFileShareOutcome.shared;
  }

  @override
  Future<PickedFile?> pickFile() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (r == null || r.files.isEmpty) return null;
    final f = r.files.single;
    return PickedFile(size: f.size, readBytes: () async => f.bytes ?? await File(f.path!).readAsBytes());
  }
}
