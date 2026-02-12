import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import '../../app_colors.dart';
import '../../repositories/backup_repository.dart';
import '../app_selector_page.dart';

class SettingsTab extends StatefulWidget {
  final VoidCallback onCheckUpdate;
  final VoidCallback? onRestoreSuccess;

  const SettingsTab({
    super.key, 
    required this.onCheckUpdate,
    this.onRestoreSuccess,
  });

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final _mtuCtrl = TextEditingController();
  final _pingTargetCtrl = TextEditingController();
  final _pingIntervalCtrl = TextEditingController();
  final _udpgwPortCtrl = TextEditingController();
  final _udpgwMaxConnCtrl = TextEditingController();
  final _udpgwBufSizeCtrl = TextEditingController();
  final _dnsCtrl = TextEditingController();
  final _appsListCtrl = TextEditingController();
  final _tcpSndBufCtrl = TextEditingController();
  final _tcpWndCtrl = TextEditingController();
  final _socksBufCtrl = TextEditingController();

  bool _cpuWakelock = false;
  bool _enableUdpgw = true;
  bool _filterApps = false;
  bool _bypassMode = false;
  String _logLevel = "info";
  double _coreCount = 4.0;
  String _appVersion = "Unknown";
  final _backupRepo = BackupRepository();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadVersion();
  }

  Future<void> _openAppSelector() async {
    final currentList = _appsListCtrl.text
        .split("\n")
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final result = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (context) => AppSelectorPage(initialSelected: currentList),
      ),
    );

    if (result != null) {
      setState(() {
        _appsListCtrl.text = result.join("\n");
      });
    }
  }

  Future<void> _handleBackup() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Creating backup...")),
    );
    
    final file = await _backupRepo.createBackup();
    if (file != null && mounted) {
      await Share.shareXFiles([XFile(file.path)], text: "MiniZIVPN Config Backup");
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Backup failed")),
      );
    }
  }

  Future<void> _handleRestore() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final success = await _backupRepo.restoreBackup(file);
      
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Restore successful.")),
          );
          _loadSettings(); // Reload Settings UI
          widget.onRestoreSuccess?.call(); // Reload Home/Proxies UI
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Restore failed. Invalid backup file.")),
          );
        }
      }
    }
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = "v${info.version}");
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _mtuCtrl.text = (prefs.getInt('mtu') ?? 1500).toString();
      _pingTargetCtrl.text = prefs.getString('ping_target') ?? "http://www.gstatic.com/generate_204";
      _pingIntervalCtrl.text = prefs.getString('ping_interval') ?? "3";
      _udpgwPortCtrl.text = prefs.getString('udpgw_port') ?? "7300";
      _udpgwMaxConnCtrl.text = prefs.getString('udpgw_max_connections') ?? "512";
      _udpgwBufSizeCtrl.text = prefs.getString('udpgw_buffer_size') ?? "32";
      _dnsCtrl.text = prefs.getString('upstream_dns') ?? "208.67.222.222";
      _appsListCtrl.text = prefs.getString('apps_list') ?? "";
      _tcpSndBufCtrl.text = prefs.getString('tcp_snd_buf') ?? "65535";
      _tcpWndCtrl.text = prefs.getString('tcp_wnd') ?? "65535";
      _socksBufCtrl.text = prefs.getString('socks_buf') ?? "65536";
      _cpuWakelock = prefs.getBool('cpu_wakelock') ?? false;
      _enableUdpgw = prefs.getBool('enable_udpgw') ?? true;
      _filterApps = prefs.getBool('filter_apps') ?? false;
      _bypassMode = prefs.getBool('bypass_mode') ?? false;
      _logLevel = prefs.getString('log_level') ?? "info";
      _coreCount = (prefs.getInt('core_count') ?? 4).toDouble();
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Helper to get value or default
    String val(TextEditingController c, String d) => c.text.isEmpty ? d : c.text;

    await prefs.setInt('mtu', int.tryParse(val(_mtuCtrl, "1500")) ?? 1500);
    await prefs.setString('ping_target', val(_pingTargetCtrl, "http://www.gstatic.com/generate_204"));
    await prefs.setString('ping_interval', val(_pingIntervalCtrl, "3"));
    await prefs.setString('udpgw_port', val(_udpgwPortCtrl, "7300"));
    await prefs.setString('udpgw_max_connections', val(_udpgwMaxConnCtrl, "512"));
    await prefs.setString('udpgw_buffer_size', val(_udpgwBufSizeCtrl, "32"));
    await prefs.setString('upstream_dns', val(_dnsCtrl, "208.67.222.222"));
    await prefs.setString('apps_list', _appsListCtrl.text);
    await prefs.setString('tcp_snd_buf', val(_tcpSndBufCtrl, "65535"));
    await prefs.setString('tcp_wnd', val(_tcpWndCtrl, "65535"));
    await prefs.setString('socks_buf', val(_socksBufCtrl, "65536"));
    
    await prefs.setBool('cpu_wakelock', _cpuWakelock);
    await prefs.setBool('enable_udpgw', _enableUdpgw);
    await prefs.setBool('filter_apps', _filterApps);
    await prefs.setBool('bypass_mode', _bypassMode);
    await prefs.setString('log_level', _logLevel);
    await prefs.setInt('core_count', _coreCount.toInt());

    _loadSettings(); // Reload into controllers to show defaults if input was empty

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Settings Saved")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          "Core Settings",
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                _buildTextInput(
                  _mtuCtrl,
                  "MTU (Default: 1500)",
                  Icons.settings_ethernet,
                ),
                const Divider(),
                const ListTile(
                  title: Text("UDP Forwarding", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                ),
                SwitchListTile(
                  title: const Text("Forward UDP"),
                  subtitle: const Text("If active, redirects requests to the remote server."),
                  value: _enableUdpgw,
                  onChanged: (val) => setState(() => _enableUdpgw = val),
                ),
                if (_enableUdpgw)
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: _buildTextInput(
                          _udpgwPortCtrl,
                          "Udp Gateway Port (Remote)",
                          Icons.door_sliding,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: _buildTextInput(
                          _udpgwMaxConnCtrl,
                          "Max UDP Connections",
                          Icons.connect_without_contact,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: _buildTextInput(
                          _udpgwBufSizeCtrl,
                          "UDP Buffer (Packets)",
                          Icons.shopping_bag,
                        ),
                      ),
                    ],
                  ),
                const Divider(),
                const ListTile(
                  title: Text("Ping", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: _buildTextInput(
                    _pingIntervalCtrl,
                    "Ping(sec, ex. 3) | To disable use 0",
                    Icons.timer,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: _buildTextInput(
                    _pingTargetCtrl,
                    "Destination Ping (URL/IP)",
                    Icons.network_check,
                  ),
                ),
                const Divider(),
                const ListTile(
                  title: Text("Apps Filter", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                ),
                SwitchListTile(
                  title: const Text("Filter Apps"),
                  value: _filterApps,
                  onChanged: (val) => setState(() => _filterApps = val),
                ),
                SwitchListTile(
                  title: const Text("Bypass Mode"),
                  subtitle: const Text("If enabled, selected apps will bypass VPN."),
                  value: _bypassMode,
                  onChanged: (val) => setState(() => _bypassMode = val),
                ),
                ListTile(
                  leading: const Icon(Icons.apps),
                  title: const Text("Select Apps"),
                  subtitle: const Text("Choose apps to include or exclude"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _openAppSelector,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    controller: _appsListCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: "Apps List (Package names, one per line)",
                      prefixIcon: const Icon(Icons.list),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: AppColors.card,
                    ),
                  ),
                ),
                const Divider(),
                const ListTile(
                  title: Text("Advanced", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                ),
                _buildSliderSection(),
                SwitchListTile(
                  title: const Text("CPU Wakelock"),
                  subtitle: const Text("Prevent CPU sleep (High Battery Usage)"),
                  value: _cpuWakelock,
                  onChanged: (val) => setState(() => _cpuWakelock = val),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: _buildTextInput(
                    _tcpSndBufCtrl,
                    "TCP Send Buffer (Default: 65535)",
                    Icons.upload_file,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: _buildTextInput(
                    _tcpWndCtrl,
                    "TCP Window Size (Default: 65535)",
                    Icons.download_for_offline,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: _buildTextInput(
                    _socksBufCtrl,
                    "SOCKS Buffer Size (Default: 65536)",
                    Icons.memory,
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: _buildTextInput(
                    _dnsCtrl,
                    "Upstream DNS (IP:PORT)",
                    Icons.dns,
                  ),
                ),
                const Divider(),
                _buildDropdownTile(
                  "Log Level",
                  "Verbosity of logs",
                  _logLevel,
                  ["debug", "info", "error", "silent"],
                  (val) => setState(() => _logLevel = val!),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.cloud_download_outlined),
                  title: const Text("Backup Configuration"),
                  subtitle: const Text("Export all settings to ZIP"),
                  onTap: _handleBackup,
                ),
                ListTile(
                  leading: const Icon(Icons.restore_page_outlined),
                  title: const Text("Restore Configuration"),
                  subtitle: const Text("Import settings from ZIP"),
                  onTap: _handleRestore,
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.system_update),
                  title: const Text("Check for Updates"),
                  subtitle: Text("Current: $_appVersion"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                  onTap: widget.onCheckUpdate,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 30),
        ElevatedButton.icon(
          onPressed: _saveSettings,
          icon: const Icon(Icons.save),
          label: const Text("Save Configuration"),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        )
      ],
    );
  }

  Widget _buildTextInput(TextEditingController ctrl, String label, IconData icon) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: AppColors.card,
      ),
    );
  }

  Widget _buildSliderSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            "Hysteria Cores: ${_coreCount.toInt()}",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
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
          child: Text(
            "More cores = Higher speed but more battery usage",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownTile(
    String title,
    String subtitle,
    String value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: DropdownButton<String>(
        value: value,
        items: items
            .map((item) => DropdownMenuItem(
                  value: item,
                  child: Text(item.toUpperCase()),
                ))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}
