import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gphotos_uploader_mobile/src/features/database/models/asset_metadata.dart';
import 'package:gphotos_uploader_mobile/src/features/database/repositories/asset_repository.dart';

void main() {
  group('AssetRepository DB Tests', () {
    late AssetRepository repository;
    late Database db;

    setUpAll(() {
      // Initialize sqflite ffi for testing environment
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      repository = AssetRepository();
      // overriding the database to use an in-memory db for testing
      db = await databaseFactory.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(
              version: 1,
              onCreate: (db, version) async {
                await db.execute('''
                  CREATE TABLE assets (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    localId TEXT UNIQUE NOT NULL,
                    albumName TEXT NOT NULL,
                    hashFingerprint TEXT NOT NULL,
                    size INTEGER NOT NULL,
                    syncStatus INTEGER NOT NULL,
                    remoteMediaItemId TEXT
                  )
                ''');
              }));
      await db.execute('DELETE FROM assets');
    });
    
    // We create a helper class for testing to inject the db
    test('insert and getAssetByLocalId', () async {
       final testRepo = TestAssetRepository(db);
       
       final asset = AssetMetadata(
         localId: '12345',
         albumName: 'Test Album',
         hashFingerprint: 'hash_123',
         size: 1000,
         syncStatus: SyncStatus.pending
       );
       
       await testRepo.putAsset(asset);
       
       final fetched = await testRepo.getAssetByLocalId('12345');
       expect(fetched, isNotNull);
       expect(fetched!.localId, '12345');
       expect(fetched.albumName, 'Test Album');
       expect(fetched.syncStatus, SyncStatus.pending);
    });

    test('updateStatus should change status and add remote ID', () async {
       final testRepo = TestAssetRepository(db);
       
       final asset = AssetMetadata(
         localId: 'status_test',
         albumName: 'Test Album',
         hashFingerprint: 'hash_status',
         size: 500,
         syncStatus: SyncStatus.pending
       );
       
       await testRepo.putAsset(asset);
       
       await testRepo.updateStatus('status_test', SyncStatus.done, remoteMediaItemId: 'remote_abc');
       
       final fetched = await testRepo.getAssetByLocalId('status_test');
       expect(fetched!.syncStatus, SyncStatus.done);
       expect(fetched.remoteMediaItemId, 'remote_abc');
    });

    test('getPendingAssets should only return pending items', () async {
       final testRepo = TestAssetRepository(db);
       
       await testRepo.putAssets([
         AssetMetadata(localId: '1', albumName: 'A', hashFingerprint: 'h1', size: 1, syncStatus: SyncStatus.pending),
         AssetMetadata(localId: '2', albumName: 'A', hashFingerprint: 'h2', size: 1, syncStatus: SyncStatus.uploading),
         AssetMetadata(localId: '3', albumName: 'A', hashFingerprint: 'h3', size: 1, syncStatus: SyncStatus.done),
         AssetMetadata(localId: '4', albumName: 'A', hashFingerprint: 'h4', size: 1, syncStatus: SyncStatus.pending),
       ]);
       
       final pending = await testRepo.getPendingAssets();
       expect(pending.length, 2);
       expect(pending.any((a) => a.localId == '1'), isTrue);
       expect(pending.any((a) => a.localId == '4'), isTrue);
    });
  });
}

class TestAssetRepository extends AssetRepository {
  final Database mockDb;
  TestAssetRepository(this.mockDb);

  @override
  Future<Database> get database async => mockDb;
}
