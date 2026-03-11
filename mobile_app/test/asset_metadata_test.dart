import 'package:flutter_test/flutter_test.dart';
import 'package:gphotos_uploader_mobile/src/features/database/models/asset_metadata.dart';

void main() {
  group('AssetMetadata Model Tests', () {
    test('toMap and fromMap should work correctly', () {
      final asset = AssetMetadata(
        id: 1,
        localId: 'local_123',
        albumName: 'Camera',
        hashFingerprint: 'abc123_1024_99999',
        size: 1024,
        syncStatus: SyncStatus.done,
        remoteMediaItemId: 'remote_456',
      );

      final map = asset.toMap();

      expect(map['id'], 1);
      expect(map['localId'], 'local_123');
      expect(map['albumName'], 'Camera');
      expect(map['hashFingerprint'], 'abc123_1024_99999');
      expect(map['size'], 1024);
      expect(map['syncStatus'], SyncStatus.done.index);
      expect(map['remoteMediaItemId'], 'remote_456');

      final newAsset = AssetMetadata.fromMap(map);

      expect(newAsset.id, asset.id);
      expect(newAsset.localId, asset.localId);
      expect(newAsset.albumName, asset.albumName);
      expect(newAsset.hashFingerprint, asset.hashFingerprint);
      expect(newAsset.size, asset.size);
      expect(newAsset.syncStatus, asset.syncStatus);
      expect(newAsset.remoteMediaItemId, asset.remoteMediaItemId);
    });
  });
}
