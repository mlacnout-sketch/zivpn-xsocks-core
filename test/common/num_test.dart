import 'package:flutter_test/flutter_test.dart';
import 'package:mini_zivpn/common/num.dart';

void main() {
  group('formatBytes', () {
    test('formats bytes boundary from B to KB at 1024', () {
      expect(formatBytes(1023), '1023 B');
      expect(formatBytes(1024), '1.0 KB');
    });

    test('formats bytes boundary from KB to MB at 1 MiB', () {
      expect(formatBytes(1024 * 1024 - 1), '1024.0 KB');
      expect(formatBytes(1024 * 1024), '1.00 MB');
    });

    test('formats speed suffix correctly', () {
      expect(formatBytes(1023, perSecond: true), '1023 B/s');
      expect(formatBytes(1024, perSecond: true), '1.0 KB/s');
    });

    test('treats negative values as zero', () {
      expect(formatBytes(-1), '0 B');
    });
  });
}
