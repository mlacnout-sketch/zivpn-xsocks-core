import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
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
        cardTheme: CardTheme(
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

  // App State
  bool _isRunning = false;
  final List<String> _logs = [];
  final ScrollController _logScrollCtrl = ScrollController();
  
  @override
  void initState() {
    super.initState();
    _checkVpnStatus();
    _initLogListener();
  }

  Future<void> _checkVpnStatus() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isRunning = prefs.getBool('vpn_running') ?? false;
    });
  }

  void _initLogListener() {
    logChannel.receiveBroadcastStream().listen((event) {
      if (event is String && mounted) {
        setState(() {
          _logs.add(event);
          if (_logs.length > 1000) _logs.removeAt(0);
        });
        // Auto scroll logs if on Log tab
        if (_selectedIndex == 2 && _logScrollCtrl.hasClients) {
          _logScrollCtrl.jumpTo(_logScrollCtrl.position.maxScrollExtent);
        }
      }
    });
  }

  Future<void> _toggleVpn() async {
    HapticFeedback.mediumImpact();
    if (_isRunning) {
      try {
        await platform.invokeMethod('stopCore');
        setState(() => _isRunning = false);
      } catch (e) {
        _logs.add("Error stopping: $e");
      }
    } else {
      // Load config from prefs before starting
      final prefs = await SharedPreferences.getInstance();
      final ip = prefs.getString('ip') ?? "";
      if (ip.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please configure Server IP in Settings")),
        );
        setState(() => _selectedIndex = 3); // Jump to settings
        return;
      }

      try {
        await platform.invokeMethod('startCore', {
          "ip": ip,
          "port_range": prefs.getString('port_range') ?? "6000-19999",
          "pass": prefs.getString('auth') ?? "",
          "obfs": prefs.getString('obfs') ?? "hu``hqb`c",
          "recv_window_multiplier": 4.0, // Max performance
          "udp_mode": "udp",
          "mtu": 1500
        });
        await platform.invokeMethod('startVpn');
        setState(() => _isRunning = true);
      } catch (e) {
        setState(() {
          _isRunning = false;
          _logs.add("Start Failed: $e");
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardTab(isRunning: _isRunning, onToggle: _toggleVpn),
      const ProxiesTab(),
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
        indicatorColor: const Color(0xFF6C63FF).withOpacity(0.2),
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

// --- TABS ---

class DashboardTab extends StatelessWidget {
  final bool isRunning;
  final VoidCallback onToggle;

  const DashboardTab({super.key, required this.isRunning, required this.onToggle});

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
          
          // Big Connection Button
          Expanded(
            child: Center(
              child: GestureDetector(
                onTap: onToggle,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isRunning ? const Color(0xFF6C63FF) : const Color(0xFF272736),
                    boxShadow: [
                      BoxShadow(
                        color: (isRunning ? const Color(0xFF6C63FF) : Colors.black).withOpacity(0.4),
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
                      const SizedBox(height: 10),
                      Text(
                        isRunning ? "CONNECTED" : "TAP TO CONNECT",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          // Traffic Stats (Placeholder for now)
          const Row(
            children: [
              Expanded(child: StatCard(label: "Download", value: "0 KB/s", icon: Icons.download, color: Colors.green)),
              SizedBox(width: 15),
              Expanded(child: StatCard(label: "Upload", value: "0 KB/s", icon: Icons.upload, color: Colors.orange)),
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
            decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
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

class ProxiesTab extends StatelessWidget {
  const ProxiesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text("Proxy Groups", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        _buildGroup("Load Balancer", "Round Robin", Colors.blue),
        _buildGroup("Hysteria Core", "UDP Turbo", Colors.purple),
        const SizedBox(height: 20),
        const Text("Nodes", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 10),
        _buildNode("Hysteria-1", "127.0.0.1:20080", "12 ms"),
        _buildNode("Hysteria-2", "127.0.0.1:20081", "14 ms"),
        _buildNode("Hysteria-3", "127.0.0.1:20082", "11 ms"),
        _buildNode("Hysteria-4", "127.0.0.1:20083", "13 ms"),
      ],
    );
  }

  Widget _buildGroup(String name, String type, Color color) {
    return Card(
      child: ListTile(
        leading: Icon(Icons.hub, color: color),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(type),
        trailing: const Icon(Icons.more_vert),
      ),
    );
  }

  Widget _buildNode(String name, String ip, String ping) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.flash_on, color: Colors.green),
        title: Text(name),
        subtitle: Text(ip),
        trailing: Text(ping, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
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
              IconButton(icon: const Icon(Icons.delete), onPressed: () => logs.clear()),
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
                  child: Text(
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
  final _ipCtrl = TextEditingController();
  final _authCtrl = TextEditingController();
  final _obfsCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ipCtrl.text = prefs.getString('ip') ?? "";
      _authCtrl.text = prefs.getString('auth') ?? "";
      _obfsCtrl.text = prefs.getString('obfs') ?? "hu``hqb`c";
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ip', _ipCtrl.text);
    await prefs.setString('auth', _authCtrl.text);
    await prefs.setString('obfs', _obfsCtrl.text);
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Settings Saved")));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text("Configuration", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        _buildInput(_ipCtrl, "Server IP / Domain", Icons.dns),
        const SizedBox(height: 15),
        _buildInput(_authCtrl, "Password / Auth", Icons.password),
        const SizedBox(height: 15),
        _buildInput(_obfsCtrl, "Obfuscation Salt", Icons.security),
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