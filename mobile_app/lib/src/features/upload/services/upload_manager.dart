import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/services/google_auth_service.dart';
import '../../auth/services/google_photos_api_client.dart';
import '../../database/models/asset_metadata.dart';
import '../../database/repositories/asset_repository.dart';
import '../../settings/settings_provider.dart';
import 'battery_optimization_helper.dart';
import 'resumable_upload_engine.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

final uploadManagerProvider = Provider<UploadManager>((ref) {
  final authService = ref.read(authServiceProvider);
  final apiClient = ref.read(googlePhotosApiProvider);
  final repo = AssetRepository();
  final settings = ref.watch(settingsProvider);
  return UploadManager(
    authService,
    apiClient,
    repo,
    requireWifi: settings.requireWifi,
  );
});

class UploadManager {
  final GoogleAuthService _authService;
  final GooglePhotosApiClient _apiClient;
  final AssetRepository _repository;
  bool _requireWifi;

  static const String _taskGroup = 'gphotos_backup';
  static const int _progressNotificationId = 2026030701;
  static const String _progressChannelId = 'gphotos_progress_channel';
  static const String _progressChannelName = 'Google Photos Upload Progress';

  bool _callbacksRegistered = false;
  bool _notificationInitialized = false;
  bool _notificationEnabled = false;
  bool _downloaderConfigured = false;
  String? _activeAccessToken;
  bool _isProcessing = false;

  final ListQueue<_BindJob> _bindQueue = ListQueue<_BindJob>();
  final Map<String, _BindJob> _bindByTaskId = <String, _BindJob>{};
  bool _isBindRunning = false;
  int _bindSequence = 0;

  final Map<String, String> _assetAlbum = {};
  final Map<String, int> _albumTargetCount = {};
  final Map<String, int> _albumUploadedCount = {};
  final Set<String> _countedDoneAssets = {};

  int _targetPhotoCount = 0;
  int _uploadedPhotoCount = 0;
  String _currentAlbum = '-';

  UploadManager(
    this._authService,
    this._apiClient,
    this._repository, {
    bool requireWifi = true,
  }) : _requireWifi = requireWifi {
    _initCustomNotifications();
    _initDownloader();  // async, but fire-and-forget during construction
  }

  Future<void> _initCustomNotifications() async {
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: androidInit);
      await flutterLocalNotificationsPlugin
          .initialize(settings: settings)
          .timeout(const Duration(seconds: 5));

