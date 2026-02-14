import 'dart:convert';
import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/app_version.dart';

import 'package:shared_preferences/shared_preferences.dart';

class UpdateRepository {
  final String apiUrl = "https://api.github.com/repos/mlacnout-sketch/zivpn-xsocks-core/releases";
  static const String _directStrategy = "DIRECT";
  static const String _socksStrategy = "SOCKS 127.0.0.1:7777";

  static const String _rrEnabledKey = 'update_strategy_round_robin';
  static const String _preferSocksKey = 'update_strategy_prefer_socks';
  static const String _downloadForceSocksKey = 'update_download_force_socks5';
  static const String _allowDirectFallbackKey = 'update_allow_direct_fallback';
  static const String _forceSocksForAllUpdateTrafficKey = 'update_force_socks5_all_traffic';

  int _strategyCursor = 0;

  Future<List<String>> _getStrategies() async {
    final prefs = await SharedPreferences.getInstance();

    // Check both potential keys just to be safe (migration consistency)
    final running = (prefs.getBool('vpn_running') ?? false) || (prefs.getBool('flutter.vpn_running') ?? false);

    if (running) {
      // If VPN is on, DIRECT connection will likely fail (no quota) or cause issues.
      // Force SOCKS only.
      return const [_socksStrategy];
    }

    // Optional hard lock: force all update traffic (check + download) through MiniZIVPN SOCKS5.
    // Default true to avoid accidental DIRECT usage when quota policy disallows it.
    final forceAllUpdateTrafficViaSocks =
        prefs.getBool(_forceSocksForAllUpdateTrafficKey) ?? true;
    if (forceAllUpdateTrafficViaSocks) {
      return const [_socksStrategy];
    }

    // Keep behavior adjustable from prefs without code changes:
    // - update_strategy_prefer_socks=true  => SOCKS first
    // - update_strategy_round_robin=false => keep fixed order
    final preferSocks = prefs.getBool(_preferSocksKey) ?? false;
    final roundRobinEnabled = prefs.getBool(_rrEnabledKey) ?? true;

    final baseStrategies = preferSocks
        ? const [_socksStrategy, _directStrategy]
        : const [_directStrategy, _socksStrategy];

    if (!roundRobinEnabled) {
      return baseStrategies;
    }

    return _roundRobinStrategies(baseStrategies);
  }

  List<String> _roundRobinStrategies(List<String> candidates) {
    final candidateCount = candidates.length;
    if (candidateCount <= 1) {
      return candidates;
    }

    final startIndex = _strategyCursor % candidateCount;
    final rotated = List<String>.filled(candidateCount, '', growable: false);

    for (int i = 0; i < candidateCount; i++) {
      rotated[i] = candidates[(startIndex + i) % candidateCount];
    }

    _strategyCursor = (startIndex + 1) % candidateCount;
    return rotated;
  }

  Future<List<String>> _getDownloadStrategies() async {
    final prefs = await SharedPreferences.getInstance();

    // Default behavior: force update APK download through MiniZIVPN SOCKS5,
    // because DIRECT traffic may not have usable main quota.
    final forceSocks = prefs.getBool(_downloadForceSocksKey) ?? true;
    if (forceSocks) {
      return const [_socksStrategy];
    }

    // Optional fallback for operators who explicitly allow DIRECT as backup.
    final allowDirectFallback = prefs.getBool(_allowDirectFallbackKey) ?? false;
    if (!allowDirectFallback) {
      return const [_socksStrategy];
    }

    return const [_socksStrategy, _directStrategy];
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
    final strategies = await _getDownloadStrategies();
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
    
    if (proxyConf != _directStrategy) {
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

    if (proxyConf != _directStrategy) {
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
      int buildLocal = int.tryParse(currentBuildNumber) ?? 0;

      // Extract Remote Build Number (-bXX)
      final RegExp regBuildRemote = RegExp(r'-b(\d+)');
      final matchBuildRemote = regBuildRemote.firstMatch(latestTag);
      if (matchBuildRemote != null) {
        buildRemote = int.parse(matchBuildRemote.group(1)!);
      }

      print("Ver Check: Remote=$v1 ($buildRemote) vs Local=$v2 ($buildLocal)");

      return buildRemote > buildLocal;
    } catch (e) {
      print("Version check error: $e");
      return false;
    }
  }
}
