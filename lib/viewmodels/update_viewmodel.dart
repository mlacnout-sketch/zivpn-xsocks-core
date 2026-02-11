import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';
import '../models/app_version.dart';
import '../repositories/update_repository.dart';

class UpdateViewModel {
  final UpdateRepository _repository;

  UpdateViewModel({UpdateRepository? repository})
      : _repository = repository ?? UpdateRepository();

  final _availableUpdate = BehaviorSubject<AppVersion?>();
  final _downloadProgress = BehaviorSubject<double>.seeded(-1.0);
  final _isDownloading = BehaviorSubject<bool>.seeded(false);

  Stream<AppVersion?> get availableUpdate => _availableUpdate.stream;
  Stream<double> get downloadProgress => _downloadProgress.stream;
  Stream<bool> get isDownloading => _isDownloading.stream;

  Future<bool> checkForUpdate() async {
    final update = await _repository.fetchUpdate();
    _availableUpdate.add(update);
    return update != null;
  }

  Future<File?> startDownload(AppVersion version) async {
    _isDownloading.add(true);
    _downloadProgress.add(0.0);

    // Strategy: Try HTTP Proxy First (Best for Flutter), then Direct
    // Note: SOCKS5 is not supported by Dart's HttpClient findProxy
    final strategies = [
      "PROXY 127.0.0.1:7778",  // Priority 1: New HTTP Proxy (Go)
      "DIRECT"                 // Priority 2: Fallback
    ];

    for (final proxy in strategies) {
      if (_isDownloading.isClosed) return null;
      print("Attempting download via: $proxy");
      try {
        final file = await _executeDownload(version, proxy);
        if (file != null) {
          if (!_isDownloading.isClosed) _isDownloading.add(false);
          if (!_downloadProgress.isClosed) _downloadProgress.add(1.0);
          return file;
        }
      } catch (e) {
        print("Download failed via $proxy: $e");
      }
    }
    
    if (!_isDownloading.isClosed) _isDownloading.add(false);
    if (!_downloadProgress.isClosed) _downloadProgress.add(-1.0);
    return null;
  }

  Future<File?> _executeDownload(AppVersion version, String proxyConf) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    
    // Force Proxy Config
    if (proxyConf != "DIRECT") {
      client.findProxy = (uri) => proxyConf;
    }

    try {
      final request = await client.getUrl(Uri.parse(version.apkUrl));
      final response = await request.close();
      
      if (response.statusCode != 200) {
        throw Exception("HTTP ${response.statusCode}");
      }

      final contentLength = response.contentLength;
      final dir = await getTemporaryDirectory();
      final fileName = "update_${version.name}.apk";
      final file = File("${dir.path}/$fileName");
      
      if (await file.exists()) {
        await file.delete();
      }
      
      final sink = file.openWrite();
      int receivedBytes = 0;

      await for (var chunk in response) {
        if (_downloadProgress.isClosed) {
           await sink.close(); 
           return null; // Stop if disposed
        }
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (contentLength > 0 && !_downloadProgress.isClosed) {
          _downloadProgress.add(receivedBytes / contentLength.toDouble());
        }
      }
      await sink.flush();
      await sink.close();
      
      if (contentLength > 0 && file.lengthSync() != contentLength) {
          throw Exception("Incomplete download");
      }
      return file;
    } finally {
      client.close();
    }
  }

  void dispose() {
    _availableUpdate.close();
    _downloadProgress.close();
    _isDownloading.close();
  }
}