import 'package:flutter/material.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class DashboardTab extends StatefulWidget {
  final bool isRunning;
  final VoidCallback onToggle;
  final String dl;
  final String ul;
  final String duration;
  final int sessionRx;
  final int sessionTx;

  const DashboardTab({
    super.key,
    required this.isRunning,
    required this.onToggle,
    required this.dl,
    required this.ul,
    required this.duration,
    required this.sessionRx,
    required this.sessionTx,
  });

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> with SingleTickerProviderStateMixin {
  String _pingResult = "";
  bool _isPinging = false;
  late AnimationController _pingAnimCtrl;

  @override
  void initState() {
    super.initState();
    _pingAnimCtrl = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _pingAnimCtrl.dispose();
    super.dispose();
  }

  Future<void> _doPing() async {
    if (_isPinging) return;

    setState(() {
      _isPinging = true;
      _pingResult = "Pinging...";
    });
    _pingAnimCtrl.repeat();

    final prefs = await SharedPreferences.getInstance();
    final target = prefs.getString('ping_target') ?? "http://www.gstatic.com/generate_204";

    final stopwatch = Stopwatch()..start();
    String result = "Error";

    try {
      if (target.startsWith("http")) {
        // Use HTTP Real Ping (Generate 204)
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 5);
        final request = await client.getUrl(Uri.parse(target));
        final response = await request.close();
        stopwatch.stop();

        if (response.statusCode == 204 || response.statusCode == 200) {
          result = "${stopwatch.elapsedMilliseconds} ms";
        } else {
          result = "HTTP ${response.statusCode}";
        }
      } else {
        // Fallback to ICMP
        final proc = await Process.run('ping', ['-c', '1', '-W', '2', target]);
        stopwatch.stop();
        if (proc.exitCode == 0) {
           final match = RegExp(r"time=([0-9\.]+) ms").firstMatch(proc.stdout.toString());
           if (match != null) result = "${match.group(1)} ms";
        } else {
           result = "Timeout";
        }
      }
    } catch (_) {
      result = "Error";
    }

    if (mounted) {
      setState(() {
        _isPinging = false;
        _pingResult = result;
      });
      _pingAnimCtrl.stop();
      _pingAnimCtrl.reset();
    }
  }

  String _formatTotalBytes(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    if (bytes < 1024 * 1024 * 1024) {
      return "${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB";
    }
    return "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB";
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "ZIVPN",
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const Text("Turbo Tunnel Engine", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: GestureDetector(
                    onTap: widget.onToggle,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      width: 220,
                      height: 240,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.isRunning ? const Color(0xFF6C63FF) : const Color(0xFF272736),
                        boxShadow: [
                          BoxShadow(
                            color: (widget.isRunning ? const Color(0xFF6C63FF) : Colors.black)
                                .withValues(alpha: 0.4),
                            blurRadius: 30,
                            spreadRadius: 10,
                          )
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            widget.isRunning ? Icons.vpn_lock : Icons.power_settings_new,
                            size: 64,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 15),
                          Text(
                            widget.isRunning ? "CONNECTED" : "TAP TO CONNECT",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          if (widget.isRunning) ...[
                            const SizedBox(height: 15),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Text(
                                widget.duration,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          ]
                        ],
                      ),
                    ),
                  ),
                ),
                // Ping Button & Result
                if (widget.isRunning)
                  Positioned(
                    bottom: 20,
                    right: 20,
                    child: Column(
                      children: [
                        FloatingActionButton.small(
                          onPressed: _doPing,
                          backgroundColor: const Color(0xFF272736),
                          child: RotationTransition(
                            turns: _pingAnimCtrl,
                            child: Icon(
                              Icons.flash_on,
                              color: _isPinging ? Colors.yellow : const Color(0xFF6C63FF),
                            ),
                          ),
                        ),
                        if (_pingResult.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _pingResult,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _pingResult.contains("ms") 
                                    ? (int.tryParse(_pingResult.split(' ')[0]) ?? 999) < 150 
                                        ? Colors.greenAccent 
                                        : Colors.orangeAccent
                                    : Colors.redAccent,
                              ),
                            ),
                          ),
                        ]
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 15),
            decoration: BoxDecoration(
              color: const Color(0xFF272736),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text(
                  "Session: ${_formatTotalBytes(widget.sessionRx + widget.sessionTx)}",
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Container(width: 1, height: 12, color: Colors.white10),
                Text(
                  "Rx: ${_formatTotalBytes(widget.sessionRx)}",
                  style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
                ),
                Container(width: 1, height: 12, color: Colors.white10),
                Text(
                  "Tx: ${_formatTotalBytes(widget.sessionTx)}",
                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: "Download",
                  value: widget.dl,
                  icon: Icons.download,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: StatCard(
                  label: "Upload",
                  value: widget.ul,
                  icon: Icons.upload,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

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
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          )
        ],
      ),
    );
  }
}