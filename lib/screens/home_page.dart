import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'tabs/dashboard_tab.dart';
import 'tabs/proxies_tab.dart';
import 'tabs/logs_tab.dart';
import 'tabs/settings_tab.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  static const platform = MethodChannel('com.minizivpn.app/core');
  static const logChannel = EventChannel('com.minizivpn.app/logs');
  static const statsChannel = EventChannel('com.minizivpn.app/stats');

  String _vpnState = "disconnected"; // disconnected, connecting, connected
  final List<String> _logs = [];
  final ScrollController _logScrollCtrl = ScrollController();
  
  List<Map<String, dynamic>> _accounts = [];
  int _activeAccountIndex = -1;
  
  Timer? _timer;
  DateTime? _startTime;
  String _durationString = "00:00:00";
  
  String _dlSpeed = "0 KB/s";
  String _ulSpeed = "0 KB/s";
  int _sessionRx = 0;
  int _sessionTx = 0;
  
  @override
  void initState() {
    super.initState();
    _loadData();
    _initLogListener();
    _initStatsListener();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString('saved_accounts');
    if (jsonStr != null) {
      _accounts = List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
    }
    
    final isRunning = prefs.getBool('vpn_running') ?? false;
    final startMillis = prefs.getInt('vpn_start_time');
    final currentIp = prefs.getString('ip') ?? "";
    
    if (currentIp.isNotEmpty) {
      _activeAccountIndex = _accounts.indexWhere((acc) => acc['ip'] == currentIp);
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
    await prefs.setString('saved_accounts', jsonEncode(_accounts));
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_startTime == null) return;
      final diff = DateTime.now().difference(_startTime!);
      String twoDigits(int n) => n.toString().padLeft(2, "0");
      setState(() {
        _durationString =
            "${twoDigits(diff.inHours)}:${twoDigits(diff.inMinutes.remainder(60))}:${twoDigits(diff.inSeconds.remainder(60))}";
      });
    });
  }

  void _initLogListener() {
    logChannel.receiveBroadcastStream().listen((event) {
      if (event is String && mounted) {
        setState(() {
          _logs.add(event);
          if (_logs.length > 1000) _logs.removeAt(0);
        });
        if (_selectedIndex == 2 && _logScrollCtrl.hasClients) {
          _logScrollCtrl.jumpTo(_logScrollCtrl.position.maxScrollExtent);
        }
      }
    });
  }

  void _initStatsListener() {
    statsChannel.receiveBroadcastStream().listen((event) {
      if (event is String && mounted) {
        final parts = event.split('|');
        if (parts.length == 2) {
          final rx = int.tryParse(parts[0]) ?? 0;
          final tx = int.tryParse(parts[1]) ?? 0;

          setState(() {
            _dlSpeed = _formatBytes(rx);
            _ulSpeed = _formatBytes(tx);
            _sessionRx += rx;
            _sessionTx += tx;

            if (_activeAccountIndex != -1) {
              _accounts[_activeAccountIndex]['usage'] =
                  (_accounts[_activeAccountIndex]['usage'] ?? 0) + rx + tx;
            }
          });
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

    if (_vpnState == "connected") {
      try {
        await platform.invokeMethod('stopCore');
        _timer?.cancel();
        setState(() {
          _vpnState = "disconnected";
          _durationString = "00:00:00";
          _startTime = null;
          _sessionRx = 0;
          _sessionTx = 0;
        });
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
          "buffer_size": prefs.getString('buffer_size') ?? "4m",
          "log_level": prefs.getString('log_level') ?? "info",
          "core_count": (prefs.getInt('core_count') ?? 4)
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

    await prefs.setString('ip', account['ip']);
    await prefs.setString('auth', account['auth']);
    await prefs.setString('obfs', account['obfs']);

    setState(() {
      _activeAccountIndex = index;
      _sessionRx = 0;
      _sessionTx = 0;
    });

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
              duration: _durationString,
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
              onDelete: (index) {
                setState(() => _accounts.removeAt(index));
                _saveAccounts();
              },
            ),
            LogsTab(logs: _logs, scrollController: _logScrollCtrl),
            const SettingsTab(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        backgroundColor: const Color(0xFF1E1E2E),
        indicatorColor: const Color(0xFF6C63FF).withValues(alpha: 0.2),
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