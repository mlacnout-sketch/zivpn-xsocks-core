import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shizuku_api/shizuku_api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import '../models/ping_log_entry.dart';
import '../models/autopilot_config.dart';
import '../models/autopilot_state.dart';
import 'notification_service.dart';

const String kAppPackageName = 'com.minizivpn.app';

class AutoPilotService extends ChangeNotifier {
  static const List<List<String>> _airplaneModeMethods = [
    ['cmd connectivity airplane-mode {action}'],
    [
      'settings put global airplane_mode_on {stateValue}',
      'am broadcast -a android.intent.action.AIRPLANE_MODE --ez state {stateBool}',
    ],
    ['svc data {svcAction}'],
  ];
  static const List<String> _stabilizerUrls = [
    'https://speed.cloudflare.com/__down?bytes=1048576',
    'https://proof.ovh.net/files/1Mb.dat',
    'https://speedtest.selectel.ru/1MB',
  ];
  static const Duration _stabilizerChunkTimeout = Duration(seconds: 20);
  static const int _maxStabilizerSizeMb = 10;
  static const Duration _shizukuCommandTimeout = Duration(seconds: 4);
  static const int _watchdogPriorityRefreshInterval = 5;

  static final AutoPilotService _instance = AutoPilotService._internal();

  factory AutoPilotService() {
    return _instance;
  }

  AutoPilotService._internal();

  static String _normalizePingDestination(String? destination) {
    final trimmed = destination?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'http://connectivitycheck.gstatic.com/generate_204';
    }

    final parsed = Uri.tryParse(trimmed);
    if (parsed == null) {
      return 'http://connectivitycheck.gstatic.com/generate_204';
    }

    if (parsed.hasScheme) {
      if ((parsed.scheme == 'http' || parsed.scheme == 'https') &&
          parsed.host.isNotEmpty) {
        return parsed.toString();
      }
      return 'http://connectivitycheck.gstatic.com/generate_204';
    }

