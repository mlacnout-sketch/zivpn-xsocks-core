import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/app_version.dart';

class UpdateRepository {
  static const _platform = MethodChannel('com.minizivpn.app/core');
  final String apiUrl = "https://api.github.com/repos/mlacnout-sketch/zivpn-xsocks-core/releases";

  Future<String> _getDeviceAbi() async {
    try {
      final String? abi = await _platform.invokeMethod('getABI');
      return abi ?? "arm64-v8a";
    } catch (e) {
      print("Failed to get ABI: $e");
      return "arm64-v8a";
    }
  }

  // Use Native Bridge to bypass VPN exclusions/routing issues
  Future<AppVersion?> fetchUpdate() async {
    try {
      print("Checking for updates via Native Bridge (SOCKS5 Loopback)...");
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
      print("Downloading update: ${version.name} for ${version.apkUrl}");
      // Notify start
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
      final deviceAbi = await _getDeviceAbi();
      
      print("Update Check: Current=$currentVersion, ABI=$deviceAbi");
      
      for (var release in releases) {
        final tagName = release['tag_name'].toString();
        if (_isNewer(tagName, currentVersion)) {
          final assets = release['assets'] as List?;
          if (assets == null) continue;

          // ABI Filtering Strategy:
          // 1. Look for assets containing the specific device ABI (e.g., 'arm64-v8a')
          // 2. Fallback to 'universal' or any APK if only one is available
          var asset = assets.firstWhere(
            (a) {
              final name = a['name'].toString().toLowerCase();
              return name.endsWith('.apk') && name.contains(deviceAbi.toLowerCase());
            },
            orElse: () => null
          );

          // Second pass: Universal or simple APK
          asset ??= assets.firstWhere(
            (a) {
              final name = a['name'].toString().toLowerCase();
              return name.endsWith('.apk') && (name.contains('universal') || !name.contains('arm'));
            },
            orElse: () => null
          );

          if (asset != null) {
            print("Found matching update: $tagName (${asset['name']})");
            return AppVersion(
              name: tagName,
              apkUrl: asset['browser_download_url'],
              apkSize: asset['size'],
              description: release['body'] ?? "",
            );
          }
        }
      }
      print("No newer version found for ABI: $deviceAbi");
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
