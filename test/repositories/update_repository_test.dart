import 'package:flutter_test/flutter_test.dart';
import 'package:mini_zivpn/repositories/update_repository.dart';

void main() {
  late UpdateRepository repository;

  setUp(() {
    repository = UpdateRepository();
  });

  group('isNewerVersion', () {
    test('returns true for major version update', () {
      expect(repository.isNewerVersion('2.0.0', '1.0.0'), isTrue);
    });

    test('returns true for minor version update', () {
      expect(repository.isNewerVersion('1.1.0', '1.0.0'), isTrue);
    });

    test('returns true for patch version update', () {
      expect(repository.isNewerVersion('1.0.1', '1.0.0'), isTrue);
    });

    test('returns false for same version', () {
      expect(repository.isNewerVersion('1.0.0', '1.0.0'), isFalse);
    });

    test('returns false for older major version', () {
      expect(repository.isNewerVersion('0.9.0', '1.0.0'), isFalse);
    });

    test('returns false for older minor version', () {
      expect(repository.isNewerVersion('1.0.0', '1.1.0'), isFalse);
    });

    test('returns false for older patch version', () {
      expect(repository.isNewerVersion('1.0.0', '1.0.1'), isFalse);
    });

    test('returns false for malformed version strings', () {
      expect(repository.isNewerVersion('invalid', '1.0.0'), isFalse);
      expect(repository.isNewerVersion('1.0.0', 'invalid'), isFalse);
      expect(repository.isNewerVersion('1.0', '1.0.0'), isFalse); // Regex requires 3 parts
    });
  });

  group('findUpdateInJson', () {
    test('returns AppVersion when a valid newer version with APK is found', () {
      final jsonStr = '''
      [
        {
          "tag_name": "1.1.0",
          "body": "New features",
          "assets": [
            {
              "name": "app-release.apk",
              "content_type": "application/vnd.android.package-archive",
              "browser_download_url": "https://example.com/app.apk",
              "size": 1024
            }
          ]
        },
        {
          "tag_name": "1.0.0",
          "assets": []
        }
      ]
      ''';

      final result = repository.findUpdateInJson(jsonStr, '1.0.0');

      expect(result, isNotNull);
      expect(result!.name, '1.1.0');
      expect(result.apkUrl, 'https://example.com/app.apk');
      expect(result.apkSize, 1024);
      expect(result.description, 'New features');
    });

    test('returns null when newer version has no APK asset', () {
      final jsonStr = '''
      [
        {
          "tag_name": "1.1.0",
          "assets": [
            {
              "name": "source.zip",
              "content_type": "application/zip",
              "browser_download_url": "https://example.com/source.zip",
              "size": 500
            }
          ]
        }
      ]
      ''';

      final result = repository.findUpdateInJson(jsonStr, '1.0.0');

      expect(result, isNull);
    });

    test('returns null when only older versions are available', () {
      final jsonStr = '''
      [
        {
          "tag_name": "0.9.0",
          "assets": [
            {
              "name": "app.apk",
              "content_type": "application/vnd.android.package-archive",
              "browser_download_url": "https://example.com/app.apk",
              "size": 1024
            }
          ]
        }
      ]
      ''';

      final result = repository.findUpdateInJson(jsonStr, '1.0.0');

      expect(result, isNull);
    });

    test('returns null for malformed JSON', () {
      final jsonStr = '{ "tag_name": "1.1.0" }'; // Not a list

      final result = repository.findUpdateInJson(jsonStr, '1.0.0');

      expect(result, isNull);
    });

    test('handles null assets gracefully', () {
       final jsonStr = '''
      [
        {
          "tag_name": "1.1.0",
          "assets": null
        }
      ]
      ''';
      final result = repository.findUpdateInJson(jsonStr, '1.0.0');
      expect(result, isNull);
    });
  });
}
