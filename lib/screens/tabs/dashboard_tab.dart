import 'package:flutter/material.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class DashboardTab extends StatefulWidget {
  final String vpnState; // "disconnected", "connecting", "connected"
  final VoidCallback onToggle;
  final String dl;
  final String ul;
  final String duration;
  final int sessionRx;
  final int sessionTx;

  const DashboardTab({
    super.key,
    required this.vpnState,
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

    String result = "Error";
    try {
      // Enforce 10s hard timeout for the entire operation
      result = await _performPingLogic().timeout(const Duration(seconds: 10), onTimeout: () {
        return "Timeout";
      });
    } catch (e) {
      result = "Error";
    } finally {
      if (mounted) {
        setState(() {
          _isPinging = false;
          _pingResult = result;
        });
        _pingAnimCtrl.stop();
        _pingAnimCtrl.reset();
      }
    }
  }

  Future<String> _performPingLogic() async {
    final prefs = await SharedPreferences.getInstance();
    String target = prefs.getString('ping_target') ?? "http://www.gstatic.com/generate_204";
    
    if (!target.startsWith("http")) {
      target = "http://$target";
    }

    final stopwatch = Stopwatch()..start();

    try {
      // 1. Try HTTP
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 5);
        final request = await client.getUrl(Uri.parse(target));
        final response = await request.close();
        
        if (response.statusCode == 204 || response.statusCode == 200) {
          stopwatch.stop();
          return "${stopwatch.elapsedMilliseconds} ms";
        }
      } catch (_) {}

      // 2. Fallback to ICMP
      final cleanTarget = target.replaceAll(RegExp(r'^https?://'), '').split('/')[0];
      final proc = await Process.run('ping', ['-c', '1', '-W', '2', cleanTarget]);
      stopwatch.stop();
      
      if (proc.exitCode == 0) {
         final match = RegExp(r"time=([0-9\.]+) ms").firstMatch(proc.stdout.toString());
         if (match != null) return "${match.group(1)} ms";
      }
      return "Timeout";
    } catch (_) {
      return "Error";
    }
  }

  Color _getPingColor(String result) {
    if (result.contains("Error") || result.contains("Timeout") || result.contains("HTTP")) {
      return Colors.redAccent;
    }
    try {
      final msString = result.split(' ')[0];
      final ms = double.tryParse(msString);
      if (ms != null) {
        if (ms < 150) return Colors.greenAccent;
        if (ms < 300) return Colors.orangeAccent;
      }
    } catch (_) {}
    return Colors.redAccent;
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
    bool isConnected = widget.vpnState == "connected";
    bool isConnecting = widget.vpnState == "connecting";
    Color statusColor = isConnected ? const Color(0xFF6C63FF) : (isConnecting ? Colors.orange : const Color(0xFF272736));

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
                    onTap: isConnecting ? null : widget.onToggle,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      width: 220,
                      height: 240,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor,
                        boxShadow: [
                          BoxShadow(
                            color: (isConnected ? const Color(0xFF6C63FF) : Colors.black)
                                .withValues(alpha: 0.4),
                            blurRadius: 30,
                            spreadRadius: 10,
                          )
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (isConnecting)
                            const SizedBox(
                              width: 64, 
                              height: 64, 
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)
                            )
                          else
                            Icon(
                              isConnected ? Icons.vpn_lock : Icons.power_settings_new,
                              size: 64,
                              color: Colors.white,
                            ),
                          const SizedBox(height: 15),
                          Text(
                            isConnecting ? "CONNECTING..." : (isConnected ? "CONNECTED" : "TAP TO CONNECT"),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          if (isConnected) ...[
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
                if (isConnected)
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
                                color: _getPingColor(_pingResult),
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