import 'package:flutter/material.dart';

class DashboardTab extends StatelessWidget {
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
            child: Center(
              child: GestureDetector(
                onTap: onToggle,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  width: 220,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isRunning ? const Color(0xFF6C63FF) : const Color(0xFF272736),
                    boxShadow: [
                      BoxShadow(
                        color: (isRunning ? const Color(0xFF6C63FF) : Colors.black)
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
                        isRunning ? Icons.vpn_lock : Icons.power_settings_new,
                        size: 64,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 15),
                      Text(
                        isRunning ? "CONNECTED" : "TAP TO CONNECT",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (isRunning) ...[
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
                            duration,
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
                  "Session: ${_formatTotalBytes(sessionRx + sessionTx)}",
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Container(width: 1, height: 12, color: Colors.white10),
                Text(
                  "Rx: ${_formatTotalBytes(sessionRx)}",
                  style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
                ),
                Container(width: 1, height: 12, color: Colors.white10),
                Text(
                  "Tx: ${_formatTotalBytes(sessionTx)}",
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
                  value: dl,
                  icon: Icons.download,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: StatCard(
                  label: "Upload",
                  value: ul,
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
