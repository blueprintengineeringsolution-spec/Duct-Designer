import 'package:ductletor_pro/core/file_download.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('outside a browser nothing is downloaded and the caller falls back', () async {
    expect(await downloadTextFile('x.txt', 'hello'), isFalse);
  });
}
