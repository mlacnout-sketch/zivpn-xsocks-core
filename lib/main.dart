import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MiniZivpnApp());
}

class MiniZivpnApp extends StatelessWidget {
  const MiniZivpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MiniZivpn',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
          surface: const Color(0xFF1E1E2E),
        ),
        scaffoldBackgroundColor: const Color(0xFF121218),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF272736),
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  
  // Core Channels
  static const platform = MethodChannel('com.minizivpn.app/core');
  static const logChannel = EventChannel('com.minizivpn.app/logs');
  static const statsChannel = EventChannel('com.minizivpn.app/stats');

  // App State
  bool _isRunning = false;
  final List<String> _logs = [];
  final ScrollController _logScrollCtrl = ScrollController();
  
  // Timer State
  Timer? _timer;
  DateTime? _startTime;
  String _durationString = "00:00:00";
  
  // Stats
  String _dlSpeed = "0 KB/s";
  String _ulSpeed = "0 KB/s";
  
  @override
  void initState() {
    super.initState();
    _checkVpnStatus();
    _initLogListener();
    _initStatsListener();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkVpnStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final isRunning = prefs.getBool('vpn_running') ?? false;
    final startMillis = prefs.getInt('vpn_start_time');
    
    setState(() {
      _isRunning = isRunning;
      if (isRunning && startMillis != null) {
        _startTime = DateTime.fromMillisecondsSinceEpoch(startMillis);
        _startTimer();
      } else {
        _durationString = "00:00:00";
      }
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_startTime == null) return;
      final diff = DateTime.now().difference(_startTime!);
      String twoDigits(int n) => n.toString().padLeft(2, "0");
      final hours = twoDigits(diff.inHours);
      final minutes = twoDigits(diff.inMinutes.remainder(60));
      final seconds = twoDigits(diff.inSeconds.remainder(60));
      setState(() {
        _durationString = "$hours:$minutes:$seconds";
      });
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    setState(() {
      _durationString = "00:00:00";
      _startTime = null;
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
    
    if (_isRunning) {
      try {
        await platform.invokeMethod('stopCore');
        _stopTimer();
        await prefs.remove('vpn_start_time');
        setState(() => _isRunning = false);
      } catch (e) {
        _logs.add("Error stopping: $e");
      }
    } else {
      final ip = prefs.getString('ip') ?? "";
      if (ip.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please configure Server IP in Settings")),
        );
        setState(() => _selectedIndex = 3);
        return;
      }

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
        
        // Start Timer
        final now = DateTime.now();
        await prefs.setInt('vpn_start_time', now.millisecondsSinceEpoch);
        _startTime = now;
        _startTimer();
        
        setState(() => _isRunning = true);
      } catch (e) {
        setState(() {
          _isRunning = false;
          _logs.add("Start Failed: $e");
        });
      }
    }
  }

  Future<void> _handleAccountSwitch() async {
    if (_isRunning) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Switching account..."),
          duration: Duration(seconds: 1),
          backgroundColor: Color(0xFF6C63FF),
        )
      );
      
      // Stop
      await _toggleVpn();
      
      // Wait for cleanup
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Start
      await _toggleVpn();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardTab(
        isRunning: _isRunning, 
        onToggle: _toggleVpn, 
        dl: _dlSpeed, 
        ul: _ulSpeed,
        duration: _durationString,
      ),
      ProxiesTab(onActivate: _handleAccountSwitch),
      LogsTab(logs: _logs, scrollController: _logScrollCtrl),
      const SettingsTab(),
    ];

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: pages,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        backgroundColor: const Color(0xFF1E1E2E),
        indicatorColor: const Color(0xFF6C63FF).withValues(alpha: 0.2),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.public_outlined), selectedIcon: Icon(Icons.public), label: 'Proxies'),
          NavigationDestination(icon: Icon(Icons.terminal_outlined), selectedIcon: Icon(Icons.terminal), label: 'Logs'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

class DashboardTab extends StatelessWidget {
  final bool isRunning;
  final VoidCallback onToggle;
  final String dl;
  final String ul;
  final String duration;

  const DashboardTab({
    super.key, 
    required this.isRunning, 
    required this.onToggle,
    this.dl = "0 KB/s",
    this.ul = "0 KB/s",
    this.duration = "00:00:00",
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text("ZIVPN", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          const Text("Turbo Tunnel Engine", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 40),
          
          Expanded(
            child: Center(
              child: GestureDetector(
                onTap: onToggle,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isRunning ? const Color(0xFF6C63FF) : const Color(0xFF272736),
                    boxShadow: [
                      BoxShadow(
                        color: (isRunning ? const Color(0xFF6C63FF) : Colors.black).withValues(alpha: 0.4),
                        blurRadius: 30,
                        spreadRadius: 10,
                      )
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isRunning ? Icons.vpn_lock : Icons.power_settings_new,
                        size: 64,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 15),
                      Text(
                        isRunning ? "CONNECTED" : "TAP TO CONNECT",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      if (isRunning) ...[
                        const SizedBox(height: 15),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white12)
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.timer, size: 14, color: Colors.white70),
                              const SizedBox(width: 6),
                              Text(
                                duration,
                                style: const TextStyle(
                                  fontFamily: 'monospace', 
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.white
                                ),
                              ),
                            ],
                          ),
                        ),
                      ]
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          Row(
            children: [
              Expanded(child: StatCard(label: "Download", value: dl, icon: Icons.download, color: Colors.green)),
              const SizedBox(width: 15),
              Expanded(child: StatCard(label: "Upload", value: ul, icon: Icons.upload, color: Colors.orange)),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const StatCard({super.key, required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF272736),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          )
        ],
      ),
    );
  }
}

class ProxiesTab extends StatefulWidget {
  final Future<void> Function()? onActivate;
  
  const ProxiesTab({super.key, this.onActivate});

  @override
  State<ProxiesTab> createState() => _ProxiesTabState();
}

class _ProxiesTabState extends State<ProxiesTab> {
  List<Map<String, dynamic>> _accounts = [];

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString('saved_accounts');
    if (jsonStr != null) {
      setState(() {
        _accounts = List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
      });
    }
  }

  Future<void> _saveAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_accounts', jsonEncode(_accounts));
  }

  Future<void> _activateAccount(Map<String, dynamic> account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ip', account['ip']);
    await prefs.setString('auth', account['auth']);
    await prefs.setString('obfs', account['obfs']);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Activated: ${account['name']}"),
          backgroundColor: const Color(0xFF6C63FF),
          duration: const Duration(milliseconds: 800),
        ),
      );
    }
    
    if (widget.onActivate != null) {
      await widget.onActivate!();
    }
  }

  Future<void> _deleteAccount(int index) async {
    setState(() {
      _accounts.removeAt(index);
    });
    await _saveAccounts();
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final ipCtrl = TextEditingController();
    final authCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF272736),
        title: const Text("Add Account"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Name (e.g. SG-1)")),
              TextField(controller: ipCtrl, decoration: const InputDecoration(labelText: "IP:Port")),
              TextField(controller: authCtrl, decoration: const InputDecoration(labelText: "Password")),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C63FF), foregroundColor: Colors.white),
            onPressed: () {
              if (nameCtrl.text.isNotEmpty && ipCtrl.text.isNotEmpty) {
                setState(() {
                  _accounts.add({
                    "name": nameCtrl.text,
                    "ip": ipCtrl.text,
                    "auth": authCtrl.text,
                    "obfs": "hu``hqb`c",
                  });
                });
                _saveAccounts();
                Navigator.pop(ctx);
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        backgroundColor: const Color(0xFF6C63FF),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _accounts.isEmpty 
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.no_accounts_outlined, size: 64, color: Colors.grey.withOpacity(0.3)),
                  const SizedBox(height: 16),
                  const Text("No accounts saved", style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _accounts.length,
              itemBuilder: (context, index) {
                final acc = _accounts[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C63FF).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.dns, color: Color(0xFF6C63FF)),
                    ),
                    title: Text(acc['name'] ?? "Unknown", style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(acc['ip'] ?? ""),
                    trailing: PopupMenuButton(
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(value: 'delete', child: Text("Delete")),
                      ],
                      onSelected: (val) {
                        if (val == 'delete') _deleteAccount(index);
                      },
                    ),
                    onTap: () => _activateAccount(acc),
                  ),
                );
              },
            ),
    );
  }
}

