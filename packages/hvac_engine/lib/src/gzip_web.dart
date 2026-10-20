import 'package:archive/archive.dart';

/// Browser: dart:io gzip is unavailable, so use the pure-Dart archive package.
Future<List<int>> gzipEncodeBytes(List<int> data) async {
  final List<int>? out = GZipEncoder().encode(data);
  if (out == null) throw const FormatException('Could not compress the project');
  return out;
}

/// The size recorded at the end of the gzip data is checked before unpacking. A file that
/// lies about it can still use a lot of memory in the browser tab, but nothing else.
Future<List<int>> gzipDecodeCapped(List<int> packed, int maxBytes) async {
  if (packed.length < 18) throw const FormatException('The shared code is damaged');
  final n = packed.length;
  final claimed = packed[n - 4] | (packed[n - 3] << 8) | (packed[n - 2] << 16) | (packed[n - 1] << 24);
  if (claimed > maxBytes) throw const FormatException('The shared project is too large');
  final List<int> out = GZipDecoder().decodeBytes(packed);
  if (out.length > maxBytes) throw const FormatException('The shared project is too large');
  return out;
}
