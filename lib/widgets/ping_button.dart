import 'package:flutter/material.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class PingButton extends StatefulWidget {
  const PingButton({super.key});

  @override
  State<PingButton> createState() => _PingButtonState();
}

class _PingButtonState extends State<PingButton> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  final ValueNotifier<String> _result = ValueNotifier("");
  bool _isPinging = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    _result.dispose();
    super.dispose();
  }

  Future<void> _doPing() async {
    if (_isPinging) return;

    _isPinging = true;
    _result.value = "Pinging...";
    _animController.repeat();

    try {
      final res = await _performPing().timeout(
        const Duration(seconds: 15), 
        onTimeout: () => "Timeout"
      );
      if (mounted) _result.value = res;
    } catch (e) {
      if (mounted) _result.value = "Error";
    } finally {
      if (mounted) {
        _isPinging = false;
        _animController.stop();
        _animController.reset();
      }
    }
  }

  Future<String> _performPing() async {
    final prefs = await SharedPreferences.getInstance();
    String target = (prefs.getString('ping_target') ?? "http://clients3.google.com/generate_204").trim();
    
    if (target.isEmpty) target = "http://clients3.google.com/generate_204";
    if (!target.startsWith("http")) target = "http://$target";

    final stopwatch = Stopwatch()..start();
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    client.userAgent = "Mozilla/5.0 (Android) MiniZivpn/1.0";
    client.badCertificateCallback = (cert, host, port) => true;

    try {
      // 1. Try HTTP Ping (Layer 7 - Native)
      final request = await client.getUrl(Uri.parse(target));
      final response = await request.close();
      stopwatch.stop();
      await response.drain();

      if (response.statusCode == 200 || response.statusCode == 204) {
        return "${stopwatch.elapsedMilliseconds} ms";
      }
      return "HTTP ${response.statusCode}";
    } catch (e) {
      // 1.5. Fallback: Gstatic Ping (Alternative Endpoint)
      try {
        final request = await client.getUrl(Uri.parse("http://www.gstatic.com/generate_204"));
        final response = await request.close();
        await response.drain();
        if (response.statusCode == 204) return "Gstatic OK";
      } catch (_) {}

      // 2. Fallback: TCP Handshake (Layer 4)
      try {
        final socket = await Socket.connect('1.1.1.1', 80, timeout: const Duration(seconds: 3));
        socket.destroy();
        return "TCP OK";
      } catch (_) {
        // 3. Last Resort: Package HTTP (High Level)
        try {
           final response = await http.get(Uri.parse("http://1.1.1.1")).timeout(const Duration(seconds: 5));
           if (response.statusCode == 200) return "HTTP OK";
        } catch(_) {}
        
        return "Timeout";
      }
    } finally {
      client.close();
    }
  }

  Color _getColor(String res) {
    if (res == "Pinging...") return Colors.white;
    if (res.contains("ms")) {
      final ms = int.tryParse(res.split(' ')[0]) ?? 999;
      if (ms < 150) return Colors.greenAccent;
      if (ms < 300) return Colors.yellow;
    }
    if (res == "TCP OK") return Colors.cyanAccent;
    if (res == "Gstatic OK") return Colors.lightGreenAccent;
    if (res == "HTTP OK") return Colors.lightBlueAccent;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: _result,
      builder: (context, value, child) {
        return Column(
          children: [
            FloatingActionButton.small(
              heroTag: "ping_btn",
              onPressed: _doPing,
              backgroundColor: const Color(0xFF272736),
              elevation: 4,
              child: RotationTransition(
                turns: _animController,
                child: Icon(
                  Icons.flash_on,
                  color: _isPinging ? Colors.yellow : const Color(0xFF6C63FF),
                ),
              ),
            ),
            if (value.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _getColor(value).withValues(alpha: 0.3),
                    width: 1
                  )
                ),
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _getColor(value),
                  ),
                ),
              ),
            ]
          ],
        );
      },
    );
  }
}