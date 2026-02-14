import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notifications.initialize(initSettings);
    _isInitialized = true;
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

    const details = NotificationDetails(android: androidDetails);
    await _notifications.show(id, title, body, details);
  }

  Future<void> cancel(int id) async {
    await _notifications.cancel(id);
  }
}
