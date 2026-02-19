import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/ping_log_entry.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  static const MethodChannel _platform = MethodChannel('com.minizivpn.app/service');
  
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    const androidChannel = AndroidNotificationChannel(
      'ping_notifications',
      'AutoPilot Status',
      description: 'Notifications for PING and network connectivity status',
      importance: Importance.low,
      enableVibration: false,
      playSound: false,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notifications.initialize(initSettings);
    _isInitialized = true;
  }

  Future<void> showPingNotification(PingLogEntry pingEntry) async {
    if (!_isInitialized) await init();

    if (pingEntry.status == PingStatus.success) {
      final quality = pingEntry.latencyQuality;
      await _showBitmapNotification(
        text: '${pingEntry.latencyMs}',
        title: '🌐 Network ${quality.displayName}',
        body: '${quality.emoji} ${pingEntry.latencyMs} ms',
      );
      return;
    }

    final body = pingEntry.errorMessage?.split('\n').first ?? 'Network error';
    await _showBitmapNotification(
      text: 'ERR',
      title: '⚠️ Connection ${pingEntry.status.displayName}',
      body: body,
    );
  }

  Future<void> showRecoveryNotification(PingLogEntry successEntry, Duration downtime) async {
    if (!_isInitialized) await init();

    final minutesDown = downtime.inSeconds > 60
        ? '${downtime.inMinutes}m'
        : '${downtime.inSeconds}s';

    await _showBitmapNotification(
      text: '${successEntry.latencyMs}',
      title: '✅ Connection Restored',
      body: 'Down for $minutesDown • Now: ${successEntry.latencyMs}ms',
    );
  }

  Future<void> _showBitmapNotification({
    required String text,
    required String title,
    required String body,
  }) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _platform.invokeMethod('updatePingIcon', {
          'text': text,
          'title': title,
          'body': body,
        }).timeout(const Duration(seconds: 2));
        return;
      } catch (e) {
        debugPrint('[NotificationService] Failed to update ping icon: $e');
      }
    }

    // Fallback to standard notification if bitmap fails or non-android
    final notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'ping_notifications',
        'AutoPilot Status',
        channelDescription: 'Network status updates',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        onlyAlertOnce: true,
        showProgress: false,
        enableVibration: false,
        playSound: false,
      ),
    );

    await _notifications.show(1001, title, body, notificationDetails);
  }

  Future<void> showProgress(int id, int progress, int total, String title, String body) async {
    if (!_isInitialized) await init();

    final androidDetails = AndroidNotificationDetails(
      'download_channel',
      'Downloads',
      channelDescription: 'Show download progress',
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: total,
      progress: progress,
      indeterminate: false,
    );

    final details = NotificationDetails(android: androidDetails);
    await _notifications.show(id, title, body, details);
  }

  Future<void> showComplete(int id, String title, String body) async {
    if (!_isInitialized) await init();

    const androidDetails = AndroidNotificationDetails(
      'download_channel',
      'Downloads',
      channelDescription: 'Show download progress',
      importance: Importance.high,
      priority: Priority.high,
      onlyAlertOnce: false,
      showProgress: false,
    );

    final details = NotificationDetails(android: androidDetails);
    await _notifications.show(id, title, body, details);
  }

  Future<void> cancel(int id) async {
    await _notifications.cancel(id);
  }
}
