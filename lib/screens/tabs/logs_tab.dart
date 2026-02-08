import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app_colors.dart';

class LogsTab extends StatefulWidget {
  final List<String> logs;
  final ScrollController scrollController;

  const LogsTab({
    super.key,
    required this.logs,
    required this.scrollController,
  });

  @override
  State<LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends State<LogsTab> {
  bool _simpleMode = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Live Logs",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(_simpleMode ? Icons.bug_report_outlined : Icons.bug_report),
                    tooltip: _simpleMode ? "Show Debug Logs" : "Show Simple Logs",
                    color: _simpleMode ? Colors.grey : AppColors.primary,
                    onPressed: () {
                      setState(() {
                        _simpleMode = !_simpleMode;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(_simpleMode ? "Simple Mode Enabled" : "Debug Mode Enabled"),
                          duration: const Duration(milliseconds: 500),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_all),
                    tooltip: "Copy All",
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.logs.join("\n")));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("All logs copied")),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_sweep),
                    tooltip: "Clear Logs",
                    onPressed: () {
                      setState(() {
                        widget.logs.clear();
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.logBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: ListView.builder(
              controller: widget.scrollController,
              itemCount: widget.logs.length,
              itemBuilder: (context, index) {
                final log = widget.logs[index];
                
                String message = log;
                Color color = Colors.greenAccent; // Default color
                bool isVisible = true;

                // --- LOGIC PENENTUAN WARNA & FILTERING ---
                if (log.toLowerCase().contains("error") || log.toLowerCase().contains("fail") || log.toLowerCase().contains("refused")) {
                   color = Colors.redAccent;
                } else if (log.toLowerCase().contains("warn")) {
                   color = Colors.orangeAccent;
                } else {
                   color = Colors.white70;
                }

                if (_simpleMode) {
                  // --- SIMPLE MODE: Translate & Hide ---
                  if (color == Colors.redAccent) {
                     // Keep errors, simplify text if possible
                     if (log.contains("handshake")) message = "Connection Handshake Failed";
                     else if (log.contains("timeout")) message = "Connection Timeout";
                     else if (log.contains("refused")) message = "Server Refused Connection";
                  } else {
                     // Non-error logs
                     if (log.contains("[Tun2Socks]")) {
                        if (log.contains("Socks5 UDP")) {
                           isVisible = false; // Noise
                        } else {
                           message = log.replaceAll("[Tun2Socks]", "Tunnel:");
                        }
                     } else if (log.contains("Hysteria")) {
                        // Simplify Hysteria logs
                        message = "Core: Running...";
                        if (log.contains("connected")) message = "Core: Connected to Server";
                     } else if (log.contains("LoadBalancer")) {
                        message = "System: Optimizing Route";
                     } else {
                        // Hide other generic info logs in simple mode unless explicit
                        // isVisible = false; // (Optional: Hide unknown logs?) -> Better keep them but raw
                     }
                  }
                } else {
                  // --- DEBUG MODE: Raw Logs ---
                  // Show everything as is, just with color coding
                }

                if (!isVisible) return const SizedBox.shrink();

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: SelectableText(
                    message,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: color,
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
