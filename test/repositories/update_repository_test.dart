import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
// Import the repository. Assuming package structure.
// Since I'm in test/repositories, I need to import correctly.
// I don't know the package name from here, but relative imports work in tests if aligned.
// Or I can use 'package:app_name/...' if I knew the app name.
// I'll try relative import.
import '../../lib/repositories/update_repository.dart';

// --- Mocks ---

class MockHttpClient extends Fake implements HttpClient {
  String? findProxyString;
  bool shouldFail = false;

  @override
  set findProxy(String Function(Uri url)? f) {
    if (f != null) {
      findProxyString = f(Uri.parse('http://example.com'));
    }
  }

  @override
  set connectionTimeout(Duration? duration) {}

  @override
  set userAgent(String? userAgent) {}

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    if (shouldFail) {
      throw const SocketException("Connection failed");
    }
    return MockHttpClientRequest();
  }

  @override
  void close({bool force = false}) {}
}

class MockHttpClientRequest extends Fake implements HttpClientRequest {
  @override
  Future<HttpClientResponse> close() async {
    return MockHttpClientResponse();
  }
}

class MockHttpClientResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => 200;

  @override
  Stream<S> transform<S>(StreamTransformer<List<int>, S> streamTransformer) {
    // For check update, we need to return a stream that decodes to JSON
    // The repo uses utf8.decoder.join()
    // We can return a Stream<List<int>> that is utf8 bytes of JSON.
    final jsonStr =
        '[{"tag_name": "1.0.1", "assets": [{"name": "app.apk", "content_type": "application/vnd.android.package-archive", "browser_download_url": "http://example.com/app.apk", "size": 1024}]}]';
    return Stream.value(utf8.encode(jsonStr))
        .cast<List<int>>()
        .transform(streamTransformer);
  }

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    final jsonStr =
        '[{"tag_name": "1.0.1", "assets": [{"name": "app.apk", "content_type": "application/vnd.android.package-archive", "browser_download_url": "http://example.com/app.apk", "size": 1024}]}]';
    return Stream.value(utf8.encode(jsonStr)).listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}

class TestHttpOverrides extends HttpOverrides {
  final List<MockHttpClient> clients = [];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = MockHttpClient();
    // Configure the client based on how many have been requested
    // Logic: First client (SOCKS) should fail, Second (DIRECT) should succeed?
    // Or we just verify the configuration.

    // For this test, let's make the first one fail to verify fallback.
    if (clients.isEmpty) {
      client.shouldFail = true; // SOCKS fails
    } else {
      client.shouldFail = false; // DIRECT succeeds
    }

    clients.add(client);
    return client;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UpdateRepository Tests', () {
    late UpdateRepository repository;
    late TestHttpOverrides httpOverrides;

    setUp(() {
      repository = UpdateRepository();
      httpOverrides = TestHttpOverrides();
      HttpOverrides.global = httpOverrides;

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
      HttpOverrides.global = null;
    });

    test('fetchUpdate tries SOCKS then DIRECT', () async {
      // Act
      final update = await repository.fetchUpdate();

      // Assert
      // We expect 2 clients to have been created.
      expect(httpOverrides.clients.length, 2);

      // 1st client: SOCKS
      final client1 = httpOverrides.clients[0];
      expect(client1.findProxyString, contains("SOCKS 127.0.0.1:7777"));

      // 2nd client: DIRECT
      final client2 = httpOverrides.clients[1];
      expect(client2.findProxyString,
          isNull); // DIRECT means findProxy not set in code

      // Verification of result
      expect(update, isNotNull);
      expect(update!.name, "1.0.1");
    });
  });
}
