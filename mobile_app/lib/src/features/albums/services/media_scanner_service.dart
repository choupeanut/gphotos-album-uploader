import 'package:photo_manager/photo_manager.dart';
import '../../database/repositories/asset_repository.dart';
import '../../database/services/hash_service.dart';
import '../../database/models/asset_metadata.dart';

class MediaScannerService {
  final AssetRepository _repository;

  MediaScannerService(this._repository);

  /// 取得所有相簿清單供 UI 選擇
  Future<List<AssetPathEntity>> getAlbums() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth) {
      throw Exception('無權限存取媒體庫');
    }
    
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common, // 包含圖片與影片
      hasAll: true,
    );
    
    // 過濾掉系統預設的「全部/最近」相簿，避免與實體相簿重複計算或混淆
    return albums.where((album) => !album.isAll).toList();
  }

  /// 掃描指定相簿並將照片以批次方式建立 Hash 存入 DB
  Future<void> scanAndSyncDatabase(List<AssetPathEntity> selectedAlbums) async {
    // 請求權限
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth) {
      throw Exception('無權限存取媒體庫');
    }

    for (var album in selectedAlbums) {
      final albumName = album.name;
      
      // 取得這個相簿底下的照片數量
      int assetCount = await album.assetCountAsync;
      if (assetCount == 0) continue;

      // 分批次讀取 (Batch size) 避免 OOM
      const batchSize = 100;
      for (int i = 0; i < assetCount; i += batchSize) {
        final assets = await album.getAssetListRange(start: i, end: i + batchSize);
        
        List<AssetMetadata> newAssetsToInsert = [];

        for (var asset in assets) {
          // 檢查是否已在資料庫 (依據 localId)
          final existing = await _repository.getAssetByLocalId(asset.id);
          if (existing != null && (existing.syncStatus == SyncStatus.done || existing.syncStatus == SyncStatus.verified)) {
            continue; // 已經上傳完成的略過
          }

          if (existing == null) {
            final file = await asset.file;
            if (file == null) continue;

            final modified = asset.modifiedDateTime;
            final fingerprint = await HashService.calculateFingerprint(file, modified);
            
            // 防重複上傳機制：檢查這支手機裡是否已經有「同樣 Hash」的檔案上傳過了 (例如不同相簿、複製檔案)
            final existingHash = await _repository.getAssetByHash(fingerprint);
            if (existingHash != null && (existingHash.syncStatus == SyncStatus.done || existingHash.syncStatus == SyncStatus.verified)) {
               // 已經上傳過了，直接將這張相片標記為已完成，並沿用相同的遠端 ID
               final newAsset = AssetMetadata(
                 localId: asset.id,
                 albumName: albumName,
                 hashFingerprint: fingerprint,
                 size: await file.length(),
                 syncStatus: SyncStatus.done,
                 remoteMediaItemId: existingHash.remoteMediaItemId,
                 remoteAlbumId: existingHash.remoteAlbumId,
               );
               newAssetsToInsert.add(newAsset);
               continue;
            }

            // 完全沒處理過的新檔案，標記為 Pending
            final newAsset = AssetMetadata(
              localId: asset.id,
              albumName: albumName,
              hashFingerprint: fingerprint,
              size: await file.length(),
              syncStatus: SyncStatus.pending,
            );
              
            newAssetsToInsert.add(newAsset);
          }
        }
        
        // 將這一批次的新相片存入 SQLite DB
        if (newAssetsToInsert.isNotEmpty) {
          await _repository.putAssets(newAssetsToInsert);
        }
      }
    }
  }
}
