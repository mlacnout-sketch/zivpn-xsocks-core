import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final _mtuCtrl = TextEditingController();
  final _pingTargetCtrl = TextEditingController();

  bool _autoTuning = true;
  String _bufferSize = "4m";
  String _logLevel = "info";
  double _coreCount = 4.0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _mtuCtrl.text = prefs.getString('mtu') ?? "1200";
      _pingTargetCtrl.text = prefs.getString('ping_target') ?? "http://www.gstatic.com/generate_204";
      _autoTuning = prefs.getBool('auto_tuning') ?? true;
      _bufferSize = prefs.getString('buffer_size') ?? "4m";
      _logLevel = prefs.getString('log_level') ?? "info";
      _coreCount = (prefs.getInt('core_count') ?? 4).toDouble();
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mtu', _mtuCtrl.text);
    await prefs.setString('ping_target', _pingTargetCtrl.text);
    await prefs.setBool('auto_tuning', _autoTuning);
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
                  title: const Text("TCP Auto Tuning"),
                  subtitle: const Text("Dynamic buffer sizing for stability"),
                  value: _autoTuning,
                  onChanged: (val) => setState(() => _autoTuning = val),
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
            backgroundColor: const Color(0xFF6C63FF),
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
        fillColor: const Color(0xFF272736),
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