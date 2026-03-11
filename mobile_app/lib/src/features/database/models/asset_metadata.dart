enum SyncStatus {
  pending,
  uploading,
  done,
  verified,
  failed
}

class AssetMetadata {
  int? id;
  String localId;
  String albumName;
  String hashFingerprint;
  int size;
  SyncStatus syncStatus;
  String? remoteMediaItemId;
  String? remoteAlbumId;

  AssetMetadata({
    this.id,
    required this.localId,
    required this.albumName,
    required this.hashFingerprint,
    required this.size,
    required this.syncStatus,
    this.remoteMediaItemId,
    this.remoteAlbumId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'localId': localId,
      'albumName': albumName,
      'hashFingerprint': hashFingerprint,
      'size': size,
      'syncStatus': syncStatus.index,
      'remoteMediaItemId': remoteMediaItemId,
      'remoteAlbumId': remoteAlbumId,
    };
  }

  factory AssetMetadata.fromMap(Map<String, dynamic> map) {
    return AssetMetadata(
      id: map['id'] as int?,
      localId: map['localId'] as String,
      albumName: map['albumName'] as String,
      hashFingerprint: map['hashFingerprint'] as String,
      size: map['size'] as int,
      syncStatus: SyncStatus.values[map['syncStatus'] as int],
      remoteMediaItemId: map['remoteMediaItemId'] as String?,
      remoteAlbumId: map['remoteAlbumId'] as String?,
    );
  }
}
