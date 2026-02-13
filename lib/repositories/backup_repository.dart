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

      // 2. Prepare Config JSON
      final configJson = jsonEncode(allPrefs);

      // 3. Create ZIP Archive
      final archive = Archive();
      
      // Add config.json
      archive.addFile(ArchiveFile('config.json', configJson.length, utf8.encode(configJson)));
      
      // 4. Save ZIP to temp
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'minizivpn_backup_$timestamp.zip';
      final zipFile = File('${tempDir.path}/$fileName');
      
      final encoder = ZipEncoder();
      final zipData = encoder.encode(archive);
      if (zipData == null) return null;
      
      await zipFile.writeAsBytes(zipData);
      return zipFile;
    } catch (e) {
      print('Backup failed: $e');
      return null;
    }
  }

  Future<bool> restoreBackup(File backupFile) async {
    try {
      final bytes = await backupFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      // Find config.json
      final ArchiveFile? configFile = archive.findFile('config.json');
      if (configFile == null) return false;
      
      final content = utf8.decode(configFile.content as List<int>);
      final Map<String, dynamic> prefsData = jsonDecode(content);
      
      final prefs = await SharedPreferences.getInstance();
      
      // Clear current prefs or merge? Ideally clear relevant ones first to avoid ghost data.
      // But clearing everything might wipe 'vpn_running' state if app crashed.
      // We overwrite keys present in backup.
      
      for (var entry in prefsData.entries) {
        final key = entry.key;
        final val = entry.value;
        
        if (val is bool) {
          await prefs.setBool(key, val);
        } else if (val is int) await prefs.setInt(key, val);
        else if (val is double) await prefs.setDouble(key, val);
        else if (val is String) await prefs.setString(key, val);
        else if (val is List) await prefs.setStringList(key, List<String>.from(val));
      }
      
      return true;
    } catch (e) {
      print('Restore failed: $e');
      return false;
    }
  }
}
