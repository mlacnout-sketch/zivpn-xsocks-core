import 'package:flutter_test/flutter_test.dart';
import 'package:mini_zivpn/viewmodels/update_viewmodel.dart';
import 'package:mini_zivpn/repositories/update_repository.dart';
import 'package:mini_zivpn/models/app_version.dart';

// Manual Mock extending UpdateRepository to avoid dependencies on mockito
class MockUpdateRepository extends UpdateRepository {
  AppVersion? _mockResult;

  void setMockResult(AppVersion? result) {
    _mockResult = result;
  }

  @override
  Future<AppVersion?> fetchUpdate() async {
    return _mockResult;
  }
}

void main() {
  group('UpdateViewModel Tests', () {
    late UpdateViewModel viewModel;
    late MockUpdateRepository mockRepository;

    setUp(() {
      mockRepository = MockUpdateRepository();
      viewModel = UpdateViewModel(repository: mockRepository);
    });

    tearDown(() {
      viewModel.dispose();
    });

    test('checkForUpdate returns true and emits value when update is available', () async {
      final update = AppVersion(
        name: '2.0.0',
        apkUrl: 'https://example.com/update.apk',
        apkSize: 1024 * 1024 * 10,
        description: 'Major update',
      );
      mockRepository.setMockResult(update);

      // Verify stream emission
      expectLater(viewModel.availableUpdate, emits(update));

      final result = await viewModel.checkForUpdate();

      expect(result, true);
    });

    test('checkForUpdate returns false and emits null when no update is available', () async {
      mockRepository.setMockResult(null);

      // Verify stream emission
      expectLater(viewModel.availableUpdate, emits(null));

      final result = await viewModel.checkForUpdate();

      expect(result, false);
    });
  });
}
