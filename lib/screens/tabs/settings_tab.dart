import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final _pdnsdPortCtrl = TextEditingController();
  final _pdnsdCacheCtrl = TextEditingController();
  final _pdnsdTimeoutCtrl = TextEditingController();
  final _pdnsdMinTtlCtrl = TextEditingController();
  final _pdnsdMaxTtlCtrl = TextEditingController();
  final _pdnsdVerbosityCtrl = TextEditingController();
  final _hysteriaRecvWinCtrl = TextEditingController();
  final _hysteriaConnCtrl = TextEditingController();

  bool _cpuWakelock = false;
  bool _enableUdpgw = true;
  bool _udpgwTransparentDns = false;
  bool _filterApps = false;
  bool _bypassMode = false;
  String _logLevel = 'info';
  String _nativePerfProfile = 'balanced';
  String _pdnsdQueryMethod = 'tcp_only';
  double _coreCount = 4.0;
  String _appVersion = 'Unknown';

  final _backupRepo = BackupRepository();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadVersion();
  }

  @override
  void dispose() {
    _mtuCtrl.dispose();
    _pingTargetCtrl.dispose();
    _pingIntervalCtrl.dispose();
    _udpgwPortCtrl.dispose();
    _udpgwMaxConnCtrl.dispose();
    _udpgwBufSizeCtrl.dispose();
    _dnsCtrl.dispose();
    _appsListCtrl.dispose();
    _tcpSndBufCtrl.dispose();
    _tcpWndCtrl.dispose();
    _socksBufCtrl.dispose();
    _pdnsdPortCtrl.dispose();
    _pdnsdCacheCtrl.dispose();
    _pdnsdTimeoutCtrl.dispose();
    _pdnsdMinTtlCtrl.dispose();
    _pdnsdMaxTtlCtrl.dispose();
    _pdnsdVerbosityCtrl.dispose();
    _hysteriaRecvWinCtrl.dispose();
    _hysteriaConnCtrl.dispose();
    super.dispose();
  }

  Future<void> _openAppSelector() async {
    final currentList = _appsListCtrl.text
        .split('\n')
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
      setState(() => _appsListCtrl.text = result.join('\n'));
    }
  }

  Future<void> _handleBackup() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Creating backup...')),
    );
    final file = await _backupRepo.createBackup();
    if (file != null && mounted) {
      await Share.shareXFiles([XFile(file.path)], text: 'MiniZIVPN Config Backup');
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup failed')),
      );
    }
  }

  Future<void> _handleRestore() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result != null && result.files.single.path != null) {
      final success = await _backupRepo.restoreBackup(File(result.files.single.path!));
      if (mounted && success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Restore successful.')),
        );
        _loadSettings();
        widget.onRestoreSuccess?.call();
      }
    }
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = 'v${info.version}');
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _mtuCtrl.text = (prefs.getInt('mtu') ?? 1500).toString();
      _pingTargetCtrl.text = prefs.getString('ping_target') ?? 'http://www.gstatic.com/generate_204';
      _pingIntervalCtrl.text = (prefs.getInt('ping_interval') ?? 3).toString();
      _udpgwPortCtrl.text = prefs.getString('udpgw_port') ?? '7300';
      _udpgwMaxConnCtrl.text = prefs.getString('udpgw_max_connections') ?? '512';
      _udpgwBufSizeCtrl.text = prefs.getString('udpgw_buffer_size') ?? '32';
      _dnsCtrl.text = prefs.getString('upstream_dns') ?? '8.8.8.8';
      _appsListCtrl.text = prefs.getString('apps_list') ?? '';
      _tcpSndBufCtrl.text = prefs.getString('tcp_snd_buf') ?? '65535';
      _tcpWndCtrl.text = prefs.getString('tcp_wnd') ?? '65535';
      _socksBufCtrl.text = prefs.getString('socks_buf') ?? '65536';
      _pdnsdPortCtrl.text = (prefs.getInt('pdnsd_port') ?? 8091).toString();
      _pdnsdCacheCtrl.text = (prefs.getInt('pdnsd_cache_entries') ?? 2048).toString();
      _pdnsdTimeoutCtrl.text = (prefs.getInt('pdnsd_timeout_sec') ?? 10).toString();
      _pdnsdMinTtlCtrl.text = prefs.getString('pdnsd_min_ttl') ?? '15m';
      _pdnsdMaxTtlCtrl.text = prefs.getString('pdnsd_max_ttl') ?? '1w';
      _pdnsdVerbosityCtrl.text = (prefs.getInt('pdnsd_verbosity') ?? 2).toString();
      _hysteriaRecvWinCtrl.text = prefs.getString('hysteria_recv_window') ?? '327680';
      _hysteriaConnCtrl.text = prefs.getString('hysteria_recv_conn') ?? '131072';

      _cpuWakelock = prefs.getBool('cpu_wakelock') ?? false;
      _enableUdpgw = prefs.getBool('enable_udpgw') ?? true;
      _udpgwTransparentDns = prefs.getBool('udpgw_transparent_dns') ?? false;
      _filterApps = prefs.getBool('filter_apps') ?? false;
      _bypassMode = prefs.getBool('bypass_mode') ?? false;
      _logLevel = prefs.getString('log_level') ?? 'info';
      _nativePerfProfile = prefs.getString('native_perf_profile') ?? 'balanced';
      _pdnsdQueryMethod = prefs.getString('pdnsd_query_method') ?? 'tcp_only';
      _coreCount = (prefs.getInt('core_count') ?? 4).toDouble();
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    String val(TextEditingController c, String d) => c.text.isEmpty ? d : c.text;

    await prefs.setInt('mtu', int.tryParse(val(_mtuCtrl, '1500')) ?? 1500);
    await prefs.setString('ping_target', val(_pingTargetCtrl, 'http://www.gstatic.com/generate_204'));
    await prefs.setInt('ping_interval', int.tryParse(val(_pingIntervalCtrl, '3')) ?? 3);
    await prefs.setString('udpgw_port', val(_udpgwPortCtrl, '7300'));
    await prefs.setString('udpgw_max_connections', val(_udpgwMaxConnCtrl, '512'));
    await prefs.setString('udpgw_buffer_size', val(_udpgwBufSizeCtrl, '32'));
    await prefs.setString('upstream_dns', val(_dnsCtrl, '8.8.8.8'));
    await prefs.setString('apps_list', _appsListCtrl.text);
    await prefs.setString('tcp_snd_buf', val(_tcpSndBufCtrl, '65535'));
    await prefs.setString('tcp_wnd', val(_tcpWndCtrl, '65535'));
    await prefs.setString('socks_buf', val(_socksBufCtrl, '65536'));
    await prefs.setInt('pdnsd_port', int.tryParse(val(_pdnsdPortCtrl, '8091')) ?? 8091);
    await prefs.setInt('pdnsd_cache_entries', int.tryParse(val(_pdnsdCacheCtrl, '2048')) ?? 2048);
    await prefs.setInt('pdnsd_timeout_sec', int.tryParse(val(_pdnsdTimeoutCtrl, '10')) ?? 10);
    await prefs.setString('pdnsd_min_ttl', val(_pdnsdMinTtlCtrl, '15m'));
    await prefs.setString('pdnsd_max_ttl', val(_pdnsdMaxTtlCtrl, '1w'));
    await prefs.setInt('pdnsd_verbosity', int.tryParse(val(_pdnsdVerbosityCtrl, '2')) ?? 2);
    await prefs.setString('hysteria_recv_window', val(_hysteriaRecvWinCtrl, '327680'));
    await prefs.setString('hysteria_recv_conn', val(_hysteriaConnCtrl, '131072'));

    await prefs.setBool('cpu_wakelock', _cpuWakelock);
    await prefs.setBool('enable_udpgw', _enableUdpgw);
    await prefs.setBool('udpgw_transparent_dns', _udpgwTransparentDns);
    await prefs.setBool('filter_apps', _filterApps);
    await prefs.setBool('bypass_mode', _bypassMode);
    await prefs.setString('log_level', _logLevel);
    await prefs.setString('native_perf_profile', _nativePerfProfile);
    await prefs.setString('pdnsd_query_method', _pdnsdQueryMethod);
    await prefs.setInt('core_count', _coreCount.toInt());

    _loadSettings();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings Saved')),
      );
    }
  }

  void _applyPreset(String value) {
    if (value == 'throughput') {
      _tcpSndBufCtrl.text = '65535';
      _tcpWndCtrl.text = '65535';
      _socksBufCtrl.text = '131072';
      _udpgwMaxConnCtrl.text = '1024';
      _udpgwBufSizeCtrl.text = '64';
      _pdnsdCacheCtrl.text = '4096';
      _pdnsdTimeoutCtrl.text = '8';
      _pdnsdVerbosityCtrl.text = '1';
      _hysteriaRecvWinCtrl.text = '655360';
      _hysteriaConnCtrl.text = '262144';
      _dnsCtrl.text = '9.9.9.9'; // Quad9 for security/throughput balance
    } else if (value == 'latency') {
      _tcpSndBufCtrl.text = '32768';
      _tcpWndCtrl.text = '32768';
      _socksBufCtrl.text = '65536';
      _udpgwMaxConnCtrl.text = '256';
      _udpgwBufSizeCtrl.text = '16';
      _pdnsdCacheCtrl.text = '2048';
      _pdnsdTimeoutCtrl.text = '5';
      _pdnsdVerbosityCtrl.text = '1';
      _hysteriaRecvWinCtrl.text = '163840';
      _hysteriaConnCtrl.text = '65536';
      _dnsCtrl.text = '1.1.1.1'; // Cloudflare for speed
    } else if (value == 'balanced') {
      _tcpSndBufCtrl.text = '65535';
      _tcpWndCtrl.text = '65535';
      _socksBufCtrl.text = '65536';
      _udpgwMaxConnCtrl.text = '512';
      _udpgwBufSizeCtrl.text = '32';
      _pdnsdCacheCtrl.text = '2048';
      _pdnsdTimeoutCtrl.text = '10';
      _pdnsdVerbosityCtrl.text = '2';
      _hysteriaRecvWinCtrl.text = '327680';
      _hysteriaConnCtrl.text = '131072';
      _dnsCtrl.text = '8.8.8.8'; // Google for reliability
    }
  }

  void _onConfigChanged(String _) {
    if (_nativePerfProfile != 'custom') {
      setState(() => _nativePerfProfile = 'custom');
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Core Settings', style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          'Sesuaikan konfigurasi core agar stabil dengan sistem perangkat.',
          style: textTheme.bodyMedium?.copyWith(color: Colors.grey.shade400),
        ),
        const SizedBox(height: 20),
        _buildSectionCard(
          title: 'Network',
          icon: Icons.network_check,
          children: [
            _buildTextInput(_mtuCtrl, 'MTU (Default: 1500)', Icons.settings_ethernet),
            _buildTextInput(_pingIntervalCtrl, 'Check Interval (sec)', Icons.timer),
            _buildTextInput(
              _pingTargetCtrl,
              'Target Ping (URL/IP)',
              Icons.network_ping,
              isNumber: false,
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Forward UDP'),
              value: _enableUdpgw,
              onChanged: (val) => setState(() => _enableUdpgw = val),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('UDPGW Transparent DNS'),
              subtitle: const Text('Tambahkan --udpgw-transparent-dns di tun2socks'),
              value: _udpgwTransparentDns,
              onChanged: (val) => setState(() => _udpgwTransparentDns = val),
            ),
            if (_enableUdpgw) ...[
              _buildTextInput(_udpgwPortCtrl, 'Udp Gateway Port', Icons.door_sliding),
              _buildTextInput(_udpgwMaxConnCtrl, 'Max UDP Connections', Icons.connect_without_contact, onChanged: _onConfigChanged),
              _buildTextInput(_udpgwBufSizeCtrl, 'UDP Buffer (Packets)', Icons.shopping_bag, onChanged: _onConfigChanged),
            ],
          ],
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: 'App Filter',
          icon: Icons.apps,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Filter Apps'),
              value: _filterApps,
              onChanged: (val) => setState(() => _filterApps = val),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Bypass Mode'),
              value: _bypassMode,
              onChanged: (val) => setState(() => _bypassMode = val),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.checklist),
              title: const Text('Pilih Aplikasi'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openAppSelector,
            ),
            TextField(
              controller: _appsListCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Apps List (Package names)',
                prefixIcon: const Icon(Icons.list),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: AppColors.card,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: 'Advanced',
          icon: Icons.tune,
          children: [
            _buildSliderSection(),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('CPU Wakelock'),
              value: _cpuWakelock,
              onChanged: (val) => setState(() => _cpuWakelock = val),
            ),
            _buildTextInput(_tcpSndBufCtrl, 'TCP Send Buffer', Icons.upload_file, onChanged: _onConfigChanged),
            _buildTextInput(_tcpWndCtrl, 'TCP Window Size', Icons.download_for_offline, onChanged: _onConfigChanged),
            _buildTextInput(_socksBufCtrl, 'SOCKS Buffer', Icons.memory, onChanged: _onConfigChanged),
            _buildTextInput(_hysteriaRecvWinCtrl, 'Hysteria Recv Window', Icons.speed, onChanged: _onConfigChanged),
            _buildTextInput(_hysteriaConnCtrl, 'Hysteria Recv Win Conn', Icons.network_check, onChanged: _onConfigChanged),
            
            // DNS Selector
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: 'DNS Preset',
                prefixIcon: const Icon(Icons.dns_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: AppColors.card,
              ),
              value: null,
              hint: const Text('Pilih DNS Preset...'),
              items: const [
                DropdownMenuItem(value: '8.8.8.8', child: Text('Google (8.8.8.8)')),
                DropdownMenuItem(value: '1.1.1.1', child: Text('Cloudflare (1.1.1.1)')),
                DropdownMenuItem(value: '9.9.9.9', child: Text('Quad9 (9.9.9.9)')),
                DropdownMenuItem(value: '94.140.14.14', child: Text('AdGuard (94.140.14.14)')),
                DropdownMenuItem(value: '208.67.222.222', child: Text('OpenDNS (208.67.222.222)')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() => _dnsCtrl.text = val);
                }
              },
            ),
            const SizedBox(height: 8),
            _buildTextInput(_dnsCtrl, 'Upstream DNS (Custom IP)', Icons.dns, isNumber: false),

            _buildDropdownTile(
              'Native Performance Profile',
              'Preset tuning tun2socks + pdnsd',
              _nativePerfProfile,
              const ['balanced', 'throughput', 'latency', 'custom', 'smart'],
              (val) {
                setState(() => _nativePerfProfile = val!);
                _applyPreset(val!);
              },
            ),
            _buildDropdownTile(
              'Log Level',
              'Verbosity',
              _logLevel,
              const ['debug', 'info', 'error', 'silent'],
              (val) => setState(() => _logLevel = val!),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: 'PDNSD Tuning',
          icon: Icons.storage,
          children: [
            _buildTextInput(_pdnsdPortCtrl, 'PDNSD Listen Port', Icons.numbers),
            _buildTextInput(_pdnsdCacheCtrl, 'PDNSD Cache Entries', Icons.storage, onChanged: _onConfigChanged),
            _buildTextInput(_pdnsdTimeoutCtrl, 'PDNSD Timeout (sec)', Icons.timer_outlined, onChanged: _onConfigChanged),
            _buildTextInput(_pdnsdMinTtlCtrl, 'PDNSD Min TTL (contoh: 15m)', Icons.hourglass_top, isNumber: false),
            _buildTextInput(_pdnsdMaxTtlCtrl, 'PDNSD Max TTL (contoh: 1w)', Icons.hourglass_bottom, isNumber: false),
            _buildTextInput(_pdnsdVerbosityCtrl, 'PDNSD Verbosity (0-3)', Icons.tune, onChanged: _onConfigChanged),
            _buildDropdownTile(
              'PDNSD Query Method',
              'tcp_only biasanya paling aman untuk tunnel',
              _pdnsdQueryMethod,
              const ['tcp_only', 'udp_only', 'udp_tcp'],
              (val) => setState(() => _pdnsdQueryMethod = val!),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: 'System',
          icon: Icons.settings_suggest,
          children: [
            _buildActionTile(
              icon: Icons.cloud_download_outlined,
              title: 'Backup Configuration',
              onTap: _handleBackup,
            ),
            _buildActionTile(
              icon: Icons.restore_page_outlined,
              title: 'Restore Configuration',
              onTap: _handleRestore,
            ),
            _buildActionTile(
              icon: Icons.system_update,
              title: 'Check for Updates',
              subtitle: 'Current: $_appVersion',
              onTap: widget.onCheckUpdate,
            ),
          ],
        ),
        const SizedBox(height: 30),
        ElevatedButton.icon(
          onPressed: _saveSettings,
          icon: const Icon(Icons.save),
          label: const Text('Save Configuration'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        )
      ],
    );
  }

  Widget _buildTextInput(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool isNumber = true,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: ctrl,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: AppColors.card,
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
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
            'Hysteria Cores: ${_coreCount.toInt()}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Slider(
          value: _coreCount,
          min: 1,
          max: 8,
          divisions: 7,
          label: '${_coreCount.toInt()} Cores',
          onChanged: (val) => setState(() => _coreCount = val),
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
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: DropdownButton<String>(
        value: value,
        items: items
            .map((item) => DropdownMenuItem(value: item, child: Text(item.toUpperCase())))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
