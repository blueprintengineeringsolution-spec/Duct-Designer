import 'dart:typed_data';

/// What happened when a text file was handed to the platform.
enum TextFileShareOutcome {
  /// The system share sheet was shown (phones and desktops).
  shared,

  /// The browser saved the file to its downloads.
  downloaded,

  /// The browser refused to save a file, so the text was copied to the clipboard instead.
  copied,
}

/// A file the person picked, not yet read.
class PickedFile {
  final int size;
  final Future<Uint8List> Function() readBytes;
  const PickedFile({required this.size, required this.readBytes});
}

/// Hands text files to the platform and picks files from it.
abstract class TextFileGateway {
  /// Phones and desktops: the system share sheet with a file. Browsers download the file; if
  /// the browser refuses, the text is copied so it can be pasted into Import > Paste instead.
  Future<TextFileShareOutcome> shareTextFile({
    required String text,
    required String fileName,
    required String subject,
    String mimeType = 'application/json',
  });

  /// Null if the person cancelled.
  Future<PickedFile?> pickFile();
}
