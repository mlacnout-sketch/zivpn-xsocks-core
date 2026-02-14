import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/app_version.dart';

import 'package:shared_preferences/shared_preferences.dart';

class UpdateRepository {
  final String apiUrl = 'https://api.github.com/repos/mlacnout-sketch/zivpn-xsocks-core/releases';

  Future<List<String>> _getStrategies() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check both potential keys just to be safe (migration consistency)
    final running = (prefs.getBool('vpn_running') ?? false) || (prefs.getBool('flutter.vpn_running') ?? false);

    if (running) {
      // If VPN is on, DIRECT connection will likely fail (no quota) or cause issues.
      // Force SOCKS only.
      return ['SOCKS 127.0.0.1:7777'];
    } else {
      // If VPN is off, try SOCKS (maybe left over?) then DIRECT.
      // Actually if VPN is off, SOCKS won't work. So DIRECT first.
      return ['DIRECT', 'SOCKS 127.0.0.1:7777'];
    }
  }

  Future<AppVersion?> fetchUpdate() async {
    final strategies = await _getStrategies();
    for (final proxy in strategies) {
      try {
        debugPrint('Checking update via: $proxy');
        final responseBody = await _executeCheck(proxy);
        return await _processResponse(responseBody);
      } catch (e) {
        debugPrint('Update check failed via $proxy: $e');
      }
    }
    debugPrint('All update check strategies failed.');
    return null;
  }

  Future<File?> downloadUpdate(AppVersion version, File targetFile,
      void Function(double) onProgress) async {
    final strategies = await _getStrategies();
    for (final proxy in strategies) {
      try {
        debugPrint('Downloading update via: $proxy');
        await _executeDownload(version.apkUrl, targetFile, proxy, onProgress);
        return targetFile;
      } catch (e) {
        debugPrint('Download failed via $proxy: $e');
        if (await targetFile.exists()) {
          try {
            await targetFile.delete();
          } catch (_) {}
        }
      }
    }
    debugPrint('All download strategies failed.');
    return null;
  }

  Future<String> _executeCheck(String proxyConf) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    
    if (proxyConf != 'DIRECT') {
      client.findProxy = (uri) => proxyConf;
    }
    // GitHub API requires User-Agent
    client.userAgent = 'MiniZivpn-Updater';

    try {
      final request = await client.getUrl(Uri.parse(apiUrl));
      final response = await request.close();
      
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }

  Future<void> _executeDownload(String url, File targetFile, String proxyConf,
      void Function(double) onProgress) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30); // Longer timeout for downloads

    if (proxyConf != 'DIRECT') {
      client.findProxy = (uri) => proxyConf;
    }
    client.userAgent = 'MiniZivpn-Updater';

    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final contentLength = response.contentLength;

      if (await targetFile.exists()) {
        await targetFile.delete();
      }

      final sink = targetFile.openWrite();
      int receivedBytes = 0;

      try {
        await for (var chunk in response) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (contentLength > 0) {
            onProgress(receivedBytes / contentLength.toDouble());
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (contentLength > 0 && targetFile.lengthSync() != contentLength) {
          throw Exception('Incomplete download');
      }
    } finally {
      client.close();
    }
  }

  Future<AppVersion?> _processResponse(String jsonStr) async {
    final List<dynamic> releases = json.decode(jsonStr) as List<dynamic>;
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    final currentBuildNumber = packageInfo.buildNumber;

    debugPrint('Current App: $currentVersion ($currentBuildNumber)');

    for (var release in releases) {
      final tagName = release['tag_name'].toString();
      if (_isNewer(tagName, currentVersion, currentBuildNumber)) {
        final assets = release['assets'] as List?;
        if (assets == null) continue;

        final asset = assets.firstWhere(
            (a) =>
                a['content_type'] ==
                    'application/vnd.android.package-archive' ||
                a['name'].toString().endsWith('.apk'),
            orElse: () => null);

        if (asset != null) {
          return AppVersion(
            name: tagName,
            apkUrl: asset['browser_download_url'] as String,
            apkSize: asset['size'] as int,
            description: (release['body'] as String?) ?? '',
          );
        }
      }
    }
    return null;
  }

  bool _isNewer(String latestTag, String currentVersion, String currentBuildNumber) {
    try {
      // Parse Major.Minor.Patch
      final RegExp regVer = RegExp(r'(\d+)\.(\d+)\.(\d+)');
      final match1 = regVer.firstMatch(latestTag);
      final match2 = regVer.firstMatch(currentVersion);

      if (match1 == null || match2 == null) return false;

      final v1 = [
        int.parse(match1.group(1)!),
        int.parse(match1.group(2)!),
        int.parse(match1.group(3)!)
      ];
      
      final v2 = [
        int.parse(match2.group(1)!),
        int.parse(match2.group(2)!),
        int.parse(match2.group(3)!)
      ];

      for (int i = 0; i < 3; i++) {
        if (v1[i] > v2[i]) return true;
        if (v1[i] < v2[i]) return false;
      }
      
      // If versions are equal, check Build Number
      int buildRemote = 0;
      final int buildLocal = int.tryParse(currentBuildNumber) ?? 0;

      // Extract Remote Build Number (-bXX)
      final RegExp regBuildRemote = RegExp(r'-b(\d+)');
      final matchBuildRemote = regBuildRemote.firstMatch(latestTag);
      if (matchBuildRemote != null) {
        buildRemote = int.parse(matchBuildRemote.group(1)!);
      }

      debugPrint(
          'Ver Check: Remote=$v1 ($buildRemote) vs Local=$v2 ($buildLocal)');

      return buildRemote > buildLocal;
    } catch (e) {
      debugPrint('Version check error: $e');
      return false;
    }
  }
}
