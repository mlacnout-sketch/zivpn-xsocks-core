import 'dart:convert';
import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/app_version.dart';

import 'package:shared_preferences/shared_preferences.dart';

class UpdateRepository {
  final String apiUrl = "https://api.github.com/repos/mlacnout-sketch/zivpn-xsocks-core/releases";

  Future<List<String>> _getStrategies() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check both potential keys just to be safe (migration consistency)
    final running = (prefs.getBool('vpn_running') ?? false) || (prefs.getBool('flutter.vpn_running') ?? false);

    if (running) {
      // If VPN is on, DIRECT connection will likely fail (no quota) or cause issues.
      // Force SOCKS only.
      return ["SOCKS 127.0.0.1:7777"];
    } else {
      // If VPN is off, try SOCKS (maybe left over?) then DIRECT.
      // Actually if VPN is off, SOCKS won't work. So DIRECT first.
      return ["DIRECT", "SOCKS 127.0.0.1:7777"];
    }
  }

  Future<AppVersion?> fetchUpdate() async {
    final strategies = await _getStrategies();
    for (final proxy in strategies) {
      try {
        print("Checking update via: $proxy");
        final responseBody = await _executeCheck(proxy);
        return await _processResponse(responseBody);
      } catch (e) {
        print("Update check failed via $proxy: $e");
      }
    }
    print("All update check strategies failed.");
    return null;
  }

  Future<File?> downloadUpdate(AppVersion version, File targetFile, Function(double) onProgress) async {
    final strategies = await _getStrategies();
    for (final proxy in strategies) {
      try {
        print("Downloading update via: $proxy");
        await _executeDownload(version.apkUrl, targetFile, proxy, onProgress);
        return targetFile;
      } catch (e) {
        print("Download failed via $proxy: $e");
        if (await targetFile.exists()) {
          try {
             await targetFile.delete();
          } catch (_) {}
        }
      }
    }
    print("All download strategies failed.");
    return null;
  }

  Future<String> _executeCheck(String proxyConf) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    
    if (proxyConf != "DIRECT") {
      client.findProxy = (uri) => proxyConf;
    }
    // GitHub API requires User-Agent
    client.userAgent = "MiniZivpn-Updater"; 

    try {
      final request = await client.getUrl(Uri.parse(apiUrl));
      final response = await request.close();
      
      if (response.statusCode != 200) {
        throw Exception("HTTP ${response.statusCode}");
      }
      
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }

  Future<void> _executeDownload(String url, File targetFile, String proxyConf, Function(double) onProgress) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30); // Longer timeout for downloads

    if (proxyConf != "DIRECT") {
      client.findProxy = (uri) => proxyConf;
    }
    client.userAgent = "MiniZivpn-Updater";

    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception("HTTP ${response.statusCode}");
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
          throw Exception("Incomplete download");
      }
    } finally {
      client.close();
    }
  }

  Future<AppVersion?> _processResponse(String jsonStr) async {
      final List releases = json.decode(jsonStr);
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuildNumber = packageInfo.buildNumber;
      
      print("Current App: $currentVersion ($currentBuildNumber)");
      
      for (var release in releases) {
        final tagName = release['tag_name'].toString();
        if (_isNewer(tagName, currentVersion, currentBuildNumber)) {
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

  bool _isNewer(String latestTag, String currentVersion, String currentBuildNumber) {
    try {
      final remoteVersion = _extractVersionParts(latestTag);
      final localVersion = _extractVersionParts(currentVersion);

      if (remoteVersion.isEmpty || localVersion.isEmpty) {
        return false;
      }

      final compare = _compareVersionParts(remoteVersion, localVersion);
      if (compare != 0) {
        print("Ver Check: Remote=$remoteVersion vs Local=$localVersion => compare=$compare");
        return compare > 0;
      }

      final buildRemote = _extractBuildNumber(latestTag);
      final buildLocal = int.tryParse(currentBuildNumber) ?? _extractBuildNumber(currentVersion);

      print("Ver Check: Remote=$remoteVersion ($buildRemote) vs Local=$localVersion ($buildLocal)");
      return buildRemote > buildLocal;
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

  int _extractBuildNumber(String value) {
    final dashBuild = RegExp(r'-b(\d+)', caseSensitive: false).firstMatch(value);
    if (dashBuild != null) {
      return int.tryParse(dashBuild.group(1)!) ?? 0;
    }

    final plusBuild = RegExp(r'\+(\d+)').firstMatch(value);
    if (plusBuild != null) {
      return int.tryParse(plusBuild.group(1)!) ?? 0;
    }

    return 0;
  }
}
