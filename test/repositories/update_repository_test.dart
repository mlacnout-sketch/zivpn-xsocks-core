import 'package:flutter_test/flutter_test.dart';
import 'package:mini_zivpn/repositories/update_repository.dart';

void main() {
  group('UpdateRepository Strategies', () {
    test('uses default strategies when none provided', () {
      final repo = UpdateRepository();
      // Check that it uses the default strategies constant
      expect(repo.strategies, equals(UpdateRepository.defaultStrategies));
      // Verify the content of default strategies matches the expectation
      expect(repo.strategies, equals([
        "SOCKS5 127.0.0.1:7777",
        "DIRECT"
      ]));
    });

    test('uses provided strategies', () {
      final customStrategies = ["PROXY 1.2.3.4:8080"];
      final repo = UpdateRepository(strategies: customStrategies);
      expect(repo.strategies, equals(customStrategies));
    });
  });
}
