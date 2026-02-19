import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app_colors.dart';
import '../../services/autopilot_service.dart';
import '../../models/autopilot_state.dart';
import '../../models/autopilot_config.dart';
import '../../models/ping_log_entry.dart';

class AutoPilotTab extends StatefulWidget {
  const AutoPilotTab({super.key});

  @override
  State<AutoPilotTab> createState() => _AutoPilotTabState();
}

class _AutoPilotTabState extends State<AutoPilotTab> {
  final _service = AutoPilotService();
  bool _isStarting = false;
  final List<String> _activityLogs = [];
  String? _lastStateMessage;

  @override
  void initState() {
    super.initState();
    // In actual app, the service should already be initialized in main
  }

  void _handleStateLog(AutoPilotState state) {
    final message = state.message?.trim();
    if (message == null || message.isEmpty || message == _lastStateMessage) return;

    _lastStateMessage = message;
    final now = DateTime.now();
    final timeLabel = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
    final entry = "[$timeLabel] $message";

    setState(() {
      _activityLogs.insert(0, entry);
      if (_activityLogs.length > 15) _activityLogs.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AutoPilotState>(
      stream: _service.stateStream,
      initialData: _service.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? _service.currentState;
        _handleStateLog(state);
        final isRunning = state.status != AutoPilotStatus.idle && state.status != AutoPilotStatus.stopped;

        return Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.radar, color: AppColors.primary),
                    SizedBox(width: 8),
                    Text(
                      "lexpesawat (AutoPilot)",
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildStatusCard(state),
                const SizedBox(height: 16),
                _buildControlCard(isRunning),
                const SizedBox(height: 24),
                _buildActivityLog(),
                const SizedBox(height: 24),
                const Text("Settings", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
                const SizedBox(height: 12),
                _buildMonitoringSettings(),
                const SizedBox(height: 16),
                _buildRecoverySettings(),
                const SizedBox(height: 16),
                _buildConnectionStatus(state),
                const SizedBox(height: 30),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusCard(AutoPilotState state) {
    Color color;
    IconData icon;
    String label;

    switch (state.status) {
      case AutoPilotStatus.idle:
      case AutoPilotStatus.stopped: color = Colors.grey; icon = Icons.stop_circle_outlined; label = "IDLE"; break;
      case AutoPilotStatus.running:
      case AutoPilotStatus.monitoring: color = Colors.green; icon = Icons.radar; label = "RUNNING"; break;
      case AutoPilotStatus.checking: color = Colors.blue; icon = Icons.sync; label = "CHECKING..."; break;
      case AutoPilotStatus.recovering:
      case AutoPilotStatus.resetting: color = Colors.orange; icon = Icons.airplane_ticket; label = "RECOVERING"; break;
      case AutoPilotStatus.stabilizing: color = Colors.purple; icon = Icons.bolt; label = "STABILIZING"; break;
      case AutoPilotStatus.error: color = Colors.red; icon = Icons.error_outline; label = "ERROR"; break;
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, size: 56, color: color),
            const SizedBox(height: 12),
            Text(label, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
            if (state.message != null) ...[
              const SizedBox(height: 8),
              Text(state.message!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildControlCard(bool isRunning) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isStarting ? null : (isRunning ? _stop : _start),
            icon: Icon(isRunning ? Icons.stop : Icons.play_arrow, size: 28),
            label: Text(isRunning ? "STOP AUTOPILOT" : "START AUTOPILOT", style: const TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: isRunning ? Colors.redAccent : AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActivityLog() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.receipt_long_rounded, size: 20, color: AppColors.primary),
                SizedBox(width: 8),
                Text('Activity Log', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            if (_activityLogs.isEmpty)
              const Text('No activity yet. Start AutoPilot to monitor connection.', style: TextStyle(color: Colors.white54, fontSize: 12))
            else
              SizedBox(
                height: 150,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _activityLogs.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(_activityLogs[index], style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white70)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonitoringSettings() {
    final cfg = _service.config;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sliderSetting(
              title: "Check Interval",
              desc: "Time between internet checks",
              val: cfg.checkIntervalSeconds.toDouble(),
              min: 5, max: 60, div: 11, unit: "s",
              onChanged: (v) => _updateCfg(cfg.copyWith(checkIntervalSeconds: v.toInt())),
            ),
            const Divider(height: 32),
            _sliderSetting(
              title: "Ping Timeout",
              desc: "Max wait for each check",
              val: cfg.connectionTimeoutSeconds.toDouble(),
              min: 2, max: 15, div: 13, unit: "s",
              onChanged: (v) => _updateCfg(cfg.copyWith(connectionTimeoutSeconds: v.toInt())),
            ),
            const Divider(height: 32),
            const Text("Ping Destination", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                hintText: "http://google.com",
                isDense: true,
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: cfg.pingDestination),
              onSubmitted: (v) => _updateCfg(cfg.copyWith(pingDestination: v)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecoverySettings() {
    final cfg = _service.config;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sliderSetting(
              title: "Max Fail Count",
              desc: "Fails before triggering reset",
              val: cfg.maxFailCount.toDouble(),
              min: 1, max: 10, div: 9, unit: "x",
              onChanged: (v) => _updateCfg(cfg.copyWith(maxFailCount: v.toInt())),
            ),
            const Divider(height: 32),
            _sliderSetting(
              title: "Reset Duration",
              desc: "Time to stay in Airplane Mode",
              val: cfg.airplaneModeDelaySeconds.toDouble(),
              min: 1, max: 10, div: 9, unit: "s",
              onChanged: (v) => _updateCfg(cfg.copyWith(airplaneModeDelaySeconds: v.toInt())),
            ),
            const Divider(height: 32),
            _sliderSetting(
              title: "Recovery Wait",
              desc: "Time to wait for signal latch",
              val: cfg.recoveryWaitSeconds.toDouble(),
              min: 5, max: 30, div: 5, unit: "s",
              onChanged: (v) => _updateCfg(cfg.copyWith(recoveryWaitSeconds: v.toInt())),
            ),
            const Divider(height: 32),
            SwitchListTile(
              title: const Text("Ping Stabilizer", style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text("Downloads data to wake up connection"),
              value: cfg.enablePingStabilizer,
              activeColor: AppColors.primary,
              onChanged: (v) => _updateCfg(cfg.copyWith(enablePingStabilizer: v)),
            ),
            if (cfg.enablePingStabilizer)
              _sliderSetting(
                title: "Stabilizer Size",
                desc: "Total dummy data to download",
                val: cfg.stabilizerSizeMb.toDouble(),
                min: 1, max: 10, div: 9, unit: "MB",
                onChanged: (v) => _updateCfg(cfg.copyWith(stabilizerSizeMb: v.toInt())),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sliderSetting({required String title, required String desc, required double val, required double min, required double max, required int div, required String unit, required ValueChanged<double> onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(desc, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
              child: Text("${val.toInt()}$unit", style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
            )
          ],
        ),
        Slider(
          value: val, min: min, max: max, divisions: div,
          activeColor: AppColors.primary,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildConnectionStatus(AutoPilotState state) {
    return Card(
      color: state.hasInternet ? Colors.green.withValues(alpha: 0.05) : Colors.red.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(state.hasInternet ? Icons.wifi : Icons.wifi_off, color: state.hasInternet ? Colors.green : Colors.red),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(state.hasInternet ? "CONNECTED" : "OFFLINE", style: const TextStyle(fontWeight: FontWeight.bold)),
                if (state.failCount > 0) Text("Attempts: ${state.failCount}/${_service.config.maxFailCount}", style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
              ],
            )
          ],
        ),
      ),
    );
  }

  void _start() async {
    setState(() => _isStarting = true);
    try {
      await _service.start();
    } catch (e) {
      if (e.toString().contains("Shizuku")) _showShizukuTutorial();
      else ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  void _stop() => _service.stop();

  void _updateCfg(AutoPilotConfig newCfg) {
    _service.updateConfig(newCfg);
    setState(() {});
  }

  void _showShizukuTutorial() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Shizuku Required"),
        content: const Text("Shizuku service is not running or authorized. Please open Shizuku app and start it."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("OK")),
          ElevatedButton(onPressed: () => launchUrl(Uri.parse("https://shizuku.rikka.app/")), child: const Text("GET SHIZUKU")),
        ],
      ),
    );
  }
}
