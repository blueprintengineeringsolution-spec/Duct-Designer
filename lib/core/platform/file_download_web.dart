import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Saves [text] as a file through the browser's download. Returns false if the browser refused.
Future<bool> downloadTextFile(String fileName, String text, {String mimeType = 'application/json'}) async {
  try {
    final blob = web.Blob([text.toJS].toJS, web.BlobPropertyBag(type: '$mimeType;charset=utf-8'));
    final url = web.URL.createObjectURL(blob);
    final a = web.document.createElement('a') as web.HTMLAnchorElement;
    a.href = url;
    a.download = fileName;
    a.style.display = 'none';
    web.document.body?.append(a);
    a.click();
    a.remove();
    web.URL.revokeObjectURL(url);
    return true;
  } catch (_) {
    return false;
  }
}
