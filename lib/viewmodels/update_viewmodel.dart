import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';
import '../models/app_version.dart';
import '../repositories/update_repository.dart';
import '../services/notification_service.dart';

class UpdateViewModel {
  final _repository = UpdateRepository();
  final _notificationService = NotificationService();

  final _availableUpdate = BehaviorSubject<AppVersion?>();
  final _downloadProgress = BehaviorSubject<double>.seeded(-1.0);
  final _isDownloading = BehaviorSubject<bool>.seeded(false);

  Stream<AppVersion?> get availableUpdate => _availableUpdate.stream;
  Stream<double> get downloadProgress => _downloadProgress.stream;
  Stream<bool> get isDownloading => _isDownloading.stream;

  Future<AppVersion?> checkForUpdate() async {
    final update = await _repository.fetchUpdate();
    if (!_availableUpdate.isClosed) {
      _availableUpdate.add(update);
    }
    return update;
  }

  Future<File?> startDownload(AppVersion version) async {
    if (_isDownloading.isClosed) return null;

    _isDownloading.add(true);
    _downloadProgress.add(0.0);
    await _notificationService.init();

    try {
      final dir = await getTemporaryDirectory();
      final fileName = "update_${version.name}.apk";
      final targetFile = File("${dir.path}/$fileName");

      final file = await _repository.downloadUpdate(
        version,
        targetFile,
        (progress) {
          if (!_downloadProgress.isClosed) {
            _downloadProgress.add(progress);
            _notificationService.showProgress(
              100, 
              (progress * 100).toInt(), 
              100, 
              "Downloading Update", 
              "v${version.name}"
            );
          }
        }
      );

      if (file != null) {
        if (!_isDownloading.isClosed) _isDownloading.add(false);
        if (!_downloadProgress.isClosed) _downloadProgress.add(1.0);
        await _notificationService.showComplete(100, "Download Complete", "Tap to install");
        return file;
      }
    } catch (e) {
      print("Download failed: $e");
      await _notificationService.cancel(100);
    }
    
    if (!_isDownloading.isClosed) _isDownloading.add(false);
    if (!_downloadProgress.isClosed) _downloadProgress.add(-1.0);
    return null;
  }

  void dispose() {
    _availableUpdate.close();
    _downloadProgress.close();
    _isDownloading.close();
  }
}
