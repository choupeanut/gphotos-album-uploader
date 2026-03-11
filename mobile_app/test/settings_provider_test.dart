import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gphotos_uploader_mobile/src/features/settings/settings_provider.dart';

void main() {
  group('SettingsProvider Tests', () {
    test('default value for requireWifi should be true if not set', () async {
      SharedPreferences.setMockInitialValues({});
      
      final container = ProviderContainer();
      
      // Initially false because the async init hasn't finished, wait for it
      await container.read(settingsProvider.notifier).loadFuture;
      final updatedSettings = container.read(settingsProvider);

      expect(updatedSettings.requireWifi, true);
    });

    test('should load requireWifi from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({'require_wifi': false});
      
      final container = ProviderContainer();
      
      // Wait for async init
      await container.read(settingsProvider.notifier).loadFuture;
      final settings = container.read(settingsProvider);

      expect(settings.requireWifi, false);
    });

    test('toggleRequireWifi should update state and SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({'require_wifi': true});
      final prefs = await SharedPreferences.getInstance();
      
      final container = ProviderContainer();
      await container.read(settingsProvider.notifier).loadFuture; // wait for init
      
      await container.read(settingsProvider.notifier).toggleRequireWifi(false);
      
      final settings = container.read(settingsProvider);
      expect(settings.requireWifi, false);
      expect(prefs.getBool('require_wifi'), false);
    });
  });
}