    final withHttps = Uri.tryParse('https://$trimmed');
    if (withHttps == null || withHttps.host.isEmpty) {
      return 'http://connectivitycheck.gstatic.com/generate_204';
    }
    return withHttps.toString();
  }

  late MethodChannel _methodChannel;
  final ShizukuApi _shizuku = ShizukuApi();
  final StreamController<AutoPilotState> _stateController = StreamController<AutoPilotState>.broadcast();
  
  AutoPilotConfig _config = const AutoPilotConfig();
  AutoPilotState _currentState = const AutoPilotState();
  
  Timer? _timer;
  int _consecutiveResets = 0;
  int _watchdogRefreshCounter = 0;

  bool _isInitialized = false;
  bool _isInitializing = false;
  bool isRunning = false;

  final List<PingLogEntry> _pingLogs = [];
  final NotificationService _notificationService = NotificationService();
  DateTime? _lastFailureTime;

  Stream<AutoPilotState> get stateStream => _stateController.stream;
  AutoPilotConfig get config => _config;
  AutoPilotState get currentState => _currentState;

  Future<void> init() async {
    if (_isInitialized) return;
    if (_isInitializing) {
      while (_isInitializing) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return;
    }

    _isInitializing = true;
    try {
      _methodChannel = const MethodChannel('com.minizivpn.app/core');
      
      await _loadConfig();
      await _notificationService.init();
      
      _isInitialized = true;
      debugPrint('[AutoPilotService] Initialization complete');
    } catch (e) {
      debugPrint('[AutoPilotService] Initialization failed: $e');
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  void dispose() {
    stop();
    _stateController.close();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _config = AutoPilotConfig(
        checkIntervalSeconds: prefs.getInt('checkIntervalSeconds') ?? 15,
        connectionTimeoutSeconds: prefs.getInt('connectionTimeoutSeconds') ?? 5,
        maxFailCount: prefs.getInt('maxFailCount') ?? 3,
        airplaneModeDelaySeconds: prefs.getInt('airplaneModeDelaySeconds') ?? 3,
        recoveryWaitSeconds: prefs.getInt('recoveryWaitSeconds') ?? 10,
        autoHealthCheck: prefs.getBool('autoHealthCheck') ?? false,
        enablePingStabilizer: prefs.getBool('enablePingStabilizer') ?? false,
        stabilizerSizeMb: (prefs.getInt('stabilizerSizeMb') ?? 1).clamp(1, _maxStabilizerSizeMb),
        maxConsecutiveResets: prefs.getInt('maxConsecutiveResets') ?? 5,
        pingDestination: _normalizePingDestination(
          prefs.getString('pingDestination'),
        ),
      );
    } catch (e) {
      _config = const AutoPilotConfig();
    }
  }

  Future<void> updateConfig(AutoPilotConfig newConfig) async {
    final wasRunning = isRunning;
    if (wasRunning) stop();
    
    _config = newConfig;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('checkIntervalSeconds', _config.checkIntervalSeconds);
    await prefs.setInt('connectionTimeoutSeconds', _config.connectionTimeoutSeconds);
    await prefs.setInt('maxFailCount', _config.maxFailCount);
    await prefs.setInt('airplaneModeDelaySeconds', _config.airplaneModeDelaySeconds);
    await prefs.setInt('recoveryWaitSeconds', _config.recoveryWaitSeconds);
    await prefs.setBool('autoHealthCheck', _config.autoHealthCheck);
    await prefs.setBool('enablePingStabilizer', _config.enablePingStabilizer);
    await prefs.setInt('stabilizerSizeMb', _config.stabilizerSizeMb);
    await prefs.setInt('maxConsecutiveResets', _config.maxConsecutiveResets);
    await prefs.setString('pingDestination', _config.pingDestination);
    
    if (wasRunning) start();
    notifyListeners();
  }

  Future<void> start() async {
    if (isRunning) return;

    try {
      final isBinderAlive = await _shizuku.pingBinder() ?? false;
      if (!isBinderAlive) throw 'Shizuku service is not running.';

      if (!(await _shizuku.checkPermission() ?? false)) {
        final granted = await _shizuku.requestPermission() ?? false;
        if (!granted) throw 'Shizuku Permission Denied';
      }

      await _applyShizukuWatchdogPriority();

      isRunning = true;
      _timer = Timer.periodic(
        Duration(seconds: _config.checkIntervalSeconds),
        (timer) async => await _checkAndRecover(),
      );

      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.running,
        failCount: 0,
        message: 'Lexpesawat siap di latar belakang',
      ));
      
      notifyListeners();
    } catch (e) {
      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.error,
        message: 'Failed to start: $e',
      ));
      rethrow;
    }
  }

  void stop() {
    if (!isRunning) return;
    _timer?.cancel();
    isRunning = false;
    _watchdogRefreshCounter = 0;

    _updateState(_currentState.copyWith(
      status: AutoPilotStatus.idle,
      message: 'Stopped',
    ));
    notifyListeners();
  }

  Future<void> _checkAndRecover() async {
    try {
      await _refreshShizukuWatchdogPriorityIfNeeded();

      final hasInternet = await _hasInternetConnection();
      final lastCheck = DateTime.now();

      if (!hasInternet) {
        final newFailCount = _currentState.failCount + 1;
        _updateState(_currentState.copyWith(
          failCount: newFailCount,
          lastCheck: lastCheck,
          hasInternet: false,
          message: 'No internet detected (Attempt $newFailCount/${_config.maxFailCount})',
        ));

        if (newFailCount >= _config.maxFailCount) {
          await _performRecovery();
        }
      } else {
        _consecutiveResets = 0;
        _updateState(_currentState.copyWith(
          failCount: 0,
          lastCheck: lastCheck,
          hasInternet: true,
          message: 'Internet stable',
        ));
      }
    } catch (e) {
      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.error,
        message: 'Check error: $e',
      ));
    }
  }

  Future<void> _refreshShizukuWatchdogPriorityIfNeeded() async {
    _watchdogRefreshCounter++;
    if (_watchdogRefreshCounter % _watchdogPriorityRefreshInterval == 0) {
      await _applyShizukuWatchdogPriority();
    }
  }

  Future<void> _applyShizukuWatchdogPriority() async {
    const pkg = kAppPackageName;
    final commands = [
      'dumpsys deviceidle whitelist +$pkg',
      'cmd appops set $pkg RUN_IN_BACKGROUND allow',
      'cmd appops set $pkg RUN_ANY_IN_BACKGROUND allow',
      'cmd activity set-inactive $pkg false',
      'cmd activity set-standby-bucket $pkg active',
      'pidof $pkg | xargs -r -n 1 -I {} sh -c "renice -n -10 -p {} || true"',
      'pidof $pkg | xargs -r -n 1 -I {} sh -c "echo -900 > /proc/{}/oom_score_adj || true"',
    ];

    for (final command in commands) {
      await _runShizukuCommandSafe(command);
    }
  }

  Future<void> _runShizukuCommandSafe(String command) async {
    try {
      await _shizuku.runCommand(command).timeout(_shizukuCommandTimeout);
    } catch (e) {
      debugPrint('[AutoPilotService] Shizuku command failed: $command');
    }
  }

  Future<bool> _hasInternetConnection() async {
    try {
      final startTime = DateTime.now();
      final response = await http
          .get(Uri.parse(_config.pingDestination))
          .timeout(Duration(seconds: _config.connectionTimeoutSeconds));
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      
      final isConnected = response.statusCode == 204 || response.statusCode == 200;
      
      final pingEntry = PingLogEntry(
        timestamp: startTime,
        status: PingStatus.success,
        latencyMs: elapsed,
        statusCode: response.statusCode,
        destination: _config.pingDestination,
      );
      
      _addPingLog(pingEntry);
      _logToNative("PING ${response.statusCode} (${elapsed}ms)");
      await _notificationService.showPingNotification(pingEntry);
      
      if (_lastFailureTime != null) {
        await _notificationService.showRecoveryNotification(pingEntry, DateTime.now().difference(_lastFailureTime!));
        _lastFailureTime = null;
      }
      
      return isConnected;
    } catch (e) {
      final pingEntry = PingLogEntry(
        timestamp: DateTime.now(),
        status: e.toString().contains('TimeoutException') ? PingStatus.timeout : PingStatus.failed,
        destination: _config.pingDestination,
        errorMessage: e.toString(),
      );
      
      _addPingLog(pingEntry);
      _logToNative("PING FAILED: ${e.toString().split('\n').first}");
      await _notificationService.showPingNotification(pingEntry);
      _lastFailureTime ??= DateTime.now();
      
      return false;
    }
  }

  Future<void> _performRecovery() async {
    if (_consecutiveResets >= _config.maxConsecutiveResets) {
      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.error,
        message: 'Max resets exceeded (${_config.maxConsecutiveResets})',
      ));
      return;
    }

    _consecutiveResets++;
    
    // Exponential backoff with jitter
    // 2^reset * 1000ms + random(500ms)
    final backoffMs = (math.pow(2, _consecutiveResets) * 1000).toInt() + 
                     (math.Random().nextInt(1000) - 500);
    final delay = Duration(milliseconds: backoffMs.clamp(1000, 30000));

    _updateState(_currentState.copyWith(
      status: AutoPilotStatus.recovering,
      message: 'Backoff for ${delay.inSeconds}s before reset #$_consecutiveResets...',
    ));
    
    await Future.delayed(delay);

    _updateState(_currentState.copyWith(
      status: AutoPilotStatus.recovering,
      message: 'Attempting recovery (Reset #$_consecutiveResets)...',
    ));

    try {
      await _toggleAirplaneMode(true);
      await Future.delayed(Duration(seconds: _config.airplaneModeDelaySeconds));
      await _toggleAirplaneMode(false);
      await Future.delayed(Duration(seconds: _config.recoveryWaitSeconds));

      final recovered = await _hasInternetConnection();
      if (recovered && _config.enablePingStabilizer) {
        await _runPingStabilizer();
      }

      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.running,
        failCount: recovered ? 0 : _currentState.failCount,
        hasInternet: recovered,
        message: recovered ? 'Recovery successful' : 'Recovery completed, but internet unstable',
      ));
    } catch (e) {
      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.error,
        message: 'Recovery failed: $e',
      ));
    }
  }

  Future<void> _runPingStabilizer() async {
    final ioc = HttpClient();
    ioc.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    final client = IOClient(ioc);
    
    try {
      final totalChunks = _config.stabilizerSizeMb.clamp(1, _maxStabilizerSizeMb);
      for (int i = 0; i < totalChunks; i++) {
        if (!isRunning) break;
        try {
          // Cycle through available URLs
          final baseUrl = _stabilizerUrls[i % _stabilizerUrls.length];
          // Append cache-busting timestamp
          final separator = baseUrl.contains('?') ? '&' : '?';
          final url = '$baseUrl${separator}t=${DateTime.now().millisecondsSinceEpoch}';
          
          final request = http.Request('GET', Uri.parse(url));
          final response = await client.send(request).timeout(_stabilizerChunkTimeout);
          
          // Consume the stream to ensure download happens
          await for (final _ in response.stream) {
            if (!isRunning) break;
          }
          _logToNative("Stabilizer chunk ${i + 1}/$totalChunks downloaded from ${Uri.parse(baseUrl).host}");
        } catch (e) {
           _logToNative("Stabilizer chunk ${i + 1} error: $e");
        }
      }
    } finally {
      client.close();
    }
  }

  Future<void> _toggleAirplaneMode(bool enabled) async {
    final action = enabled ? 'enable' : 'disable';
    final stateValue = enabled ? 1 : 0;
    final stateBool = enabled.toString();
    final svcAction = enabled ? 'disable' : 'enable';

    // Preserve Hotspot: Exclude 'wifi' and 'bluetooth' from airplane mode radios
    const preserveHotspotCommand = 'settings put global airplane_mode_radios cell,nfc,wimax';

    if (enabled) {
      try {
        await _shizuku.runCommand(preserveHotspotCommand).timeout(_shizukuCommandTimeout);
      } catch (_) {}
    }

    Object? lastError;

    for (final method in _airplaneModeMethods) {
      try {
        for (final template in method) {
          final command = template
              .replaceAll('{action}', action)
              .replaceAll('{stateValue}', stateValue.toString())
              .replaceAll('{stateBool}', stateBool)
              .replaceAll('{svcAction}', svcAction);
          
          await _shizuku.runCommand(command).timeout(_shizukuCommandTimeout);
        }
        return; // Success
      } catch (e) {
        lastError = e;
        await Future.delayed(const Duration(seconds: 1));
        continue; // Try next method
      }
    }
    
    throw 'Unable to toggle airplane mode: $lastError';
  }

  Future<void> _logToNative(String message) async {
    try {
      if (_isInitialized) {
        await _methodChannel.invokeMethod('logMessage', {'message': "[AutoPilot] $message"});
      }
    } catch (e) {
      debugPrint("Failed to log to native: $e");
    }
  }

  /// Re-probe network quality and return new config if change is significant (hysteresis)
  Future<Map<String, dynamic>?> reProbeNetwork() async {
    try {
      final Map<dynamic, dynamic>? smartConfig = 
          await _methodChannel.invokeMethod('getSmartNetworkConfig');
      
      if (smartConfig == null) return null;
      
      final int newScore = smartConfig['score'] ?? 0;
      final int oldScore = _currentState.networkScore ?? 0;
      
      // Hysteresis: Only update if score changed by more than 5 points (roughly ±2 dB equivalent)
      if ((newScore - oldScore).abs() > 5) {
        _updateState(_currentState.copyWith(
          networkScore: newScore,
          message: 'Network quality changed (Score: $newScore). Re-tuning needed.',
        ));
        
        return Map<String, dynamic>.from(smartConfig);
      } else {
        debugPrint('[AutoPilotService] Hysteresis: Score change ($oldScore -> $newScore) too small, skipping re-tune.');
        return null;
      }
    } catch (e) {
      debugPrint('[AutoPilotService] Re-probe failed: $e');
      return null;
    }
  }

  void _updateState(AutoPilotState newState) {
    if (newState.message != null && newState.message != _currentState.message) {
        _logToNative(newState.message!);
    }
    _currentState = newState;
    _stateController.add(newState);
    notifyListeners();
  }

  void _addPingLog(PingLogEntry entry) {
    _pingLogs.insert(0, entry);
    if (_pingLogs.length > 100) _pingLogs.removeLast();
  }

  List<PingLogEntry> getRecentPingLogs({int limit = 10}) => _pingLogs.take(limit).toList();
}
