import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/asset_metadata.dart';

class AssetRepository {
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB('assets.db');
    return _db!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE assets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        localId TEXT UNIQUE NOT NULL,
        albumName TEXT NOT NULL,
        hashFingerprint TEXT NOT NULL,
        size INTEGER NOT NULL,
        syncStatus INTEGER NOT NULL,
        remoteMediaItemId TEXT,
        remoteAlbumId TEXT
      )
    ''');
    
    // Create index on hashFingerprint to speed up deduplication checks
    await db.execute('''
      CREATE INDEX idx_hashFingerprint ON assets (hashFingerprint)
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE assets ADD COLUMN remoteAlbumId TEXT;');
    }
  }

  Future<void> putAsset(AssetMetadata asset) async {
    final db = await database;
    await db.insert(
      'assets',
      asset.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> putAssets(List<AssetMetadata> assets) async {
    final db = await database;
    final batch = db.batch();
    for (var asset in assets) {
      batch.insert(
        'assets',
        asset.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<AssetMetadata?> getAssetByLocalId(String localId) async {
    final db = await database;
    final maps = await db.query(
      'assets',
      where: 'localId = ?',
      whereArgs: [localId],
    );

    if (maps.isNotEmpty) {
      return AssetMetadata.fromMap(maps.first);
    }
    return null;
  }
  
  Future<AssetMetadata?> getAssetByHash(String hash) async {
    final db = await database;
    final maps = await db.query(
      'assets',
      where: 'hashFingerprint = ?',
      whereArgs: [hash],
    );

    if (maps.isNotEmpty) {
      return AssetMetadata.fromMap(maps.first);
    }
    return null;
  }

  Future<List<AssetMetadata>> getPendingAssets() async {
    final db = await database;
    final maps = await db.query(
      'assets',
      where: 'syncStatus = ?',
      whereArgs: [SyncStatus.pending.index],
    );

    return maps.map((map) => AssetMetadata.fromMap(map)).toList();
  }
  
  Future<void> updateStatus(String localId, SyncStatus status, {String? remoteMediaItemId, String? remoteAlbumId}) async {
    final db = await database;
    final Map<String, dynamic> updateValues = {
      'syncStatus': status.index,
    };
    if (remoteMediaItemId != null) {
      updateValues['remoteMediaItemId'] = remoteMediaItemId;
    }
    if (remoteAlbumId != null) {
      updateValues['remoteAlbumId'] = remoteAlbumId;
    }
    
    await db.update(
      'assets',
      updateValues,
      where: 'localId = ?',
      whereArgs: [localId],
    );
  }

  /// Get statistics for all albums.
  /// Returns a map in the format:
  /// { 'Camera': { 'total': 100, 'done': 50 }, 'Screenshots': { ... } }
  Future<Map<String, Map<String, int>>> getAlbumStats() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT albumName, syncStatus, COUNT(*) as count 
      FROM assets 
      GROUP BY albumName, syncStatus
    ''');

    final Map<String, Map<String, int>> stats = {};

    for (var row in result) {
      final album = row['albumName'] as String;
      final status = SyncStatus.values[row['syncStatus'] as int];
      final count = row['count'] as int;

      if (!stats.containsKey(album)) {
        stats[album] = {'total': 0, 'done': 0, 'pending': 0, 'uploading': 0, 'failed': 0};
      }

      stats[album]!['total'] = (stats[album]!['total'] ?? 0) + count;
      
      if (status == SyncStatus.done || status == SyncStatus.verified) {
        stats[album]!['done'] = (stats[album]!['done'] ?? 0) + count;
      } else if (status == SyncStatus.pending) {
        stats[album]!['pending'] = (stats[album]!['pending'] ?? 0) + count;
      } else if (status == SyncStatus.uploading) {
        stats[album]!['uploading'] = (stats[album]!['uploading'] ?? 0) + count;
      } else if (status == SyncStatus.failed) {
        stats[album]!['failed'] = (stats[album]!['failed'] ?? 0) + count;
      }
    }

    return stats;
  }
}
