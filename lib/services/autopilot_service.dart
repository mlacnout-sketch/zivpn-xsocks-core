import 'dart:async';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shizuku_api/shizuku_api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/autopilot_config.dart';
import '../models/autopilot_state.dart';

class AutoPilotService {
  static final AutoPilotService _instance = AutoPilotService._internal();
  factory AutoPilotService() => _instance;
  AutoPilotService._internal();

  final _shizuku = ShizukuApi();
  final _httpClient = http.Client();
  static const _platform = MethodChannel('com.minizivpn.app/core');
  
  static const _logChannel = EventChannel('com.minizivpn.app/logs');
  StreamSubscription? _logSubscription;
  
  Timer? _timer;
  AutoPilotConfig _config = const AutoPilotConfig();
  
  final _stateController = StreamController<AutoPilotState>.broadcast();
  Stream<AutoPilotState> get stateStream => _stateController.stream;
  
  bool _isResetting = false;

  AutoPilotState _currentState = const AutoPilotState(
    status: AutoPilotStatus.stopped,
    failCount: 0,
    hasInternet: true,
  );

  AutoPilotState get currentState => _currentState;
  AutoPilotConfig get config => _config;
  bool get isRunning => _currentState.status != AutoPilotStatus.stopped;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _config = AutoPilotConfig(
        checkIntervalSeconds: prefs.getInt('ping_interval_ap') ?? 15,
        connectionTimeoutSeconds: prefs.getInt('ping_timeout_ap') ?? 5,
        maxFailCount: prefs.getInt('max_fail_count_ap') ?? 3,
        airplaneModeDelaySeconds: prefs.getInt('airplane_delay_ap') ?? 2,
        recoveryWaitSeconds: prefs.getInt('recovery_wait_ap') ?? 10,
        enableStabilizer: prefs.getBool('enable_stabilizer_ap') ?? false,
        stabilizerSizeMb: prefs.getInt('stabilizer_size_ap') ?? 1,
      );
    } catch (e) {
      _log('Failed to load config: $e');
    }
  }

  Future<void> updateConfig(AutoPilotConfig newConfig) async {
    _config = newConfig;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('ping_interval_ap', newConfig.checkIntervalSeconds);
    await prefs.setInt('ping_timeout_ap', newConfig.connectionTimeoutSeconds);
    await prefs.setInt('max_fail_count_ap', newConfig.maxFailCount);
    await prefs.setInt('airplane_delay_ap', newConfig.airplaneModeDelaySeconds);
    await prefs.setInt('recovery_wait_ap', newConfig.recoveryWaitSeconds);
    await prefs.setBool('enable_stabilizer_ap', newConfig.enableStabilizer);
    await prefs.setInt('stabilizer_size_ap', newConfig.stabilizerSizeMb);
    
    // No restart needed, just config update
  }

  Future<void> _log(String message) async {
    try {
      await _platform.invokeMethod('logMessage', {'message': '[AUTOPILOT] $message'});
    } catch (e) {
      print('AP Log error: $e');
    }
  }

  Future<void> start() async {
    if (isRunning) return;

    try {
      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.monitoring,
        message: 'Initializing Shizuku...', 
      ));

      final isBinderAlive = await _shizuku.pingBinder() ?? false;
      if (!isBinderAlive) throw 'Shizuku service is not running.';

      if (!(await _shizuku.checkPermission() ?? false)) {
        final granted = await _shizuku.requestPermission() ?? false;
        if (!granted) throw 'Shizuku Permission Denied';
      }

      await strengthenBackground();

      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.monitoring,
        failCount: 0,
        message: 'Watchdog active (Listening to Core)',
      ));

      // Listen to Native Logs for [CONNECTION_LOST]
      _logSubscription = _logChannel.receiveBroadcastStream().listen(_onLogReceived);

    } catch (e) {
      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.error,
        message: 'Start failed: $e',
      ));
      rethrow;
    }
  }

  void stop() {
    _logSubscription?.cancel();
    _logSubscription = null;
    _updateState(_currentState.copyWith(
      status: AutoPilotStatus.stopped,
      failCount: 0,
      message: 'Stopped',
    ));
  }

  void _onLogReceived(dynamic event) {
    if (event is String) {
        if (event.contains("[PING] Failed")) {
             // Extract fail count if possible or just increment local visual counter
             final newFail = _currentState.failCount + 1;
             _updateState(_currentState.copyWith(
                failCount: newFail,
                hasInternet: false,
                message: "Ping Failed (Core detected issue)",
                lastCheck: DateTime.now()
             ));
        } else if (event.contains("[PING] http")) {
             _updateState(_currentState.copyWith(
                failCount: 0,
                hasInternet: true,
                message: "Connection Stable",
                lastCheck: DateTime.now()
             ));
        } else if (event.contains("[CONNECTION_LOST]")) {
             if (!_isResetting) {
                 _performReset();
             }
        }
    }
  }

  // Remove old timer-based checkAndRecover logic
  // ... rest of the file ...

  Future<void> strengthenBackground() async {
    try {
      const pkg = 'com.minizivpn.app';
      await _shizuku.runCommand('dumpsys deviceidle whitelist +$pkg');
      await _shizuku.runCommand('cmd activity set-inactive $pkg false');
      await _shizuku.runCommand('cmd activity set-standby-bucket $pkg active');
      await _shizuku.runCommand('pidof $pkg | xargs -n 1 -I {} sh -c "echo -900 > /proc/{}/oom_score_adj"');
    } catch (e) {}
  }

  Future<void> _performReset() async {
    try {
      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.resetting,
        message: 'Resetting network...',
      ));

      // --- HOTSPOT SAFE RESET SEQUENCE ---
      // 1. Blacklist WiFi from Airplane Mode
      await _shizuku.runCommand('settings put global airplane_mode_radios cell,bluetooth,nfc,wimax');
      
      // 2. Airplane Mode ON (via Broadcast to respect blacklist)
      await _shizuku.runCommand('settings put global airplane_mode_on 1');
      await _shizuku.runCommand('am broadcast -a android.intent.action.AIRPLANE_MODE --ez state true');
      
      await Future.delayed(Duration(seconds: _config.airplaneModeDelaySeconds));
      
      // 3. Airplane Mode OFF
      await _shizuku.runCommand('settings put global airplane_mode_on 0');
      await _shizuku.runCommand('am broadcast -a android.intent.action.AIRPLANE_MODE --ez state false');
      
      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.monitoring,
        message: 'Waiting for recovery...',
      ));
      
      await Future.delayed(Duration(seconds: _config.recoveryWaitSeconds));

      if (_config.enableStabilizer) {
        await _runStabilizer();
      }

      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.monitoring,
        failCount: 0,
        message: 'Monitoring resumed',
      ));
    } catch (e) {
      _updateState(_currentState.copyWith(
        status: AutoPilotStatus.error,
        message: 'Reset error: $e',
      ));
    }
  }

  Future<void> _runStabilizer() async {
    _updateState(_currentState.copyWith(
      status: AutoPilotStatus.stabilizing,
      message: 'Stabilizing connection...',
    ));
    
    final client = http.Client();
    try {
      for (int i = 1; i <= _config.stabilizerSizeMb; i++) {
        final request = http.Request('GET', Uri.parse('http://speedtest.tele2.net/1MB.zip'));
        request.headers['Connection'] = 'close';
        final response = await client.send(request).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          await for (var _ in response.stream) {}
        }
      }
    } catch (e) {} finally {
      client.close();
    }
  }

  void _updateState(AutoPilotState newState) {
    _currentState = newState;
    _stateController.add(newState);
  }

  void dispose() {
    _timer?.cancel();
    _stateController.close();
    _httpClient.close();
  }
}
