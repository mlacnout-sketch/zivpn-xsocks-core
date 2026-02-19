import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class BackupRepository {
  static const String _backupMagic = "ZIVPN_BKP_V1";
  static const String _xorKey = "turbo_socks_2026";

  Future<File?> createBackup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allPrefs = <String, dynamic>{};
      
      // 1. Collect all SharedPreferences
      final keys = prefs.getKeys();
      for (String key in keys) {
        // Skip ephemeral or binary keys
        if (key == 'vpn_running' || key == 'vpn_start_time' || key.startsWith('libuz_')) continue;
        
        final val = prefs.get(key);
        allPrefs[key] = val;
      }

      // 2. Prepare Config JSON with Metadata
      final backupData = {
        'magic': _backupMagic,
        'timestamp': DateTime.now().toIso8601String(),
        'app_version': '1.0.27',
        'data': allPrefs,
      };
      
      final configJson = jsonEncode(backupData);
      
      // 3. Encrypt JSON (Simple XOR for basic security against casual inspection)
      final encryptedBytes = _xorCipher(utf8.encode(configJson));

      // 4. Create ZIP Archive
      final archive = Archive();
      archive.addFile(ArchiveFile('vault.bin', encryptedBytes.length, encryptedBytes));
      
      // 5. Save ZIP to temp
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = "zivpn_backup_$timestamp.zip";
      final zipFile = File('${tempDir.path}/$fileName');
      
      final encoder = ZipEncoder();
      final zipData = encoder.encode(archive);
      if (zipData == null) return null;
      
      await zipFile.writeAsBytes(zipData);
      return zipFile;
    } catch (e) {
      print("Backup failed: $e");
      return null;
    }
  }

  Future<bool> restoreBackup(File backupFile) async {
    try {
      final bytes = await backupFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      // Find vault.bin (Encrypted) or config.json (Old Legacy)
      final ArchiveFile? vaultFile = archive.findFile('vault.bin');
      final ArchiveFile? legacyFile = archive.findFile('config.json');
      
      String content;
      if (vaultFile != null) {
        final decryptedBytes = _xorCipher(vaultFile.content as List<int>);
        content = utf8.decode(decryptedBytes);
      } else if (legacyFile != null) {
        content = utf8.decode(legacyFile.content as List<int>);
      } else {
        return false;
      }

      final Map<String, dynamic> backupJson = jsonDecode(content);
      
      // Validate Magic if using new format
      if (vaultFile != null && backupJson['magic'] != _backupMagic) {
        print("Invalid backup format");
        return false;
      }

      final Map<String, dynamic> prefsData = vaultFile != null 
          ? Map<String, dynamic>.from(backupJson['data']) 
          : backupJson;
      
      final prefs = await SharedPreferences.getInstance();
      
      for (var entry in prefsData.entries) {
        final key = entry.key;
        final val = entry.value;
        
        if (val is bool) await prefs.setBool(key, val);
        else if (val is int) await prefs.setInt(key, val);
        else if (val is double) await prefs.setDouble(key, val);
        else if (val is String) await prefs.setString(key, val);
        else if (val is List) await prefs.setStringList(key, List<String>.from(val));
      }
      
      return true;
    } catch (e) {
      print("Restore failed: $e");
      return false;
    }
  }

  List<int> _xorCipher(List<int> input) {
    final keyBytes = utf8.encode(_xorKey);
    final output = List<int>.filled(input.length, 0);
    for (int i = 0; i < input.length; i++) {
      output[i] = input[i] ^ keyBytes[i % keyBytes.length];
    }
    return output;
  }
}
