import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_filex/open_filex.dart';

import '../app_colors.dart';
import 'tabs/dashboard_tab.dart';
import 'tabs/proxies_tab.dart';
import 'tabs/logs_tab.dart';
import 'tabs/autopilot_tab.dart';
import 'tabs/settings_tab.dart';
import '../viewmodels/update_viewmodel.dart';
import '../repositories/backup_repository.dart';
import '../services/autopilot_service.dart';
import '../models/autopilot_state.dart';
import '../models/app_version.dart';
import '../models/account.dart';
import '../widgets/donation_widgets.dart';
import '../utils/format_utils.dart';
import '../services/notification_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  final _updateViewModel = UpdateViewModel();

  static const platform = MethodChannel('com.minizivpn.app/core');
  static const logChannel = EventChannel('com.minizivpn.app/logs');
  static const statsChannel = EventChannel('com.minizivpn.app/stats');

  String _vpnState = "disconnected"; // disconnected, connecting, connected
  final List<String> _logs = [];
  final List<String> _logBuffer = [];
  Timer? _logFlushTimer;
  final ScrollController _logScrollCtrl = ScrollController();
  
  List<Account> _accounts = [];
  int _activeAccountIndex = -1;
  
  Timer? _timer;
  DateTime? _startTime;
  final ValueNotifier<String> _durationNotifier = ValueNotifier("00:00:00");
  
  final ValueNotifier<String> _dlSpeed = ValueNotifier("0 KB/s");
  final ValueNotifier<String> _ulSpeed = ValueNotifier("0 KB/s");
  final ValueNotifier<int> _sessionRx = ValueNotifier(0);
  final ValueNotifier<int> _sessionTx = ValueNotifier(0);
  
  // AutoPilot Service
  final _autoPilot = AutoPilotService();
  bool _autoPilotActive = false;
  bool _autoPilotResetting = false;

  @override
  void initState() {
    super.initState();
    NotificationService().init(onTap: (payload) {
      if (payload != null && payload.endsWith('.apk')) {
        OpenFilex.open(payload, type: "application/vnd.android.package-archive");
      }
    });
    _loadData();
    _initLogListener();
    _initStatsListener();
    _initAutoPilotListener();
    _checkInitialImport();
    
    _updateViewModel.availableUpdate.listen((update) {
      if (update != null && mounted) _showUpdateDialog(update);
    });
    _updateViewModel.checkForUpdate();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _logFlushTimer?.cancel();
    _updateViewModel.dispose();
    _dlSpeed.dispose();
    _ulSpeed.dispose();
    _sessionRx.dispose();
    _sessionTx.dispose();
    _durationNotifier.dispose();
    _logScrollCtrl.dispose();
    super.dispose();
  }

  void _initAutoPilotListener() {
    _autoPilot.stateStream.listen((state) {
      if (mounted) {
        // Detect recovery (Transition from Resetting/Stabilizing -> Monitoring)
        if (_autoPilotResetting && state.status == AutoPilotStatus.monitoring) {
             // Connection recovered by AutoPilot!
             // We should restart VPN to apply new Smart Network Config
             if (_vpnState == "connected") {
                 _logs.add("[AUTOPILOT] Signal recovered. Restarting VPN to re-tune...");
                 // Small delay to ensure network is stable
                 Future.delayed(const Duration(seconds: 2), () async {
                     if (mounted && _vpnState == "connected") {
                         await _toggleVpn(isSystemRequest: true); // Stop
                         await Future.delayed(const Duration(seconds: 1));
                         await _toggleVpn(isSystemRequest: true); // Start (Will trigger Smart Probe)
                     }
                 });
             }
        }

        setState(() {
          _autoPilotActive = state.status != AutoPilotStatus.stopped && 
                            state.status != AutoPilotStatus.idle;
          _autoPilotResetting = state.status == AutoPilotStatus.resetting || 
                               state.status == AutoPilotStatus.stabilizing;
          
          if (state.message != null && !state.message!.contains("Monitoring")) {
             if (!_logs.contains("[AUTOPILOT] ${state.message}")) {
                _logs.add("[AUTOPILOT] ${state.message}");
             }
          }
        });
      }
    });
  }

  Future<void> _checkInitialImport() async {
    try {
      final String? filePath = await platform.invokeMethod('getInitialFile');
      if (filePath != null && mounted) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.card,
            title: const Text("Import Backup?"),
            content: const Text("A backup file was detected. Do you want to restore it now?"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: () => Navigator.pop(context, true), 
                child: const Text("Import")
              ),
            ],
          ),
        );

        if (confirmed == true) {
            final success = await BackupRepository().restoreBackup(File(filePath));
            if (success) _loadData();
        }
      }
    } catch (e) {}
  }

  void _showUpdateDialog(AppVersion update) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text("Update Available: v${update.name}"),
        content: SingleChildScrollView(child: Text(update.description)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Later")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              Navigator.pop(context);
              _executeDownload(update);
            },
            child: const Text("Update Now"),
          ),
        ],
      ),
    );
  }

  void _executeDownload(AppVersion update) async {
    // Tampilkan dialog progress
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DownloadProgressDialog(
        progress: _updateViewModel.downloadProgress,
        abi: update.abi ?? "Universal",
        onStop: () {
          Navigator.pop(context);
          _updateViewModel.stopDownload();
        },
      ),
    );

    final file = await _updateViewModel.startDownload(update);
    
    if (mounted) Navigator.pop(context); // Tutup dialog progress

    if (file != null) {
      final result = await OpenFilex.open(file.path, type: "application/vnd.android.package-archive");
      if (result.type != ResultType.done) {
        debugPrint("Failed to open APK: ${result.message}");
      }
    }
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Set Defaults
    if (!prefs.containsKey('mtu')) await prefs.setInt('mtu', 1500);
    if (!prefs.containsKey('ping_interval')) await prefs.setInt('ping_interval', 3);
    
    final String? jsonStr = prefs.getString('saved_accounts');
    if (jsonStr != null) {
      final List<dynamic> jsonData = jsonDecode(jsonStr);
      _accounts = jsonData.map((acc) => Account.fromJson(acc)).toList();
    }
    
    final isRunning = prefs.getBool('vpn_running') ?? false;
    final startMillis = prefs.getInt('vpn_start_time');
    final currentIp = prefs.getString('ip') ?? "";
    final savedIndex = prefs.getInt('active_account_index') ?? -1;
    
    if (savedIndex >= 0 && savedIndex < _accounts.length) {
      _activeAccountIndex = savedIndex;
    } else if (currentIp.isNotEmpty) {
      _activeAccountIndex = _accounts.indexWhere((acc) => acc.ip == currentIp);
    }
    
    setState(() {
      _vpnState = isRunning ? "connected" : "disconnected";
      if (isRunning && startMillis != null) {
        _startTime = DateTime.fromMillisecondsSinceEpoch(startMillis);
        _startTimer();
      }
    });

    await _autoPilot.init();
    if (isRunning && _autoPilot.config.autoReset) {
      _autoPilot.start();
    }
  }

  Future<void> _saveAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_accounts', jsonEncode(_accounts.map((acc) => acc.toJson()).toList()));
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_startTime == null) return;
      final diff = DateTime.now().difference(_startTime!);
      String twoDigits(int n) => n.toString().padLeft(2, "0");
      _durationNotifier.value =
            "${twoDigits(diff.inHours)}:${twoDigits(diff.inMinutes.remainder(60))}:${twoDigits(diff.inSeconds.remainder(60))}";
    });
  }

  void _initLogListener() {
    logChannel.receiveBroadcastStream().listen((event) {
      if (event is String && mounted) {
        _logBuffer.add(event);
        if (_logFlushTimer == null || !_logFlushTimer!.isActive) {
          _logFlushTimer = Timer(const Duration(milliseconds: 200), _flushLogs);
        }
      }
    });
  }

  void _flushLogs() {
    if (!mounted || _logBuffer.isEmpty) return;
    setState(() {
      _logs.addAll(_logBuffer);
      _logBuffer.clear();
      if (_logs.length > 1000) _logs.removeRange(0, _logs.length - 1000);
    });
    if (_selectedIndex == 2 && _logScrollCtrl.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logScrollCtrl.hasClients) _logScrollCtrl.jumpTo(_logScrollCtrl.position.maxScrollExtent);
      });
    }
  }

  void _initStatsListener() {
    statsChannel.receiveBroadcastStream().listen((event) {
      if (event is String && mounted) {
        if (event.startsWith("PROGRESS|")) {
           final pStr = event.split('|')[1];
           final pVal = double.tryParse(pStr) ?? 0.0;
           _updateViewModel.updateManualProgress(pVal);
           return;
        }

        final parts = event.split('|');
        if (parts.length >= 2) {
          final rx = int.tryParse(parts[0]) ?? 0;
          final tx = int.tryParse(parts[1]) ?? 0;
          _dlSpeed.value = FormatUtils.formatBytes(rx, asSpeed: true);
          _ulSpeed.value = FormatUtils.formatBytes(tx, asSpeed: true);
          
          if (parts.length == 4) {
             // New accurate total from Android
             _sessionRx.value = int.tryParse(parts[2]) ?? 0;
             _sessionTx.value = int.tryParse(parts[3]) ?? 0;
          } else {
             // Fallback to legacy accumulation
             _sessionRx.value += rx;
             _sessionTx.value += tx;
          }

          if (_activeAccountIndex != -1) {
             // For account usage, we still accumulate deltas to avoid losing data across sessions
             _accounts[_activeAccountIndex].usage += rx + tx;
          }
        }
      }
    });
  }

  Future<void> _toggleVpn({bool isSystemRequest = false}) async {
    HapticFeedback.mediumImpact();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    if (_vpnState == "connected") {
      void performStop() async {
        try {
          await platform.invokeMethod('stopCore');
          _autoPilot.stop();
          _timer?.cancel();
          setState(() {
            _vpnState = "disconnected";
            _startTime = null;
          });
          _durationNotifier.value = "00:00:00";
          _sessionRx.value = 0; _sessionTx.value = 0;
          _dlSpeed.value = "0 KB/s"; _ulSpeed.value = "0 KB/s";
          await prefs.remove('vpn_start_time');
          await _saveAccounts();
        } catch (e) {
          _logs.add("Error stopping: $e");
        }
      }

      if (!isSystemRequest && mounted) {
        bool shown = showSarcasticDialog(context, onProceed: performStop);
        if (!shown) performStop();
      } else {
        performStop();
      }

    } else {
      final ip = prefs.getString('ip') ?? "";
      if (ip.isEmpty) { setState(() => _selectedIndex = 4); return; }

      setState(() => _vpnState = "connecting");

      try {
        String recvWin = prefs.getString('hysteria_recv_window') ?? "327680";
        String recvConn = prefs.getString('hysteria_recv_conn') ?? "131072";
        final profile = prefs.getString('native_perf_profile') ?? "balanced";

        if (profile == "smart") {
           try {
             _logs.add("[SMART] Probing network...");
             final Map<dynamic, dynamic>? smartConfig = await platform.invokeMethod('getSmartNetworkConfig');
             if (smartConfig != null) {
                recvWin = smartConfig['recv_win'].toString();
                recvConn = smartConfig['recv_conn'].toString();
                final score = smartConfig['score'];
                _logs.add("[SMART] Network Score: $score/100. Applied dynamic tuning.");
             }
           } catch (e) {
             _logs.add("[SMART] Failed to probe network: $e");
           }
        }

        await platform.invokeMethod('startCore', {
          "ip": ip,
          "port_range": prefs.getString('port_range') ?? "6000-19999",
          "pass": prefs.getString('auth') ?? "",
          "obfs": prefs.getString('obfs') ?? "hu``hqb`c",
          "udp_mode": "udp",
          "mtu": prefs.getInt('mtu') ?? 1500,
          "enable_udpgw": prefs.getBool('enable_udpgw') ?? true,
          "udpgw_port": prefs.getString('udpgw_port') ?? "7300",
          "udpgw_max_connections": prefs.getString('udpgw_max_connections') ?? "512",
          "udpgw_buffer_size": prefs.getString('udpgw_buffer_size') ?? "32",
          "tcp_snd_buf": prefs.getString('tcp_snd_buf') ?? "65535",
          "tcp_wnd": prefs.getString('tcp_wnd') ?? "65535",
          "socks_buf": prefs.getString('socks_buf') ?? "65536",
          "ping_interval": prefs.getInt('ping_interval') ?? 3,
          "ping_target": prefs.getString('ping_target') ?? "http://www.gstatic.com/generate_204",
          "filter_apps": prefs.getBool('filter_apps') ?? false,
          "bypass_mode": prefs.getBool('bypass_mode') ?? false,
          "apps_list": prefs.getString('apps_list') ?? "",
          "log_level": prefs.getString('log_level') ?? "info",
          "core_count": (prefs.getInt('core_count') ?? 4),
          "cpu_wakelock": prefs.getBool('cpu_wakelock') ?? false,
          "udpgw_transparent_dns": prefs.getBool('udpgw_transparent_dns') ?? false,
          "native_perf_profile": profile,
          "upstream_dns": prefs.getString('upstream_dns') ?? "8.8.8.8",
          "pdnsd_port": prefs.getInt('pdnsd_port') ?? 8091,
          "pdnsd_cache_entries": prefs.getInt('pdnsd_cache_entries') ?? 2048,
          "pdnsd_timeout_sec": prefs.getInt('pdnsd_timeout_sec') ?? 10,
          "pdnsd_min_ttl": prefs.getString('pdnsd_min_ttl') ?? "15m",
          "pdnsd_max_ttl": prefs.getString('pdnsd_max_ttl') ?? "1w",
          "pdnsd_query_method": prefs.getString('pdnsd_query_method') ?? "tcp_only",
          "pdnsd_verbosity": prefs.getInt('pdnsd_verbosity') ?? 2,
          "hysteria_recv_window": recvWin,
          "hysteria_recv_conn": recvConn
        });
        await platform.invokeMethod('resetStats');
        await platform.invokeMethod('startVpn');

        final now = DateTime.now();
        await prefs.setInt('vpn_start_time', now.millisecondsSinceEpoch);
        _startTime = now;
        _startTimer();
        setState(() => _vpnState = "connected");

        await _autoPilot.init();
        if (_autoPilot.config.autoReset) _autoPilot.start();

      } catch (e) {
        setState(() { _vpnState = "disconnected"; _logs.add("Start Failed: $e"); });
      }
    }
  }

  Future<void> _handleAccountSwitch(int index) async {
    final account = _accounts[index];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ip', account.ip);
    await prefs.setString('auth', account.auth);
    await prefs.setString('obfs', account.obfs);
    await prefs.setInt('active_account_index', index);
    setState(() => _activeAccountIndex = index);
    _sessionRx.value = 0; _sessionTx.value = 0;
    if (_vpnState == "connected") {
      await _toggleVpn(); await Future.delayed(const Duration(milliseconds: 500)); await _toggleVpn();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            DashboardTab(
              vpnState: _vpnState,
              onToggle: _toggleVpn,
              onToggleAutoPilot: () {
                if (_autoPilot.isRunning) {
                  _autoPilot.stop();
                } else {
                  _autoPilot.start();
                }
              },
              dl: _dlSpeed,
              ul: _ulSpeed,
              duration: _durationNotifier,
              sessionRx: _sessionRx,
              sessionTx: _sessionTx,
              autoPilotActive: _autoPilotActive,
              isResetting: _autoPilotResetting,
            ),
            ProxiesTab(
              accounts: _accounts,
              activePingIndex: _activeAccountIndex,
              onActivate: _handleAccountSwitch,
              onAdd: (acc) { setState(() => _accounts.add(acc)); _saveAccounts(); },
              onEdit: (index, newAcc) { setState(() => _accounts[index] = newAcc); _saveAccounts(); },
              onDelete: (index) {
                setState(() {
                  _accounts.removeAt(index);
                  if (_activeAccountIndex == index) _activeAccountIndex = -1;
                  else if (_activeAccountIndex > index) _activeAccountIndex--;
                });
                _saveAccounts();
              },
            ),
            LogsTab(logs: _logs, scrollController: _logScrollCtrl),
            const AutoPilotTab(),
            SettingsTab(
              onCheckUpdate: () async {
                final hasUpdate = await _updateViewModel.checkForUpdate();
                if (!hasUpdate && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("You are using the latest version!")));
              },
              onRestoreSuccess: () => _loadData(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primaryLow,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.public_outlined), selectedIcon: Icon(Icons.public), label: 'Proxies'),
          NavigationDestination(icon: Icon(Icons.terminal_outlined), selectedIcon: Icon(Icons.terminal), label: 'Logs'),
          NavigationDestination(icon: Icon(Icons.radar_outlined), selectedIcon: Icon(Icons.radar), label: 'Auto Pilot'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

class _DownloadProgressDialog extends StatefulWidget {
  final Stream<double> progress;
  final String abi;
  final VoidCallback onStop;

  const _DownloadProgressDialog({
    required this.progress, 
    required this.abi,
    required this.onStop,
  });

  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: StreamBuilder<double>(
        stream: widget.progress,
        builder: (context, snapshot) {
          final progress = snapshot.data ?? 0.0;
          final percent = (progress * 100).toInt().clamp(0, 100);

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 20),
              Stack(
                alignment: Alignment.center,
                children: [
                  // Background Circle
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: CircularProgressIndicator(
                      value: 1.0,
                      strokeWidth: 8,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withValues(alpha: 0.05)),
                    ),
                  ),
                  // Rotating "Snake" Progress
                  RotationTransition(
                    turns: _rotationController,
                    child: SizedBox(
                      width: 100,
                      height: 100,
                      child: CircularProgressIndicator(
                        value: 0.1 + (progress * 0.1), // Snake memanjang sedikit saat progres naik
                        strokeWidth: 8,
                        strokeCap: StrokeCap.round,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                    ),
                  ),
                  // Real Progress Circle
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 8,
                      strokeCap: StrokeCap.round,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary.withValues(alpha: 0.5)),
                    ),
                  ),
                  Text(
                    "$percent%",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                "Downloading Update...",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                "Architecture: ${widget.abi}",
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white10,
                borderRadius: BorderRadius.circular(10),
              ),
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: widget.onStop,
                icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent),
                label: const Text("Stop & Resume Later", style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          );
        },
      ),
    );
  }
}
