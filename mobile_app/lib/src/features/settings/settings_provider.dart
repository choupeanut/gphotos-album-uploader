import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});

class AppSettings {
  final bool requireWifi;
  
  AppSettings({this.requireWifi = true});
  
  AppSettings copyWith({bool? requireWifi}) {
    return AppSettings(
      requireWifi: requireWifi ?? this.requireWifi,
    );
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  Future<void>? loadFuture;

  SettingsNotifier() : super(AppSettings()) {
    loadFuture = _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final requireWifi = prefs.getBool('require_wifi') ?? true;
    state = state.copyWith(requireWifi: requireWifi);
  }

  Future<void> toggleRequireWifi(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('require_wifi', value);
    state = state.copyWith(requireWifi: value);
  }
}
