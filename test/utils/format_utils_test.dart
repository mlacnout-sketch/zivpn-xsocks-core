import 'package:flutter_test/flutter_test.dart';
import 'package:mini_zivpn/utils/format_utils.dart';

void main() {
  group('FormatUtils', () {
    test('formats bytes correctly', () {
      expect(FormatUtils.formatBytes(500), '500 B');
      expect(FormatUtils.formatBytes(1023), '1023 B');
    });

    test('formats kilobytes correctly', () {
      expect(FormatUtils.formatBytes(1024), '1.0 KB');
      // 1.5 * 1024 = 1536
      expect(FormatUtils.formatBytes(1536), '1.5 KB');
    });

    test('formats megabytes correctly', () {
      expect(FormatUtils.formatBytes(1024 * 1024), '1.00 MB');
      // 2.5 * 1024 * 1024 = 2621440
      expect(FormatUtils.formatBytes(2621440), '2.50 MB');
    });

    test('formats gigabytes correctly', () {
      expect(FormatUtils.formatBytes(1024 * 1024 * 1024), '1.00 GB');
      // 2.5 * 1024 * 1024 * 1024 = 2684354560
      expect(FormatUtils.formatBytes(2684354560), '2.50 GB');
    });

    test('handles speed format correctly', () {
      expect(FormatUtils.formatBytes(500, asSpeed: true), '500 B/s');
      expect(FormatUtils.formatBytes(1024, asSpeed: true), '1.0 KB/s');
      expect(FormatUtils.formatBytes(1024 * 1024, asSpeed: true), '1.00 MB/s');
    });
  });
}
