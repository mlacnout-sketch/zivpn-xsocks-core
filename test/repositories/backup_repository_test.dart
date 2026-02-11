import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
// Adjust import path as needed based on actual file location
import 'package:mini_zivpn/repositories/backup_repository.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class FakePathProviderPlatform extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  final Directory tempDir;

  FakePathProviderPlatform(this.tempDir);

  @override
  Future<String?> getTemporaryPath() async {
    return tempDir.path;
  }
}

class FailingPathProviderPlatform extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async {
    throw Exception('Simulated path provider error');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    // Create a temporary directory for the test
    tempDir = await Directory.systemTemp.createTemp('backup_test');

    // Mock PathProvider to return our temp directory
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir);
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (e) {
      print("Failed to delete temp dir: $e");
    }
  });

  group('BackupRepository', () {
    test('createBackup creates a valid zip file with filtered preferences', () async {
      // 1. Setup SharedPreferences with mock data
      SharedPreferences.setMockInitialValues({
        'user_token': 'abc-123',
        'theme_mode': 'dark',
        'vpn_running': true, // Should be ignored
        'vpn_start_time': 1234567890, // Should be ignored
        'connection_count': 5
      });

      final repository = BackupRepository();

      // 2. Call createBackup
      final File? backupFile = await repository.createBackup();

      // 3. Verify file creation
      expect(backupFile, isNotNull);
      expect(backupFile!.existsSync(), isTrue);
      expect(backupFile.path.endsWith('.zip'), isTrue);

      // 4. Verify zip content
      final bytes = await backupFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final ArchiveFile? configFile = archive.findFile('config.json');
      expect(configFile, isNotNull, reason: 'config.json should exist in the zip');

      final contentString = utf8.decode(configFile!.content as List<int>);
      final Map<String, dynamic> config = jsonDecode(contentString);

      // 5. Verify data integrity
      expect(config['user_token'], 'abc-123');
      expect(config['theme_mode'], 'dark');
      expect(config['connection_count'], 5);

      // 6. Verify exclusions
      expect(config.containsKey('vpn_running'), isFalse, reason: 'vpn_running should be excluded');
      expect(config.containsKey('vpn_start_time'), isFalse, reason: 'vpn_start_time should be excluded');
    });

    test('createBackup handles empty preferences', () async {
      // 1. Setup empty SharedPreferences
      SharedPreferences.setMockInitialValues({});

      final repository = BackupRepository();

      // 2. Call createBackup
      final File? backupFile = await repository.createBackup();

      // 3. Verify file creation
      expect(backupFile, isNotNull);

      // 4. Verify zip content
      final bytes = await backupFile!.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final ArchiveFile? configFile = archive.findFile('config.json');

      expect(configFile, isNotNull);
      final contentString = utf8.decode(configFile!.content as List<int>);
      final Map<String, dynamic> config = jsonDecode(contentString);

      // 5. Verify it is empty
      expect(config.isEmpty, isTrue);
    });

    test('createBackup returns null on error', () async {
      // 1. Setup Failing PathProvider
      PathProviderPlatform.instance = FailingPathProviderPlatform();

      final repository = BackupRepository();

      // 2. Call createBackup
      final File? backupFile = await repository.createBackup();

      // 3. Verify returns null
      expect(backupFile, isNull);
    });
  });
}
