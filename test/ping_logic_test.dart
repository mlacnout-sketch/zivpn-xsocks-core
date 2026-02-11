import 'package:flutter_test/flutter_test.dart';
import 'package:mini_zivpn/logic/ping_logic.dart';

void main() {
  test('PingLogic should connect to valid HTTPS site', () async {
    final result = await PingLogic.performPing('https://clients3.google.com/generate_204');
    // Result should be in format "123 ms"
    expect(result, matches(RegExp(r'^\d+ ms$')));
  });

  test('PingLogic should fail on invalid SSL certificate and use fallback', () async {
    // expired.badssl.com has an expired certificate
    final result = await PingLogic.performPing('https://expired.badssl.com/');

    // If SSL validation is working, the primary connection will fail.
    // It will then try Gstatic (fallback 1.5) or TCP (fallback 2) or HTTP (fallback 3).
    // So the result will be "Gstatic OK" or "TCP ... ms" or "HTTP OK" or "Timeout" or "Error".

    // It should NOT be "123 ms" (primary success).
    expect(result, isNot(matches(RegExp(r'^\d+ ms$'))));

    // It should be one of the fallbacks
    expect(
      result.contains("Gstatic OK") ||
      result.startsWith("TCP") ||
      result == "HTTP OK" ||
      result == "Timeout" ||
      result == "Error",
      isTrue,
      reason: "Result was '$result', expected a fallback response due to SSL failure."
    );
  });
}
