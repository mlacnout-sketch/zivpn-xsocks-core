import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class BackupRepository {
  Future<File?> createBackup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allPrefs = <String, dynamic>{};
      
      // 1. Collect all SharedPreferences
      final keys = prefs.getKeys();
      for (String key in keys) {
        // Skip ephemeral keys
        if (key == 'vpn_running' || key == 'vpn_start_time') continue;
        
        final val = prefs.get(key);
        allPrefs[key] = val;
      }

      // 2. Add Metadata & Integrity Hash
      allPrefs['backup_timestamp'] = DateTime.now().toIso8601String();
      allPrefs['integrity_hash'] = _generateIntegrityHash(allPrefs);

      // 3. Prepare Config JSON
      final configJson = jsonEncode(allPrefs);

      // 4. Create ZIP Archive
      final archive = Archive();
      archive.addFile(ArchiveFile('config.json', configJson.length, utf8.encode(configJson)));
      
      // 5. Save ZIP to temp atomically
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = "minizivpn_backup_$timestamp.zip";
      final zipFile = File('${tempDir.path}/$fileName');
      final tmpFile = File('${tempDir.path}/$fileName.tmp');
      
      final encoder = ZipEncoder();
      final zipData = encoder.encode(archive);
      if (zipData == null) return null;
      
      await tmpFile.writeAsBytes(zipData, flush: true);
      await tmpFile.rename(zipFile.path);
      
      return zipFile;
    } catch (e) {
      print("Backup failed: $e");
      return null;
    }
  }

  String _generateIntegrityHash(Map<String, dynamic> data) {
    final sortedKeys = data.keys.toList()..sort();
    var combined = "";
    for (var key in sortedKeys) {
      if (key == 'integrity_hash') continue;
      combined += "$key:${data[key]}";
    }
    // Simple but stable hash for integrity check
    return combined.hashCode.toRadixString(16);
  }

  Future<bool> restoreBackup(File backupFile) async {
    try {
      if (!await backupFile.exists()) return false;
      final bytes = await backupFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      // Find config.json
      final ArchiveFile? configFile = archive.findFile('config.json');
      if (configFile == null || configFile.content == null) {
        print("Restore failed: config.json missing or empty");
        return false;
      }
      
      final content = utf8.decode(configFile.content as List<int>);
      final dynamic decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        print("Restore failed: Invalid JSON format");
        return false;
      }
      
      final Map<String, dynamic> prefsData = decoded;
      
      // 1. Verify Integrity Hash
      final storedHash = prefsData['integrity_hash'];
      if (storedHash != null) {
        final currentHash = _generateIntegrityHash(prefsData);
        if (storedHash != currentHash) {
          print("Restore failed: Integrity check failed");
          return false;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      
      for (var entry in prefsData.entries) {
        final key = entry.key;
        final val = entry.value;
        
        // Skip metadata
        if (key == 'integrity_hash' || key == 'backup_timestamp') continue;
        
        try {
          if (val is bool) await prefs.setBool(key, val);
          else if (val is int) await prefs.setInt(key, val);
          else if (val is double) await prefs.setDouble(key, val);
          else if (val is String) await prefs.setString(key, val);
          else if (val is List) await prefs.setStringList(key, List<String>.from(val));
        } catch (e) {
          print("Failed to restore key $key: $e");
        }
      }
      
      return true;
    } catch (e) {
      print("Restore failed: $e");
      return false;
    }
  }
}
