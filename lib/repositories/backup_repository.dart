import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';

class BackupRepository {
  static const Set<String> _ephemeralKeys = {
    'vpn_running',
    'vpn_start_time',
  };

  static const String savedAccountsKey = 'saved_accounts';
  static const String activeAccountIndexKey = 'active_account_index';

  Future<File?> createBackup({Account? specificAccount}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sourcePrefs = <String, dynamic>{};

      final keys = prefs.getKeys();
      for (final key in keys) {
        if (_ephemeralKeys.contains(key)) continue;
        sourcePrefs[key] = prefs.get(key);
      }

      final allPrefs = prepareBackupPrefs(sourcePrefs, specificAccount: specificAccount);
      final configJson = jsonEncode(allPrefs);
      final configBytes = utf8.encode(configJson);

      final archive = Archive();
      archive.addFile(ArchiveFile('config.json', configBytes.length, configBytes));

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final suffix = specificAccount == null ? '' : '_${_safeAccountName(specificAccount.name)}';
      final fileName = 'minizivpn_backup_${timestamp}${suffix}.zip';
      final zipFile = File('${tempDir.path}/$fileName');

      final zipData = ZipEncoder().encode(archive);
      if (zipData == null) return null;

      await zipFile.writeAsBytes(zipData, flush: true);
      return zipFile;
    } catch (e) {
      print('Backup failed: $e');
      return null;
    }
  }

  Map<String, dynamic> prepareBackupPrefs(
    Map<String, dynamic> rawPrefs, {
    Account? specificAccount,
  }) {
    final sanitized = <String, dynamic>{};
    for (final entry in rawPrefs.entries) {
      if (_ephemeralKeys.contains(entry.key)) continue;
      sanitized[entry.key] = entry.value;
    }

    if (specificAccount != null) {
      sanitized[savedAccountsKey] = jsonEncode([specificAccount.toJson()]);
      sanitized[activeAccountIndexKey] = 0;
      sanitized['ip'] = specificAccount.ip;
      sanitized['auth'] = specificAccount.auth;
      sanitized['obfs'] = specificAccount.obfs;
    }

    return sanitized;
  }

  Future<bool> restoreBackup(File backupFile) async {
    try {
      final bytes = await backupFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final configFile = archive.findFile('config.json');
      if (configFile == null) return false;

      final contentBytes = _extractBytes(configFile.content);
      if (contentBytes == null) return false;

      final content = utf8.decode(contentBytes);
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return false;
      final prefsData = decoded;

      final prefs = await SharedPreferences.getInstance();

      final currentKeys = prefs.getKeys();
      final backupKeys = prefsData.keys.toSet();
      for (final key in currentKeys) {
        if (_ephemeralKeys.contains(key)) continue;
        if (!backupKeys.contains(key)) {
          await prefs.remove(key);
        }
      }

      for (final entry in prefsData.entries) {
        final key = entry.key;
        if (_ephemeralKeys.contains(key)) continue;

        final val = entry.value;
        if (val is bool) {
          await prefs.setBool(key, val);
        } else if (val is int) {
          await prefs.setInt(key, val);
        } else if (val is double) {
          await prefs.setDouble(key, val);
        } else if (val is String) {
          await prefs.setString(key, val);
        } else if (val is List) {
          final stringList = val.map((e) => e.toString()).toList();
          await prefs.setStringList(key, stringList);
        }
      }

      return true;
    } catch (e) {
      print('Restore failed: $e');
      return false;
    }
  }

  List<int>? _extractBytes(dynamic content) {
    if (content is List<int>) return content;
    if (content is Uint8List) return content;
    return null;
  }

  String _safeAccountName(String input) {
    final cleaned = input.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
    return cleaned.isEmpty ? 'account' : cleaned;
  }
}
