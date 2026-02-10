import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import '../../app_colors.dart';
import '../../repositories/backup_repository.dart';

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
  final _udpgwPortCtrl = TextEditingController();

  bool _autoTuning = true;
  bool _cpuWakelock = false;
  bool _enableUdpgw = true;
  String _bufferSize = "4m";
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
      _mtuCtrl.text = prefs.getString('mtu') ?? "1200";
      _pingTargetCtrl.text = prefs.getString('ping_target') ?? "http://www.gstatic.com/generate_204";
      _udpgwPortCtrl.text = prefs.getString('udpgw_port') ?? "7300";
      _autoTuning = prefs.getBool('auto_tuning') ?? true;
      _cpuWakelock = prefs.getBool('cpu_wakelock') ?? false;
      _enableUdpgw = prefs.getBool('enable_udpgw') ?? true;
      _bufferSize = prefs.getString('buffer_size') ?? "4m";
      _logLevel = prefs.getString('log_level') ?? "info";
      _coreCount = (prefs.getInt('core_count') ?? 4).toDouble();
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mtu', _mtuCtrl.text);
    await prefs.setString('ping_target', _pingTargetCtrl.text);
    await prefs.setString('udpgw_port', _udpgwPortCtrl.text);
    await prefs.setBool('auto_tuning', _autoTuning);
    await prefs.setBool('cpu_wakelock', _cpuWakelock);
    await prefs.setBool('enable_udpgw', _enableUdpgw);
    await prefs.setString('buffer_size', _bufferSize);
    await prefs.setString('log_level', _logLevel);
    await prefs.setInt('core_count', _coreCount.toInt());

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
                const SizedBox(height: 16),
                _buildTextInput(
                  _pingTargetCtrl,
                  "Ping Destination (URL/IP)",
                  Icons.network_check,
                ),
                const SizedBox(height: 20),
                _buildSliderSection(),
                const Divider(),
                SwitchListTile(
                  title: const Text("CPU Wakelock"),
                  subtitle: const Text("Prevent CPU sleep (High Battery Usage)"),
                  value: _cpuWakelock,
                  onChanged: (val) => setState(() => _cpuWakelock = val),
                ),
                SwitchListTile(
                  title: const Text("TCP Auto Tuning"),
                  subtitle: const Text("Dynamic buffer sizing for stability"),
                  value: _autoTuning,
                  onChanged: (val) => setState(() => _autoTuning = val),
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text("Enable UDPGW"),
                  subtitle: const Text("Allow UDP traffic (Gaming/VOIP)"),
                  value: _enableUdpgw,
                  onChanged: (val) => setState(() => _enableUdpgw = val),
                ),
                if (_enableUdpgw)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: _buildTextInput(
                      _udpgwPortCtrl,
                      "UDPGW Port (Default: 7300)",
                      Icons.door_sliding,
                    ),
                  ),
                const Divider(),
                _buildDropdownTile(
                  "TCP Buffer Size",
                  "Max window size per connection",
                  _bufferSize,
                  ["1m", "2m", "4m", "8m"],
                  (val) => setState(() => _bufferSize = val!),
                ),
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
