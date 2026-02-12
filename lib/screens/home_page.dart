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
import 'tabs/settings_tab.dart';
import '../viewmodels/update_viewmodel.dart';
import '../repositories/backup_repository.dart';
import '../models/app_version.dart';
import '../models/account.dart';

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
  
  // Optimized: Use ValueNotifier to prevent full rebuilds on stats update
  final ValueNotifier<String> _dlSpeed = ValueNotifier("0 KB/s");
  final ValueNotifier<String> _ulSpeed = ValueNotifier("0 KB/s");
  final ValueNotifier<int> _sessionRx = ValueNotifier(0);
  final ValueNotifier<int> _sessionTx = ValueNotifier(0);
  
  @override
  void initState() {
    super.initState();
    _loadData();
    _initLogListener();
    _initStatsListener();
    _checkInitialImport();
    
    // Auto-update check
    _updateViewModel.availableUpdate.listen((update) {
      if (update != null && mounted) {
        _showUpdateDialog(update);
      }
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

  Future<void> _checkInitialImport() async {
    try {
      final String? filePath = await platform.invokeMethod('getInitialFile');
      if (filePath != null && mounted) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.card,
            title: const Text("Import Backup?"),
            content: const Text("A backup file was detected. Do you want to restore it now? This will overwrite current settings."),
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
            final repo = BackupRepository();
            final success = await repo.restoreBackup(File(filePath));
            if (success) {
                _loadData(); // Refresh UI
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Backup imported successfully.")),
                );
            } else {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Failed to import backup.")),
                );
            }
        }
      }
    } catch (e) {
      print("Import check error: $e");
    }
  }

  void _showUpdateDialog(AppVersion update) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text("Update Available: v${update.name}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Size: ${(update.apkSize / (1024 * 1024)).toStringAsFixed(2)} MB"),
            const SizedBox(height: 10),
            const Text("Changelog:"),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(child: Text(update.description)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text("Later")
          ),
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StreamBuilder<double>(
        stream: _updateViewModel.downloadProgress,
        builder: (context, snapshot) {
          double progress = snapshot.data ?? 0.0;
          return AlertDialog(
            backgroundColor: AppColors.card,
            title: const Text("Downloading Update..."),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: progress >= 0 ? progress : null,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 10),
                Text(progress >= 0 ? "${(progress * 100).toStringAsFixed(0)}%" : "Connecting..."),
              ],
            ),
          );
        },
      ),
    );

    final file = await _updateViewModel.startDownload(update);
    if (mounted) Navigator.pop(context); // Close progress dialog

    if (file != null) {
      await OpenFilex.open(file.path);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Download failed")),
      );
    }
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
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
      if (_logs.length > 1000) {
        _logs.removeRange(0, _logs.length - 1000);
      }
    });

    if (_selectedIndex == 2 && _logScrollCtrl.hasClients) {
      // Scroll to bottom after frame build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logScrollCtrl.hasClients) {
          _logScrollCtrl.jumpTo(_logScrollCtrl.position.maxScrollExtent);
        }
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

          // Optimized: Update notifiers directly, no setState
          _dlSpeed.value = _formatBytes(rx);
          _ulSpeed.value = _formatBytes(tx);
          _sessionRx.value += rx;
          _sessionTx.value += tx;

          if (_activeAccountIndex != -1) {
            _accounts[_activeAccountIndex].usage += rx + tx;
          }
        }
      }
    });
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return "$bytes B/s";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB/s";
    return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB/s";
  }

  Future<void> _toggleVpn() async {
    HapticFeedback.mediumImpact();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Force reload

    if (_vpnState == "connected") {
      try {
        await platform.invokeMethod('stopCore');
        _timer?.cancel();
        setState(() {
          _vpnState = "disconnected";
          _startTime = null;
        });
        _durationNotifier.value = "00:00:00";
        // Reset stats via notifier
        _sessionRx.value = 0;
        _sessionTx.value = 0;
        _dlSpeed.value = "0 KB/s";
        _ulSpeed.value = "0 KB/s";
        
        await prefs.remove('vpn_start_time');
        await _saveAccounts();
      } catch (e) {
        _logs.add("Error stopping: $e");
      }
    } else {
      final ip = prefs.getString('ip') ?? "";
      if (ip.isEmpty) {
        setState(() => _selectedIndex = 3); // Go to settings
        return;
      }

      setState(() => _vpnState = "connecting");

      final bool useWakelock = prefs.getBool('cpu_wakelock') ?? false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Connecting... (Wakelock: $useWakelock)"),
          duration: const Duration(seconds: 1),
          backgroundColor: AppColors.primary,
        ),
      );

      try {
        await platform.invokeMethod('startCore', {
          "ip": ip,
          "port_range": prefs.getString('port_range') ?? "6000-19999",
          "pass": prefs.getString('auth') ?? "",
          "obfs": prefs.getString('obfs') ?? "hu``hqb`c",
          "recv_window_multiplier": 4.0,
          "udp_mode": "udp",
          "mtu": int.tryParse(prefs.getString('mtu') ?? "1200") ?? 1200,
          "auto_tuning": prefs.getBool('auto_tuning') ?? true,
          "enable_udpgw": prefs.getBool('enable_udpgw') ?? true,
          "udpgw_mode": prefs.getString('udpgw_mode') ?? "relay",
          "udpgw_port": prefs.getString('udpgw_port') ?? "7300",
          "ping_interval": int.tryParse(prefs.getString('ping_interval') ?? "3") ?? 3,
          "ping_target": prefs.getString('ping_target') ?? "http://www.gstatic.com/generate_204",
          "filter_apps": prefs.getBool('filter_apps') ?? false,
          "bypass_mode": prefs.getBool('bypass_mode') ?? false,
          "apps_list": prefs.getString('apps_list') ?? "",
          "buffer_size": prefs.getString('buffer_size') ?? "4m",
          "log_level": prefs.getString('log_level') ?? "info",
          "core_count": (prefs.getInt('core_count') ?? 4),
          "cpu_wakelock": prefs.getBool('cpu_wakelock') ?? false
        });
        await platform.invokeMethod('startVpn');

        final now = DateTime.now();
        await prefs.setInt('vpn_start_time', now.millisecondsSinceEpoch);
        _startTime = now;
        _startTimer();

        setState(() => _vpnState = "connected");
      } catch (e) {
        setState(() {
          _vpnState = "disconnected";
          _logs.add("Start Failed: $e");
        });
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

    setState(() {
      _activeAccountIndex = index;
    });
    
    // Reset stats via notifier
    _sessionRx.value = 0;
    _sessionTx.value = 0;
    _dlSpeed.value = "0 KB/s";
    _ulSpeed.value = "0 KB/s";

    if (_vpnState == "connected") {
      await _toggleVpn(); // Stop
      await Future.delayed(const Duration(milliseconds: 500));
      await _toggleVpn(); // Start
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
            ),
            ProxiesTab(
              accounts: _accounts,
              activePingIndex: _activeAccountIndex,
              onActivate: _handleAccountSwitch,
              onAdd: (acc) {
                setState(() => _accounts.add(acc));
                _saveAccounts();
              },
              onEdit: (index, newAcc) {
                setState(() => _accounts[index] = newAcc);
                _saveAccounts();
              },
              onDelete: (index) {
                setState(() {
                  _accounts.removeAt(index);
                  if (_activeAccountIndex == index) {
                    _activeAccountIndex = -1;
                  } else if (_activeAccountIndex > index) {
                    _activeAccountIndex--;
                  }
                });
                _saveAccounts();
                SharedPreferences.getInstance().then((p) => p.setInt('active_account_index', _activeAccountIndex));
              },
            ),
            LogsTab(logs: _logs, scrollController: _logScrollCtrl),
            SettingsTab(
              onCheckUpdate: () async {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Checking for updates...")),
              );
              final hasUpdate = await _updateViewModel.checkForUpdate();
              if (!hasUpdate && mounted) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("You are using the latest version!")),
                );
              }
            },
            onRestoreSuccess: () {
              _loadData(); // Refresh accounts and vpn state
            },
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) {
          setState(() {
            _selectedIndex = i;
          });
        },
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primaryLow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.public_outlined),
            selectedIcon: Icon(Icons.public),
            label: 'Proxies',
          ),
          NavigationDestination(
            icon: Icon(Icons.terminal_outlined),
            selectedIcon: Icon(Icons.terminal),
            label: 'Logs',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