class LogsTab extends StatelessWidget {
  final List<String> logs;
  final ScrollController scrollController;

  const LogsTab({super.key, required this.logs, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Live Logs", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.copy_all),
                    tooltip: "Copy All",
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: logs.join("\n")));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("All logs copied")));
                    },
                  ),
                  IconButton(icon: const Icon(Icons.delete), onPressed: () => logs.clear()),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0F12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: ListView.builder(
              controller: scrollController,
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[index];
                final isError = log.toLowerCase().contains("error") || log.toLowerCase().contains("fail");
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: SelectableText(
                    log,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: isError ? Colors.redAccent : Colors.greenAccent,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final _mtuCtrl = TextEditingController();
  
  bool _autoTuning = true;
  String _bufferSize = "4m";
  String _logLevel = "info";
  double _coreCount = 4.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _mtuCtrl.text = prefs.getString('mtu') ?? "1200";
      _autoTuning = prefs.getBool('auto_tuning') ?? true;
      _bufferSize = prefs.getString('buffer_size') ?? "4m";
      _logLevel = prefs.getString('log_level') ?? "info";
      _coreCount = (prefs.getInt('core_count') ?? 4).toDouble();
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mtu', _mtuCtrl.text);
    await prefs.setBool('auto_tuning', _autoTuning);
    await prefs.setString('buffer_size', _bufferSize);
    await prefs.setString('log_level', _logLevel);
    await prefs.setInt('core_count', _coreCount.toInt());
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Settings Saved")));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text("Core Settings", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                _buildInput(_mtuCtrl, "MTU (Default: 1500)", Icons.settings_ethernet),
                const SizedBox(height: 15),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text("Hysteria Cores: ${_coreCount.toInt()}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Slider(
                      value: _coreCount,
                      min: 1,
                      max: 8,
                      divisions: 7,
                      label: "${_coreCount.toInt()} Cores",
                      onChanged: (val) => setState(() => _coreCount = val),
                    ),
                    const Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text("More cores = Higher speed but more battery usage", style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ),
                  ],
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text("TCP Auto Tuning"),
                  subtitle: const Text("Dynamic buffer sizing for stability"),
                  value: _autoTuning,
                  onChanged: (val) => setState(() => _autoTuning = val),
                ),
                const Divider(),
                ListTile(
                  title: const Text("TCP Buffer Size"),
                  subtitle: const Text("Max window size per connection"),
                  trailing: DropdownButton<String>(
                    value: _bufferSize,
                    items: const [
                      DropdownMenuItem(value: "1m", child: Text("1 MB")),
                      DropdownMenuItem(value: "2m", child: Text("2 MB")),
                      DropdownMenuItem(value: "4m", child: Text("4 MB")),
                      DropdownMenuItem(value: "8m", child: Text("8 MB")),
                    ],
                    onChanged: (val) => setState(() => _bufferSize = val!),
                  ),
                ),
                ListTile(
                  title: const Text("Log Level"),
                  subtitle: const Text("Verbosity of logs"),
                  trailing: DropdownButton<String>(
                    value: _logLevel,
                    items: const [
                      DropdownMenuItem(value: "debug", child: Text("Debug (Verbose)")),
                      DropdownMenuItem(value: "info", child: Text("Info (Standard)")),
                      DropdownMenuItem(value: "error", child: Text("Error (Minimal)")),
                      DropdownMenuItem(value: "silent", child: Text("Silent (None)")),
                    ],
                    onChanged: (val) => setState(() => _logLevel = val!),
                  ),
                )
              ],
            ),
          ),
        ),

        const SizedBox(height: 30),
        ElevatedButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save),
          label: const Text("Save Configuration"),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6C63FF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        )
      ],
    );
  }

  Widget _buildInput(TextEditingController ctrl, String label, IconData icon) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: const Color(0xFF272736),
      ),
    );
  }
}