      final androidImpl = flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          _progressChannelId,
          _progressChannelName,
          description: 'Persistent upload progress summary',
          importance: Importance.low,
        ),
      );

      _notificationInitialized = true;
    } catch (e) {
      _notificationInitialized = false;
      _logError('SYS', 'Custom notification init failed: $e');
    }
  }

  Future<void> _prepareNotificationPermission() async {
    if (!Platform.isAndroid) return;

    if (!_notificationInitialized) {
      await _initCustomNotifications();
    }

    if (!_notificationInitialized) {
      _notificationEnabled = false;
      return;
    }

    final status = await Permission.notification.request();
    _notificationEnabled = status.isGranted;
    if (!_notificationEnabled) {
      _logError('SYS', 'Notification permission denied; continue upload without custom progress notification');
    }
  }

  Future<void> _updatePersistentProgressNotification() async {
    if (!_notificationEnabled) return;

    final albumTotal = _albumTargetCount.length;
    final albumDone = _albumTargetCount.entries
        .where((entry) => (_albumUploadedCount[entry.key] ?? 0) >= entry.value)
        .length;

    final currentAlbumTarget = _albumTargetCount[_currentAlbum] ?? 0;
    final currentAlbumDone = _albumUploadedCount[_currentAlbum] ?? 0;

    final line1 =
        '共相簿 $albumDone/$albumTotal 個已上傳，共 $_uploadedPhotoCount/$_targetPhotoCount 張照片已上傳';
    final line2 =
        '目前上傳相簿：$_currentAlbum，已上傳本相簿 $currentAlbumDone/$currentAlbumTarget 張';

    final androidDetails = AndroidNotificationDetails(
      _progressChannelId,
      _progressChannelName,
      channelDescription: 'Persistent upload progress summary',
      importance: Importance.low,
      priority: Priority.low,
      showProgress: true,
      maxProgress: _targetPhotoCount == 0 ? 1 : _targetPhotoCount,
      progress: _uploadedPhotoCount,
      ongoing: _uploadedPhotoCount < _targetPhotoCount,
      onlyAlertOnce: true,
      icon: '@mipmap/ic_launcher',
      styleInformation: BigTextStyleInformation('$line1\n$line2'),
    );

    await flutterLocalNotificationsPlugin.show(
      id: _progressNotificationId,
      title: 'Google Photos 備份進度',
      body: '$line1\n$line2',
      notificationDetails: NotificationDetails(android: androidDetails),
    );
  }

  void _resetRunState(List<AssetMetadata> pendingAssets) {
    _assetAlbum.clear();
    _albumTargetCount.clear();
    _albumUploadedCount.clear();
    _countedDoneAssets.clear();

    _uploadedPhotoCount = 0;
    _targetPhotoCount = pendingAssets.length;
    _currentAlbum = '-';

    for (final asset in pendingAssets) {
      _assetAlbum[asset.localId] = asset.albumName;
      _albumTargetCount[asset.albumName] =
          (_albumTargetCount[asset.albumName] ?? 0) + 1;
      _albumUploadedCount.putIfAbsent(asset.albumName, () => 0);
    }
  }

  Future<void> _markDoneForProgress(String localId) async {
    if (_countedDoneAssets.contains(localId)) return;
    _countedDoneAssets.add(localId);

    final album = _assetAlbum[localId];
    if (album != null) {
      _albumUploadedCount[album] = (_albumUploadedCount[album] ?? 0) + 1;
      _currentAlbum = album;
    }
    _uploadedPhotoCount += 1;

    await _updatePersistentProgressNotification();
  }

  Future<void> _showCompletionNotification() async {
    if (!_notificationEnabled) return;

    final albumTotal = _albumTargetCount.length;
    final albumDone = _albumTargetCount.entries
        .where((entry) => (_albumUploadedCount[entry.key] ?? 0) >= entry.value)
        .length;

    final androidDetails = const AndroidNotificationDetails(
      _progressChannelId,
      _progressChannelName,
      channelDescription: 'Persistent upload progress summary',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: false,
      icon: '@mipmap/ic_launcher',
    );

    await flutterLocalNotificationsPlugin.show(
      id: _progressNotificationId,
      title: 'Google Photos 備份完成',
      body: '共相簿 $albumDone/$albumTotal 個完成，共 $_uploadedPhotoCount/$_targetPhotoCount 張已上傳',
      notificationDetails: NotificationDetails(android: androidDetails),
    );
  }

  Future<void> _initDownloader() async {
    if (_callbacksRegistered) return;

    // Configure persistent storage and wake lock for background resilience
    if (!_downloaderConfigured) {
      try {
        await FileDownloader().configure(
          globalConfig: [
            (Config.runInForeground, Config.always),
            (Config.checkAvailableSpace, Config.always),
          ],
          androidConfig: [
            (Config.useCacheDir, Config.whenAble),
          ],
        );
      } catch (e) {
        _logError('SYS', 'FileDownloader configure failed (non-fatal): $e');
      }

      // Enable persistent task tracking so tasks survive app restart
      try {
        await FileDownloader().trackTasks();
      } catch (e) {
        _logError('SYS', 'FileDownloader trackTasks failed (non-fatal): $e');
      }

      _downloaderConfigured = true;
    }

    // Configure foreground service notification — this makes the Android
    // system start a foreground service with type dataSync, preventing
    // the OS from killing upload tasks when the screen is off.
    FileDownloader().configureNotificationForGroup(
      _taskGroup,
      running: const TaskNotification(
        'Google Photos 備份中',
        '背景傳輸進行中… 請勿關閉',
      ),
      complete: const TaskNotification(
        'Google Photos 備份',
        '檔案上傳完成',
      ),
      error: const TaskNotification(
        'Google Photos 備份',
        '上傳失敗，將自動重試',
      ),
      paused: null,
      canceled: null,
      progressBar: true,
    );

    FileDownloader().registerCallbacks(
      group: _taskGroup,
      taskStatusCallback: (TaskStatusUpdate update) {
        _logError(update.task.taskId, 'Received status update: ${update.status}');
        _handleTaskStatus(update);
      },
      taskProgressCallback: (_) {},
    );

    _callbacksRegistered = true;
  }

  Future<void> _handleTaskStatus(TaskStatusUpdate update) async {
    final localId = update.task.taskId;

    if (localId.startsWith('bind_')) {
      await _handleBindTaskStatus(update);
      return;
    }

    final album = _assetAlbum[localId];
    if (album != null) {
      _currentAlbum = album;
    }

    if (update.status == TaskStatus.complete) {
      final uploadToken = update.responseBody?.trim();
      if (uploadToken != null && uploadToken.isNotEmpty) {
        await _enqueuePostUpload(localId, uploadToken);
      } else {
        _logError(localId, 'Upload completed but uploadToken missing; statusCode=${update.responseStatusCode}');
        await _repository.updateStatus(localId, SyncStatus.failed);
        await _updatePersistentProgressNotification();
      }
    } else if (update.status == TaskStatus.failed ||
        update.status == TaskStatus.canceled) {
      _logError(localId, 'Background upload failed: status=${update.status}, exception=${update.exception?.description}');
      await _repository.updateStatus(localId, SyncStatus.failed);
      await _updatePersistentProgressNotification();
    } else if (update.status == TaskStatus.enqueued ||
        update.status == TaskStatus.running) {
      await _repository.updateStatus(localId, SyncStatus.uploading);
      await _updatePersistentProgressNotification();
    } else if (update.status == TaskStatus.waitingToRetry ||
        update.status == TaskStatus.paused) {
      await _repository.updateStatus(localId, SyncStatus.pending);
      await _updatePersistentProgressNotification();
    }
  }

  Future<void> _enqueuePostUpload(String localId, String uploadToken) {
    _bindQueue.add(_BindJob(localId: localId, uploadToken: uploadToken));
    return _drainBindQueue();
  }

  Future<void> _drainBindQueue() async {
    if (_isBindRunning) return;

    while (_bindQueue.isNotEmpty) {
      final job = _bindQueue.removeFirst();
      final asset = await _repository.getAssetByLocalId(job.localId);
      if (asset == null) {
        continue;
      }

      final albumId = asset.remoteAlbumId;
      if (albumId == null || albumId.isEmpty) {
        _logError(job.localId, 'remoteAlbumId missing; move to pending');
        await _repository.updateStatus(job.localId, SyncStatus.pending);
        await _updatePersistentProgressNotification();
        continue;
      }

      final token = _activeAccessToken;
      if (token == null || token.isEmpty) {
        _logError(job.localId, 'active access token missing; move to pending');
        await _repository.updateStatus(job.localId, SyncStatus.pending);
        await _updatePersistentProgressNotification();
        continue;
      }

      final assetEntity = await AssetEntity.fromId(job.localId);
      String filename = 'photo_${job.localId}.jpg';
      if (assetEntity != null) {
        final file = await assetEntity.file;
        if (file != null) {
          final ext = file.path.split('.').last;
          filename = assetEntity.title ?? 'photo_${job.localId}.$ext';
        }
      }

      final bindTaskId = 'bind_${job.localId}_${_bindSequence++}';
      final dataTask = DataTask(
        taskId: bindTaskId,
        url: 'https://photoslibrary.googleapis.com/v1/mediaItems:batchCreate',
        httpRequestMethod: 'POST',
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        json: {
          'albumId': albumId,
          'newMediaItems': [
            {
              'description': filename,
              'simpleMediaItem': {'uploadToken': job.uploadToken},
            },
          ],
        },
        group: _taskGroup,
        updates: Updates.status,
        requiresWiFi: _requireWifi,
        retries: 8,
      );

      final enqueued = await FileDownloader().enqueue(dataTask);
      if (!enqueued) {
        _logError(job.localId, 'Failed to enqueue bind DataTask; move to pending');
        await _repository.updateStatus(job.localId, SyncStatus.pending);
        await _updatePersistentProgressNotification();
        continue;
      }

      _bindByTaskId[bindTaskId] = job;
      _isBindRunning = true;
      return;
    }
  }

  Future<void> _handleBindTaskStatus(TaskStatusUpdate update) async {
    final bindTaskId = update.task.taskId;
    final bindJob = _bindByTaskId[bindTaskId];
    if (bindJob == null) {
      return;
    }

    final isTerminal =
        update.status == TaskStatus.complete ||
        update.status == TaskStatus.failed ||
        update.status == TaskStatus.canceled;

    if (update.status == TaskStatus.complete) {
      final body = update.responseBody;
      if (body == null || body.isEmpty) {
        _logError(bindJob.localId, 'batchCreate response body empty');
        await _repository.updateStatus(bindJob.localId, SyncStatus.pending);
      } else {
        try {
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          final mediaItemResults = decoded['newMediaItemResults'] as List<dynamic>?;
          if (mediaItemResults == null || mediaItemResults.isEmpty) {
            throw Exception('newMediaItemResults missing');
          }

          final resultStatus = mediaItemResults.first['status'];
          if (resultStatus != null &&
              resultStatus['code'] != null &&
              resultStatus['code'] != 0) {
            throw Exception('Google API returned error: ${resultStatus['message']}');
          }

          final mediaItem = mediaItemResults.first['mediaItem'];
          if (mediaItem == null || mediaItem['id'] == null) {
            throw Exception('mediaItem.id missing');
          }

          final asset = await _repository.getAssetByLocalId(bindJob.localId);
          await _repository.updateStatus(
            bindJob.localId,
            SyncStatus.done,
            remoteMediaItemId: mediaItem['id'],
            remoteAlbumId: asset?.remoteAlbumId,
          );
          await _markDoneForProgress(bindJob.localId);
        } catch (e) {
          _logError(bindJob.localId, 'Failed to parse batchCreate response: $e');
          await _repository.updateStatus(bindJob.localId, SyncStatus.pending);
          await _updatePersistentProgressNotification();
        }
      }
    } else if (update.status == TaskStatus.failed ||
        update.status == TaskStatus.canceled) {
      _logError(bindJob.localId, 'batchCreate DataTask failed: status=${update.status}, exception=${update.exception?.description}');
      await _repository.updateStatus(bindJob.localId, SyncStatus.pending);
      await _updatePersistentProgressNotification();
    }

    if (isTerminal) {
      _bindByTaskId.remove(bindTaskId);
      _isBindRunning = false;
      await Future.delayed(const Duration(milliseconds: 1200));
      await _drainBindQueue();
    }
  }

  void _logError(String localId, String message) async {
    print('[$localId]: $message');
    final prefs = await SharedPreferences.getInstance();
    final logs = prefs.getStringList('app_error_logs') ?? [];
    final timestamp = DateTime.now().toString().split('.')[0];
    logs.insert(0, '[$timestamp] $localId: $message');
    if (logs.length > 200) logs.removeLast();
    await prefs.setStringList('app_error_logs', logs);
  }

  Future<void> enqueuePendingUploads() async {
    _logError('SYS', '=== Starting enqueuePendingUploads ===');
    String? token;
    try {
      _logError('SYS', 'Fetching Access Token...');
      token = await _authService.getAccessToken().timeout(
        const Duration(seconds: 10),
      );
      _logError('SYS', 'Token fetch success: ${token != null}');
    } catch (e) {
      _logError('SYS', 'Token fetch failed: $e');
      throw Exception(
        'Google Authorization timeout or failure ($e). Please sign in again.',
      );
    }

    if (token == null) {
      throw Exception('Unable to acquire Access Token. Please sign in again.');
    }

    try {
      _logError('SYS', 'Resetting stuck SQLite tasks...');
      final db = await _repository.database.timeout(const Duration(seconds: 5));
      await db
          .rawUpdate(
            'UPDATE assets SET syncStatus = ? WHERE syncStatus = ?',
            [SyncStatus.pending.index, SyncStatus.uploading.index],
          )
          .timeout(const Duration(seconds: 5));
      _logError('SYS', 'SQLite reset successful');
    } catch (e) {
      _logError('SYS', 'SQLite reset failed: $e');
      throw Exception('Failed to reset database states: $e');
    }

    List<AssetMetadata> pendingAssets;
    try {
      _logError('SYS', 'Reading Pending assets...');
      pendingAssets = await _repository
          .getPendingAssets()
          .timeout(const Duration(seconds: 10));
      _logError('SYS', 'Successfully read pending assets. Count: ${pendingAssets.length}');
    } catch (e) {
      _logError('SYS', 'Failed to read pending assets: $e');
      throw Exception('Failed to read waiting photos: $e');
    }

    if (pendingAssets.isEmpty) {
      _logError('SYS', 'No pending assets found. Aborting process.');
      throw Exception('No photos currently waiting for upload (Pending count is 0)');
    }

    _activeAccessToken = token;
    _resetRunState(pendingAssets);

    _logError('SYS', 'Preparing notification permission...');
    await _prepareNotificationPermission();
    await _updatePersistentProgressNotification();

    await _initDownloader();

    _logError('SYS', 'Starting background queue process: _processAndEnqueue...');
    _processAndEnqueue(pendingAssets, token);
    _logError('SYS', 'enqueuePendingUploads execution completed and returning to UI');
  }

  /// Retry all failed uploads by resetting them to pending and re-enqueuing.
  Future<int> retryFailedUploads() async {
    _logError('SYS', '=== Starting retryFailedUploads ===');
    try {
      final db = await _repository.database;

      // Count failed items
      final countResult = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM assets WHERE syncStatus = ?',
        [SyncStatus.failed.index],
      );
      final failedCount = (countResult.first['cnt'] as int?) ?? 0;

      if (failedCount == 0) {
        _logError('SYS', 'No failed uploads found to retry');
        return 0;
      }

      _logError('SYS', 'Resetting $failedCount failed uploads to pending...');

      // Reset all failed → pending
      await db.rawUpdate(
        'UPDATE assets SET syncStatus = ? WHERE syncStatus = ?',
        [SyncStatus.pending.index, SyncStatus.failed.index],
      );

      _logError('SYS', 'Reset complete. Now calling enqueuePendingUploads...');
      await enqueuePendingUploads();

      return failedCount;
    } catch (e) {
      _logError('SYS', 'retryFailedUploads error: $e');
      rethrow;
    }
  }

  /// Check if the upload preparation loop is currently running.
  bool get isProcessing => _isProcessing;

  Future<void> _processAndEnqueue(List<AssetMetadata> assets, String token) async {
    _isProcessing = true;

    // Acquire a partial CPU wake lock to keep Dart processing alive
    // when the screen is off. Essential for Xiaomi MIUI / Samsung OneUI.
    try {
      await BatteryOptimizationHelper.acquireWakeLock();
      _logError('SYS', 'Partial wake lock acquired for upload preparation');
    } catch (e) {
      _logError('SYS', 'Failed to acquire wake lock (non-fatal): $e');
    }

    try {
      _logError('SYS', 'Start processing ${assets.length} photos into background queue');

      // Pre-fetch album cache once before the loop
      try {
        await _apiClient.getOrCreateAlbum(assets.first.albumName);
        _logError('SYS', 'Album cache pre-warmed successfully');
      } catch (e) {
        _logError('SYS', 'Album cache pre-warm failed (will retry per-album): $e');
      }

      // Group assets by album to batch album preparation
      final albumGroups = <String, List<AssetMetadata>>{};
      for (final asset in assets) {
        albumGroups.putIfAbsent(asset.albumName, () => []).add(asset);
      }

      // Prepare all album IDs up front with retry
      final albumIdCache = <String, String>{};
      for (final albumName in albumGroups.keys) {
        for (int attempt = 0; attempt < 3; attempt++) {
          try {
            final albumId = await _apiClient.getOrCreateAlbum(albumName);
            albumIdCache[albumName] = albumId;
            _logError('SYS', 'Album "$albumName" prepared: $albumId');
            break;
          } catch (e) {
            _logError('SYS', 'Failed to prepare album "$albumName" (attempt ${attempt + 1}/3): $e');
            if (attempt < 2) {
              await Future.delayed(Duration(seconds: 3 * (attempt + 1)));
            }
          }
        }
      }

      int sessionUrlFailCount = 0;
      const int maxConsecutiveNetworkFails = 5;
      int enqueuedCount = 0;
      int skippedCount = 0;

      for (var assetMeta in assets) {
        _currentAlbum = assetMeta.albumName;

        final preparedAlbumId = albumIdCache[assetMeta.albumName];
        if (preparedAlbumId == null) {
          _logError(assetMeta.localId, 'Album not prepared, keeping pending for retry');
          skippedCount++;
          continue;
        }

        // Save the album ID to DB so the bind step can find it later
        await _repository.updateStatus(
          assetMeta.localId,
          SyncStatus.pending,
          remoteAlbumId: preparedAlbumId,
        );

        final assetEntity = await AssetEntity.fromId(assetMeta.localId);
        if (assetEntity == null) {
          _logError(assetMeta.localId, 'AssetEntity.fromId returned null');
          await _repository.updateStatus(assetMeta.localId, SyncStatus.failed);
          skippedCount++;
          continue;
        }

        final file = await assetEntity.file;
        if (file == null || !file.existsSync() || file.lengthSync() == 0) {
          _logError(assetMeta.localId, 'File is missing or 0 bytes (could be cloud-only)');
          await _repository.updateStatus(assetMeta.localId, SyncStatus.failed);
          skippedCount++;
          continue;
        }

        final ext = file.path.split('.').last;
        final filename = assetEntity.title ?? 'photo_${assetMeta.localId}.$ext';

        // Acquire session URL with network-aware retry
        String? sessionUrl;
        for (int attempt = 0; attempt < 3; attempt++) {
          try {
            _logError('SYS', 'Requesting sessionUrl for: $filename (attempt ${attempt + 1})');
            final engine = ResumableUploadEngine(accessToken: token);
            sessionUrl = await engine.initiateUploadSession(file, filename);
            sessionUrlFailCount = 0; // Reset on success
            break;
          } catch (e) {
            _logError(assetMeta.localId, 'Failed to acquire sessionUrl (attempt ${attempt + 1}): $e');

            final isNetworkError = e.toString().contains('SocketException') ||
                e.toString().contains('Failed host lookup') ||
                e.toString().contains('Connection refused') ||
                e.toString().contains('Connection reset');

            if (isNetworkError) {
              sessionUrlFailCount++;
              if (sessionUrlFailCount >= maxConsecutiveNetworkFails) {
                _logError('SYS',
                    'Network appears down ($sessionUrlFailCount consecutive failures). '
                    'Pausing 60s before resuming...');
                await Future.delayed(const Duration(seconds: 60));
                sessionUrlFailCount = maxConsecutiveNetworkFails - 1;
              } else {
                await Future.delayed(Duration(seconds: 3 * (attempt + 1)));
              }
            } else {
              // Non-network error (e.g. 401 auth expired), shorter delay
              await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
            }
          }
        }

        if (sessionUrl == null) {
          // All attempts failed — keep as pending so retry works later
          _logError(assetMeta.localId, 'Could not get sessionUrl after retries, keeping pending');
          skippedCount++;
          continue;
        }

        // Enqueue background upload via background_downloader
        final task = UploadTask.fromFile(
          taskId: assetMeta.localId,
          file: file,
          url: sessionUrl,
          group: _taskGroup,
          httpRequestMethod: 'POST',
          headers: {
            'X-Goog-Upload-Command': 'upload, finalize',
            'X-Goog-Upload-Offset': '0',
          },
          post: 'binary',
          updates: Updates.statusAndProgress,
          retries: 5,
          requiresWiFi: _requireWifi,
        );

        final enqueued = await FileDownloader().enqueue(task);
        if (enqueued) {
          await _repository.updateStatus(assetMeta.localId, SyncStatus.uploading);
          enqueuedCount++;
        } else {
          _logError(assetMeta.localId, 'Failed to enqueue background task');
          skippedCount++;
        }

        await _updatePersistentProgressNotification();

        // Small delay between enqueues to avoid flooding
        await Future.delayed(const Duration(milliseconds: 200));
      }

      _logError('SYS', '_processAndEnqueue completed! Enqueued: $enqueuedCount, Skipped: $skippedCount');

      // If some items were skipped due to network issues, schedule a single 
      // auto-retry after a delay (gives network time to recover)
      if (skippedCount > 0) {
        _logError('SYS', 'Scheduling auto-retry for $skippedCount skipped items in 120s...');
        Future.delayed(const Duration(seconds: 120), () async {
          if (_isProcessing) return; // Don't overlap
          try {
            final pending = await _repository.getPendingAssets();
            if (pending.isNotEmpty) {
              _logError('SYS', 'Auto-retry: found ${pending.length} pending items, re-running...');
              final freshToken = await _authService.getAccessToken();
              if (freshToken != null) {
                _activeAccessToken = freshToken;
                _resetRunState(pending);
                await _processAndEnqueue(pending, freshToken);
              }
            }
          } catch (e) {
            _logError('SYS', 'Auto-retry failed: $e');
          }
        });
      }
    } catch (e, stack) {
      _logError('SYS', 'Unexpected crash inside _processAndEnqueue: $e\n$stack');
    } finally {
      _isProcessing = false;
      try {
        await BatteryOptimizationHelper.releaseWakeLock();
        _logError('SYS', 'Partial wake lock released');
      } catch (e) {
        _logError('SYS', 'Failed to release wake lock (non-fatal): $e');
      }
    }
  }
}

class _BindJob {
  final String localId;
  final String uploadToken;

  _BindJob({required this.localId, required this.uploadToken});
}
