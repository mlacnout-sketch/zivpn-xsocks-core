import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../lib/repositories/update_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.minizivpn.app/core');

  group('UpdateRepository Tests', () {
    late UpdateRepository repository;
    final List<MethodCall> log = <MethodCall>[];

    setUp(() {
      repository = UpdateRepository();
      
      // Mock MethodChannel
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        log.add(methodCall);
        if (methodCall.method == 'checkUpdateNative') {
          return '[{"tag_name": "1.0.1", "assets": [{"content_type": "application/vnd.android.package-archive", "browser_download_url": "http://example.com/app.apk", "size": 1024}]}]';
        }
        return null;
      });

      // Mock PackageInfo
      PackageInfo.setMockInitialValues(
        appName: "TestApp",
        packageName: "com.test.app",
        version: "1.0.0",
        buildNumber: "1",
        buildSignature: "",
      );
    });

    tearDown(() {
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('fetchUpdate calls native method and parses response', () async {
      // Act
      final update = await repository.fetchUpdate();

      // Assert
      expect(log, [
        isMethodCall('checkUpdateNative', arguments: {
          'url': 'https://api.github.com/repos/mlacnout-sketch/zivpn-xsocks-core/releases'
        }),
      ]);

      expect(update, isNotNull);
      expect(update!.name, "1.0.1");
      expect(update.apkUrl, "http://example.com/app.apk");
    });
  });
}
