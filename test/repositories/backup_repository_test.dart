import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mini_zivpn/models/account.dart';
import 'package:mini_zivpn/repositories/backup_repository.dart';

void main() {
  group('BackupRepository.prepareBackupPrefs', () {
    test('removes ephemeral keys from backup payload', () {
      final repo = BackupRepository();
      final result = repo.prepareBackupPrefs({
        'vpn_running': true,
        'vpn_start_time': '12345',
        'log_level': 'info',
      });

      expect(result.containsKey('vpn_running'), isFalse);
      expect(result.containsKey('vpn_start_time'), isFalse);
      expect(result['log_level'], 'info');
    });

    test('specific account backup injects single account config', () {
      final repo = BackupRepository();
      final account = Account(
        name: 'Proxy A',
        ip: '1.2.3.4',
        auth: 'secret',
        obfs: 'custom_obfs',
        usage: 777,
      );

      final result = repo.prepareBackupPrefs(
        {
          'saved_accounts': jsonEncode([
            {'name': 'Other', 'ip': '8.8.8.8', 'auth': 'x', 'obfs': 'y', 'usage': 0}
          ]),
          'active_account_index': 3,
          'ip': 'old',
          'auth': 'old',
          'obfs': 'old',
          'ping_interval': 3,
        },
        specificAccount: account,
      );

      final savedAccountsRaw = result[BackupRepository.savedAccountsKey] as String;
      final savedAccounts = jsonDecode(savedAccountsRaw) as List<dynamic>;

      expect(savedAccounts, hasLength(1));
      expect(savedAccounts.first['name'], 'Proxy A');
      expect(savedAccounts.first['ip'], '1.2.3.4');
      expect(savedAccounts.first['auth'], 'secret');
      expect(savedAccounts.first['obfs'], 'custom_obfs');
      expect(result[BackupRepository.activeAccountIndexKey], 0);
      expect(result['ip'], '1.2.3.4');
      expect(result['auth'], 'secret');
      expect(result['obfs'], 'custom_obfs');
      expect(result['ping_interval'], 3);
    });
  });
}
