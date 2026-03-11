import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import '../../auth/services/google_auth_service.dart';
import '../../database/repositories/asset_repository.dart';
import '../../database/models/asset_metadata.dart';
import '../../albums/services/media_scanner_service.dart';
import '../../upload/services/upload_manager.dart';
import '../../upload/services/battery_optimization_helper.dart';
import '../../settings/settings_provider.dart';
import 'albums/album_selection_screen.dart';
import 'login_screen.dart';

final assetRepositoryProvider = Provider((ref) => AssetRepository());

final mediaScannerProvider = Provider((ref) {
  final repo = ref.watch(assetRepositoryProvider);
  return MediaScannerService(repo);
});

// 即時監控資料庫各狀態數量的 Provider
final syncStatsProvider = StreamProvider.autoDispose<Map<String, Map<String, int>>>((ref) async* {
  final repo = ref.watch(assetRepositoryProvider);
  // 透過 polling 簡單實作即時更新，實務上可改用 SQLite 的 hook 或 EventBus
  while (true) {
    yield await repo.getAlbumStats();
    await Future.delayed(const Duration(seconds: 2));
  }
});

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _isScanning = false;
  bool _isUploading = false;
  bool _isRetrying = false;
  bool? _batteryOptimized;

  Future<void> _startScan() async {
    // Check battery optimization on first interaction
    await _checkBatteryOptimization();

    final scanner = ref.read(mediaScannerProvider);
    
    // 1. 取得相簿清單
    List<AssetPathEntity> albums = [];
    try {
      albums = await scanner.getAlbums();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('無法讀取相簿: $e')));
      }
      return;
    }

    if (albums.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('找不到任何相簿')));
      }
      return;
    }

    // 2. 顯示選擇畫面
    if (!mounted) return;
    final currentStats = ref.read(syncStatsProvider).value ?? {};
    final selectedAlbums = await Navigator.of(context).push<List<AssetPathEntity>>(
      MaterialPageRoute(
        builder: (context) => AlbumSelectionScreen(albums: albums, stats: currentStats),
      ),
    );

    if (selectedAlbums == null || selectedAlbums.isEmpty) {
      return; // 使用者取消或未選擇
    }

    // 3. 掃描選擇的相簿
    setState(() => _isScanning = true);
    try {
      await scanner.scanAndSyncDatabase(selectedAlbums);
      ref.invalidate(syncStatsProvider); // 掃描完畢重新讀取數字
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('掃描相簿完成！')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('掃描發生錯誤: $e')));
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _startUpload() async {
    setState(() => _isUploading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final logs = prefs.getStringList('app_error_logs') ?? [];
      final timestamp = DateTime.now().toString().split('.')[0];
      logs.insert(0, '[$timestamp] UI: _startUpload 開始執行');
      if (logs.length > 50) logs.removeLast();
      await prefs.setStringList('app_error_logs', logs);

      final uploader = ref.read(uploadManagerProvider);
      
      logs.insert(0, '[$timestamp] UI: 準備呼叫 enqueuePendingUploads');
      await prefs.setStringList('app_error_logs', logs);
      
      await uploader.enqueuePendingUploads();
      
      logs.insert(0, '[$timestamp] UI: enqueuePendingUploads 呼叫完成');
      await prefs.setStringList('app_error_logs', logs);
      
      ref.invalidate(syncStatsProvider); // 開始上傳重新讀取數字
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已將任務加入背景上傳佇列！')));
      }
    } catch (e) {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('啟動上傳發生錯誤: ${e.toString().replaceAll("Exception: ", "")}')));
      }
      final prefs = await SharedPreferences.getInstance();
      final logs = prefs.getStringList('app_error_logs') ?? [];
      final timestamp = DateTime.now().toString().split('.')[0];
      logs.insert(0, '[$timestamp] UI: _startUpload 捕獲錯誤: $e');
      if (logs.length > 50) logs.removeLast();
      await prefs.setStringList('app_error_logs', logs);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _retryFailed() async {
    setState(() => _isRetrying = true);
    try {
      final uploader = ref.read(uploadManagerProvider);
      final count = await uploader.retryFailedUploads();
      ref.invalidate(syncStatsProvider);
      if (mounted) {
        if (count > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已將 $count 張失敗的照片重新加入上傳佇列')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('目前沒有失敗的照片需要重試')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重試失敗: ${e.toString().replaceAll("Exception: ", "")}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRetrying = false);
    }
  }

  Future<void> _checkBatteryOptimization() async {
    if (_batteryOptimized != null) return; // Already checked this session
    final ignored = await BatteryOptimizationHelper.isIgnoringBatteryOptimizations();
    _batteryOptimized = ignored;
    if (!ignored && mounted) {
      await _showBatteryOptimizationDialog();
    }
  }

  Future<void> _showBatteryOptimizationDialog() async {
    final instructions = await BatteryOptimizationHelper.getOemInstructions();
    final isIgnoring = await BatteryOptimizationHelper.isIgnoringBatteryOptimizations();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.battery_saver, color: isIgnoring ? Colors.green : Colors.amber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isIgnoring ? '電池優化已關閉 ✓' : '需要關閉電池優化',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isIgnoring) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '目前電池優化仍在啟用中！螢幕關閉後系統可能會終止背景上傳。',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text(instructions, style: const TextStyle(fontSize: 14, height: 1.6)),
            ],
          ),
        ),
        actions: [
          if (!isIgnoring)
            ElevatedButton.icon(
              icon: const Icon(Icons.settings, size: 18),
              label: const Text('關閉電池優化'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black87,
              ),
              onPressed: () async {
                await BatteryOptimizationHelper.requestIgnoreBatteryOptimizations();
              },
            ),
          TextButton.icon(
            icon: const Icon(Icons.app_settings_alt, size: 18),
            label: const Text('開啟手機設定'),
            onPressed: () async {
              await BatteryOptimizationHelper.openOemBatterySettings();
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearDatabase() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('警告'),
        content: const Text('這將會清除本地所有的掃描紀錄與上傳進度（不會刪除您手機或 Google 的照片）。確定要清除嗎？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('確定清除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final repo = ref.read(assetRepositoryProvider);
      final db = await repo.database;
      await db.execute('DELETE FROM assets');
      ref.invalidate(syncStatsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已清除所有本地進度紀錄')));
        Navigator.of(context).pop(); // Close drawer
      }
    }
  }

  Future<void> _resetStuckTasks() async {
    final repo = ref.read(assetRepositoryProvider);
    final db = await repo.database;
    // 將所有 uploading 狀態的改回 pending
    await db.rawUpdate('UPDATE assets SET syncStatus = ? WHERE syncStatus = ?', 
      [SyncStatus.pending.index, SyncStatus.uploading.index]);
    ref.invalidate(syncStatsProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已重置卡住的任務為等待中')));
      Navigator.of(context).pop(); // Close drawer
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = ref.watch(authServiceProvider);
    final statsAsync = ref.watch(syncStatsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('GPhotos 控制面板', style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                Scaffold.of(context).openEndDrawer();
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await authService.signOut();
              if (context.mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
          )
        ],
      ),
      endDrawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue),
              child: Text('設定', style: TextStyle(color: Colors.white, fontSize: 24)),
            ),
            Consumer(builder: (context, ref, child) {
              final settings = ref.watch(settingsProvider);
              return SwitchListTile(
                title: const Text('僅限 Wi-Fi 上傳'),
                subtitle: const Text('避免使用行動數據進行備份'),
                value: settings.requireWifi,
                onChanged: (bool value) {
                  ref.read(settingsProvider.notifier).toggleRequireWifi(value);
                },
              );
            }),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.bug_report, color: Colors.purple),
              title: const Text('檢視錯誤日誌'),
              subtitle: const Text('查看上傳失敗的詳細原因'),
              onTap: () async {
                Navigator.of(context).pop(); // Close drawer
                final prefs = await SharedPreferences.getInstance();
                final logs = prefs.getStringList('app_error_logs') ?? ['目前沒有錯誤紀錄'];
                
                if (mounted) {
                  showDialog(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('錯誤日誌'),
                      content: SizedBox(
                        width: double.maxFinite,
                        height: 300,
                        child: ListView.builder(
                          itemCount: logs.length,
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Text(logs[i], style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                          ),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () async {
                            await prefs.remove('app_error_logs');
                            if (c.mounted) Navigator.pop(c);
                          },
                          child: const Text('清空日誌', style: TextStyle(color: Colors.red)),
                        ),
                        TextButton(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: logs.join('\n')));
                            if (c.mounted) {
                               ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('已複製日誌到剪貼簿')));
                            }
                          },
                          child: const Text('複製日誌'),
                        ),
                        ElevatedButton(onPressed: () => Navigator.pop(c), child: const Text('關閉')),
                      ],
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh, color: Colors.orange),
              title: const Text('重置卡住的任務'),
              subtitle: const Text('將上傳中的照片改回等待中'),
              onTap: _resetStuckTasks,
            ),
            ListTile(
              leading: const Icon(Icons.replay, color: Colors.blue),
              title: const Text('重試失敗的任務'),
              subtitle: const Text('自動重新上傳所有失敗的照片'),
              onTap: () async {
                Navigator.of(context).pop();
                await _retryFailed();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.battery_saver, color: Colors.amber),
              title: const Text('電池優化設定'),
              subtitle: const Text('關閉電池優化以確保背景上傳'),
              onTap: () async {
                Navigator.of(context).pop();
                await _showBatteryOptimizationDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('清除本地資料庫', style: TextStyle(color: Colors.red)),
              subtitle: const Text('清空所有掃描紀錄重新開始'),
              onTap: _clearDatabase,
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(syncStatsProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      const Icon(Icons.cloud_sync, size: 64, color: Colors.blueAccent),
                      const SizedBox(height: 16),
                      const Text('備份狀態', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 24),
                      statsAsync.when(
                        data: (stats) {
                          if (stats.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text('目前沒有任何相簿資料，請先掃描本地相簿。', style: TextStyle(color: Colors.grey)),
                            );
                          }
                          
                          int totalAlbums = stats.length;
                          int completedAlbums = stats.values.where((s) => s['done'] == s['total'] && s['total']! > 0).length;

                          final entries = stats.entries.toList();
                          // 排序：有正在上傳的排最前面，再來是等待中的，最後是已完成的
                          entries.sort((a, b) {
                            final aUploading = a.value['uploading']! > 0 ? 1 : 0;
                            final bUploading = b.value['uploading']! > 0 ? 1 : 0;
                            if (aUploading != bUploading) return bUploading.compareTo(aUploading);

                            final aPending = a.value['pending']! > 0 ? 1 : 0;
                            final bPending = b.value['pending']! > 0 ? 1 : 0;
                            if (aPending != bPending) return bPending.compareTo(aPending);

                            return a.key.compareTo(b.key); // 名稱字母排序
                          });

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '已完成相簿: $completedAlbums / $totalAlbums',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A73E8)),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ...entries.map((entry) {                                final albumName = entry.key;
                                final albumStats = entry.value;
                                final total = albumStats['total'] ?? 0;
                                final done = albumStats['done'] ?? 0;
                                final uploading = albumStats['uploading'] ?? 0;
                                final failed = albumStats['failed'] ?? 0;
                                
                                final progress = total > 0 ? done / total : 0.0;
                                
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              albumName,
                                              style: const TextStyle(fontWeight: FontWeight.w600),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (uploading > 0)
                                            const SizedBox(
                                              width: 12, height: 12,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            ),
                                          if (uploading > 0) const SizedBox(width: 8),
                                          Text(
                                            '$done / $total 張',
                                            style: TextStyle(
                                              color: done == total ? Colors.green : Colors.grey[700],
                                              fontWeight: done == total ? FontWeight.bold : FontWeight.normal,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: progress,
                                          backgroundColor: Colors.grey[200],
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            failed > 0 ? Colors.red : (done == total ? Colors.green : Colors.blue),
                                          ),
                                          minHeight: 6,
                                        ),
                                      ),
                                      if (failed > 0)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4.0),
                                          child: Text('有 $failed 張上傳失敗', style: const TextStyle(color: Colors.red, fontSize: 12)),
                                        )
                                    ],
                                  ),
                                );
                              }).toList(),
                            ],
                          );
                        },
                        loading: () => const CircularProgressIndicator(),
                        error: (err, stack) => Text('讀取狀態失敗: $err', style: const TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _isScanning ? null : _startScan,
                icon: _isScanning
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.search),
                label: Text(_isScanning ? '正在掃描手機相簿...' : '步驟 1: 掃描本地相簿'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1A73E8),
                  side: const BorderSide(color: Color(0xFF1A73E8), width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _isUploading ? null : _startUpload,
                icon: _isUploading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_upload),
                label: Text(_isUploading ? '正在建立上傳佇列...' : '步驟 2: 開始背景備份'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A73E8),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isRetrying ? null : _retryFailed,
                icon: _isRetrying
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.replay, size: 20),
                label: Text(_isRetrying ? '重試中...' : '重試失敗的照片'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange[800],
                  side: BorderSide(color: Colors.orange[300]!),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                '提示：啟動「背景備份」後，即使您將 App 關閉，上傳仍會在背景繼續執行。大檔案會自動斷點續傳。',
                style: TextStyle(color: Colors.grey, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              FutureBuilder<bool>(
                future: BatteryOptimizationHelper.isIgnoringBatteryOptimizations(),
                builder: (context, snapshot) {
                  if (snapshot.data == false) {
                    return GestureDetector(
                      onTap: _showBatteryOptimizationDialog,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber[50],
                          border: Border.all(color: Colors.amber[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '⚠️ 電池優化未關閉，螢幕關閉後可能無法上傳。點此設定。',
                                style: TextStyle(fontSize: 13, color: Colors.black87),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'v1.0.3',
                style: TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
            ),
          )
        ],
      ),
    );
  }
}
