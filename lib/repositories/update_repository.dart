import 'dart:convert';
import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/app_version.dart';

class UpdateRepository {
  final String apiUrl = "https://api.github.com/repos/mlacnout-sketch/zivpn-xsocks-core/releases";

  Future<AppVersion?> fetchUpdate() async {
    // Strategy: Try SOCKS5 first (via active VPN tunnel), then DIRECT (handled by OS)
    final strategies = [
      "SOCKS5 127.0.0.1:7777",
      "DIRECT"
    ];

    for (final proxy in strategies) {
      try {
        print("Checking update via: $proxy");
        final responseBody = await _executeRequest(proxy);
        return await _processResponse(responseBody);
      } catch (e) {
        print("Update check failed via $proxy: $e");
      }
    }
    print("All update strategies failed.");
    return null;
  }

  Future<String> _executeRequest(String proxyConf) async {
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

  Future<AppVersion?> _processResponse(String jsonStr) async {
    final packageInfo = await PackageInfo.fromPlatform();
    return findUpdateInJson(jsonStr, packageInfo.version);
  }

  /// Parses the release JSON and finds a valid update newer than [currentVersion].
  AppVersion? findUpdateInJson(String jsonStr, String currentVersion) {
    try {
      final List releases = json.decode(jsonStr);
      // Build number ignored to prevent loop (Local 2 vs Remote CI RunNumber)

      print("Current App: $currentVersion");

      for (var release in releases) {
        final tagName = release['tag_name'].toString();
        if (isNewerVersion(tagName, currentVersion)) {
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
    } catch (e) {
      print("Error parsing update JSON: $e");
    }
    return null;
  }

  /// Compares [latestTag] with [currentVersion] strictly by Semantic Versioning (Major.Minor.Patch).
  /// Returns true if [latestTag] is newer.
  bool isNewerVersion(String latestTag, String currentVersion) {
    try {
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
      
      // Build number comparison removed to strictly follow Semantic Versioning
      // and avoid issues where CI Run Number (Remote) > Pubspec Build Number (Local)
      
      return false;
    } catch (e) {
      return false;
    }
  }
}