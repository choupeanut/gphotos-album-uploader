import 'dart:io';
import 'package:flutter/services.dart';

/// Helper to manage OEM-specific battery optimization settings.
/// Critical for Xiaomi (MIUI) and Samsung (OneUI) which aggressively
/// kill background processes.
class BatteryOptimizationHelper {
  static const _channel =
      MethodChannel('com.example.gphotos_uploader_mobile/background');

  /// Check if the app is already exempt from battery optimization.
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      final result =
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Show system dialog to request disabling battery optimization for this app.
  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  }

  /// Open OEM-specific battery / autostart settings.
  /// Returns true if an OEM-specific intent was launched.
  static Future<bool> openOemBatterySettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final result =
          await _channel.invokeMethod<bool>('openOemBatterySettings');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Get the device manufacturer (lowercase).
  static Future<String> getDeviceManufacturer() async {
    if (!Platform.isAndroid) return 'unknown';
    try {
      final result =
          await _channel.invokeMethod<String>('getDeviceManufacturer');
      return result ?? 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  /// Acquire a partial CPU wake lock to keep background processing alive.
  /// Auto-releases after 30 minutes.
  static Future<void> acquireWakeLock() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('acquireWakeLock');
    } catch (_) {}
  }

  /// Release the partial CPU wake lock.
  static Future<void> releaseWakeLock() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('releaseWakeLock');
    } catch (_) {}
  }

  /// Get OEM-specific instructions for the user.
  static Future<String> getOemInstructions() async {
    final manufacturer = await getDeviceManufacturer();

    if (manufacturer.contains('xiaomi') || manufacturer.contains('redmi')) {
      return '您使用的是小米/Redmi 手機，MIUI 會積極限制背景應用。\n'
          '請按照以下步驟設定：\n\n'
          '1. 「設定」→「應用設定」→「自啟動管理」→ 開啟本 App\n'
          '2. 「設定」→「電池與效能」→「省電策略」→ 將本 App 設為「無限制」\n'
          '3. 在最近任務中，長按本 App 卡片 → 點擊鎖定圖示 🔒\n'
          '4. 確認已關閉「電池優化」（上方按鈕可直接開啟）';
    } else if (manufacturer.contains('samsung')) {
      return '您使用的是三星手機，OneUI 會將背景 App 設為休眠。\n'
          '請按照以下步驟設定：\n\n'
          '1. 「設定」→「電池」→「背景使用限制」→ 將本 App 從「休眠 App」移除\n'
          '2. 「設定」→「電池」→「電池最佳化」→ 找到本 App → 選擇「不要最佳化」\n'
          '3. 確認已關閉「電池優化」（上方按鈕可直接開啟）';
    } else if (manufacturer.contains('huawei') || manufacturer.contains('honor')) {
      return '您使用的是華為/榮耀手機，系統會限制背景 App。\n'
          '請按照以下步驟設定：\n\n'
          '1. 「設定」→「電池」→「啟動管理」→ 關閉本 App 的自動管理\n'
          '2. 手動開啟「自啟動」、「背景活動」和「關聯啟動」\n'
          '3. 確認已關閉「電池優化」';
    } else if (manufacturer.contains('oppo') || manufacturer.contains('realme') || manufacturer.contains('oneplus')) {
      return '您使用的手機系統可能限制背景應用。\n'
          '請按照以下步驟設定：\n\n'
          '1. 「設定」→「電池」→「更多電池設定」→ 關閉「智慧省電」\n'
          '2. 「設定」→「應用管理」→ 本 App →「電池使用率」→「允許背景活動」\n'
          '3. 確認已關閉「電池優化」';
    }

    return '為確保背景上傳正常運作：\n\n'
        '1. 請關閉本 App 的「電池優化」（上方按鈕可直接開啟）\n'
        '2. 確認 App 的背景活動權限為「不受限制」\n'
        '3. 在最近任務中鎖定本 App 防止被系統清除';
  }
}
