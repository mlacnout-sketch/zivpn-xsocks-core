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
        setState(() {
          _autoPilotActive = state.status != AutoPilotStatus.stopped;
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
    final file = await _updateViewModel.startDownload(update);
    if (file != null) await OpenFilex.open(file.path);
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
        final parts = event.split('|');
        if (parts.length == 2) {
          final rx = int.tryParse(parts[0]) ?? 0;
          final tx = int.tryParse(parts[1]) ?? 0;
          _dlSpeed.value = FormatUtils.formatBytes(rx, asSpeed: true);
          _ulSpeed.value = FormatUtils.formatBytes(tx, asSpeed: true);
          _sessionRx.value += rx;
          _sessionTx.value += tx;
          if (_activeAccountIndex != -1) _accounts[_activeAccountIndex].usage += rx + tx;
        }
      }
    });
  }

  Future<void> _toggleVpn() async {
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

      if (mounted) {
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
          "native_perf_profile": prefs.getString('native_perf_profile') ?? "balanced",
          "pdnsd_port": prefs.getInt('pdnsd_port') ?? 8091,
          "pdnsd_cache_entries": prefs.getInt('pdnsd_cache_entries') ?? 2048,
          "pdnsd_timeout_sec": prefs.getInt('pdnsd_timeout_sec') ?? 10,
          "pdnsd_min_ttl": prefs.getString('pdnsd_min_ttl') ?? "15m",
          "pdnsd_max_ttl": prefs.getString('pdnsd_max_ttl') ?? "1w",
          "pdnsd_query_method": prefs.getString('pdnsd_query_method') ?? "tcp_only",
          "pdnsd_verbosity": prefs.getInt('pdnsd_verbosity') ?? 2
        });
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
