import 'dart:io';
import 'package:http/http.dart' as http;

class PingLogic {
  static Future<String> performPing(String? target) async {
    // Default to HTTPS if empty
    if (target == null || target.trim().isEmpty) {
      target = "https://clients3.google.com/generate_204";
    } else {
      target = target.trim();
    }

    // Ensure HTTPS protocol if missing
    if (!target.startsWith("http")) {
      target = "https://$target";
    }

    final stopwatch = Stopwatch()..start();
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    client.userAgent = "Mozilla/5.0 (Android) MiniZivpn/1.0";
    // REMOVED: client.badCertificateCallback = (cert, host, port) => true; // Security fix: Enforce certificate validation

    try {
      // 1. Try HTTPS Ping (Layer 7 - Native)
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
        final request = await client.getUrl(Uri.parse("https://www.gstatic.com/generate_204"));
        final response = await request.close();
        await response.drain();
        if (response.statusCode == 204) return "Gstatic OK";
      } catch (_) {}

      // 2. Fallback: TCP Handshake (Layer 4)
      try {
        final sw = Stopwatch()..start();
        // Use port 443 for HTTPS consistency
        final socket = await Socket.connect('1.1.1.1', 443, timeout: const Duration(seconds: 3));
        sw.stop();
        socket.destroy();
        return "TCP ${sw.elapsedMilliseconds} ms";
      } catch (_) {
        // 3. Last Resort: Package HTTP (High Level)
        try {
           final response = await http.get(Uri.parse("https://1.1.1.1")).timeout(const Duration(seconds: 5));
           if (response.statusCode == 200) return "HTTP OK";
        } catch(_) {}

        return "Timeout";
      }
    } finally {
      client.close();
    }
  }
}
