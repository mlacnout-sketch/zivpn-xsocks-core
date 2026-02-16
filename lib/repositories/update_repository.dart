import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/app_version.dart';

class UpdateRepository {
  static const _platform = MethodChannel('com.minizivpn.app/core');
  final String apiUrl = "https://api.github.com/repos/mlacnout-sketch/zivpn-xsocks-core/releases";

  // Use Native Bridge to bypass VPN exclusions/routing issues
  Future<AppVersion?> fetchUpdate() async {
    try {
      final responseBody = await _platform.invokeMethod('checkUpdateNative', {'url': apiUrl});
      if (responseBody != null) {
        return await _processResponse(responseBody);
      }
    } catch (e) {
      print("Update check failed: $e");
    }
    return null;
  }

  Future<File?> downloadUpdate(AppVersion version, File targetFile, Function(double) onProgress) async {
    try {
      // Notify start (Native download is blocking/indeterminate for now)
      onProgress(0.1);
      
      final result = await _platform.invokeMethod('downloadUpdateNative', {
        'url': version.apkUrl,
        'path': targetFile.path
      });

      if (result == "OK") {
        onProgress(1.0);
        return targetFile;
      }
    } catch (e) {
      print("Download failed: $e");
      if (await targetFile.exists()) {
        try { await targetFile.delete(); } catch (_) {}
      }
    }
    return null;
  }

  Future<AppVersion?> _processResponse(String jsonStr) async {
      final List releases = json.decode(jsonStr);
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      
      print("Current App: $currentVersion");
      
      for (var release in releases) {
        final tagName = release['tag_name'].toString();
        if (_isNewer(tagName, currentVersion)) {
          final assets = release['assets'] as List?;
          if (assets == null) continue;

          final asset = assets.firstWhere(
            (a) => a['content_type'] == 'application/vnd.android.package-archive' || a['name'].toString().endsWith('.apk'),
            orElse: () => null
          );

          if (asset != null) {
            return AppVersion(
              name: tagName,
              apkUrl: asset['browser_download_url'],
              apkSize: asset['size'],
              description: release['body'] ?? "",
            );
          }
        }
      }
      return null;
  }

  bool _isNewer(String latestTag, String currentVersion) {
    try {
      final remoteVersion = _extractVersionParts(latestTag);
      final localVersion = _extractVersionParts(currentVersion);

      if (remoteVersion.isEmpty || localVersion.isEmpty) {
        return false;
      }

      final compare = _compareVersionParts(remoteVersion, localVersion);
      // Strictly greater means newer version. Equal or less means no update.
      // We explicitly ignore build number differences as requested.
      return compare > 0;
    } catch (e) {
      print("Version check error: $e");
      return false;
    }
  }

  List<int> _extractVersionParts(String value) {
    final match = RegExp(r'(\d+(?:\.\d+)+)').firstMatch(value);
    if (match == null) return const [];

    return match
        .group(1)!
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
  }

  int _compareVersionParts(List<int> remote, List<int> local) {
    final maxLen = remote.length > local.length ? remote.length : local.length;
    for (int i = 0; i < maxLen; i++) {
      final r = i < remote.length ? remote[i] : 0;
      final l = i < local.length ? local[i] : 0;
      if (r > l) return 1;
      if (r < l) return -1;
    }
    return 0;
  }
}
