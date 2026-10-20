import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Mobile, desktop and VM: dart:io gzip, decoded as a stream so a size cap can stop a bomb early.
Future<List<int>> gzipEncodeBytes(List<int> data) async => gzip.encode(data);

Future<List<int>> gzipDecodeCapped(List<int> packed, int maxBytes) async {
  final out = BytesBuilder(copy: false);
  await for (final chunk in gzip.decoder.bind(Stream.value(packed))) {
    out.add(chunk);
    if (out.length > maxBytes) throw const FormatException('The shared project is too large');
  }
  return out.takeBytes();
}
