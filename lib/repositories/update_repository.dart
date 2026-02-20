import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/app_version.dart';

class UpdateRepository {
  static const _platform = MethodChannel('com.minizivpn.app/core');
  final String apiUrl = "https://api.github.com/repos/mlacnout-sketch/zivpn-xsocks-core/releases";

  Future<AppVersion?> fetchUpdate() async {
    // Strategy 1: Native VPN Binding (Best for bypassing exclusions)
    try {
      print("Checking update via Native VPN Binding...");
      final responseBody = await _platform.invokeMethod('checkUpdateNative', {'url': apiUrl});
      if (responseBody != null && responseBody != "ERR") {
        return await _processResponse(responseBody);
      }
    } catch (e) {
      print("Native update check failed: $e");
    }

    // Strategy 2: HttpClient via SOCKS5 Proxy (Local loopback bypass)
    try {
      print("Checking update via SOCKS5 Fallback (127.0.0.1:7777)...");
      final responseBody = await _fetchWithSocks(apiUrl);
      if (responseBody != null) {
        return await _processResponse(responseBody);
      }
    } catch (e) {
      print("SOCKS5 update check failed: $e");
    }

    // Strategy 3: Direct (Last resort, likely fails if ISP blocks)
    try {
      print("Checking update via DIRECT Fallback...");
      final responseBody = await _fetchDirect(apiUrl);
      if (responseBody != null) {
        return await _processResponse(responseBody);
      }
    } catch (e) {
      print("Direct update check failed: $e");
    }

    return null;
  }

  Future<File?> downloadUpdate(AppVersion version, File targetFile, Function(double) onProgress) async {
    // Strategy 1: Native VPN Binding
    try {
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
      print("Native download failed: $e");
    }

    // Strategy 2: HttpClient via SOCKS5
    try {
      print("Downloading via SOCKS5 Fallback...");
      await _downloadWithSocks(version.apkUrl, targetFile, onProgress);
      return targetFile;
    } catch (e) {
      print("SOCKS5 download failed: $e");
    }

    return null;
  }

  Future<String?> _fetchWithSocks(String url) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    client.findProxy = (uri) => "SOCKS 127.0.0.1:7777";
    client.userAgent = "MiniZivpn-Updater";
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode == 200) {
        return await response.transform(utf8.decoder).join();
      }
    } finally {
      client.close();
    }
    return null;
  }

  Future<String?> _fetchDirect(String url) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    client.userAgent = "MiniZivpn-Updater";
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode == 200) {
        return await response.transform(utf8.decoder).join();
      }
    } finally {
      client.close();
    }
    return null;
  }

  Future<void> _downloadWithSocks(String url, File targetFile, Function(double) onProgress) async {
    final client = HttpClient();
    client.findProxy = (uri) => "SOCKS 127.0.0.1:7777";
    client.userAgent = "MiniZivpn-Updater";
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final contentLength = response.contentLength;
      final sink = targetFile.openWrite();
      int received = 0;
      await for (var chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0) onProgress(received / contentLength);
      }
      await sink.flush();
      await sink.close();
    } finally {
      client.close();
    }
  }

  Future<AppVersion?> _processResponse(String jsonStr) async {
      try {
        // Handle enhanced native response
        var releasesData = json.decode(jsonStr);
        List releases;

        if (releasesData is Map) {
           // Native enriched response
           // deviceAbi logic removed as unused for now
           
           if (releasesData.containsKey('device_abi')) {
              // Logic for future ABI usage
           }
           releases = []; 
        } else if (releasesData is List) {
           releases = releasesData;
        } else {
           return null;
        }

        // Try to detect ABI from platform if native injection didn't work/happen
        // (Since MainActivity logic checks for '{', it won't inject into a List '[')
        // We can pass ABI from native via a separate channel call if strictly needed, 
        // but for now, let's infer from asset names based on standard naming.
        // Actually, we can just fetch all assets and let user pick? 
        // Or better: filter for "v8a" if we are on 64bit, "v7a" if 32bit.
        // Since we can't easily get ABI in pure Dart without plugins, 
        // we'll try to find 'universal' first, then specific if universal missing.
        
        final packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = packageInfo.version;
        
        for (var release in releases) {
          final tagName = release['tag_name'].toString();
          if (_isNewer(tagName, currentVersion)) {
            final assets = release['assets'] as List?;
            if (assets == null) continue;
            
            // Smart Asset Selection Logic
            Map<String, dynamic>? bestAsset;
            
            // 1. Try Universal (Safest)
            bestAsset = assets.firstWhere(
              (a) => a['name'].toString().toLowerCase().contains('universal'),
              orElse: () => null
            );

            // 2. If no universal, try simple .apk
            if (bestAsset == null) {
               bestAsset = assets.firstWhere(
                (a) => a['name'].toString().endsWith('.apk'),
                orElse: () => null
              );
            }

            if (bestAsset != null) {
              return AppVersion(
                name: tagName,
                apkUrl: bestAsset['browser_download_url'],
                apkSize: bestAsset['size'],
                description: release['body'] ?? "",
              );
            }
          }
        }
      } catch (e) { print("Process response error: $e"); }
      return null;
  }

  bool _isNewer(String latestTag, String currentVersion) {
    try {
      final remoteVersion = _extractVersionParts(latestTag);
      final localVersion = _extractVersionParts(currentVersion);
      if (remoteVersion.isEmpty || localVersion.isEmpty) return false;
      return _compareVersionParts(remoteVersion, localVersion) > 0;
    } catch (_) { return false; }
  }

  List<int> _extractVersionParts(String value) {
    final match = RegExp(r'(\d+(?:\.\d+)+)').firstMatch(value);
    if (match == null) return const [];
    return match.group(1)!.split('.').map((p) => int.tryParse(p) ?? 0).toList();
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
