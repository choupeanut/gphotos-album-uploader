import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gphotos_uploader_mobile/src/features/database/services/hash_service.dart';
import 'package:path/path.dart' as p;

void main() {
  group('HashService Tests', () {
    late Directory tempDir;
    late File smallFile;
    late File largeFile;
    
    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('hash_test');
      
      smallFile = File(p.join(tempDir.path, 'small.txt'));
      await smallFile.writeAsString('Hello World, this is a small file.');

      largeFile = File(p.join(tempDir.path, 'large.bin'));
      // Create a dummy file larger than 512KB (e.g. 1MB)
      final bytes = List.generate(1024 * 1024, (index) => index % 256);
      await largeFile.writeAsBytes(bytes);
    });

    tearDownAll(() async {
      await tempDir.delete(recursive: true);
    });

    test('should calculate fingerprint for small file consistently', () async {
      final modified = DateTime(2023, 1, 1, 12, 0, 0);
      final hash1 = await HashService.calculateFingerprint(smallFile, modified);
      final hash2 = await HashService.calculateFingerprint(smallFile, modified);

      expect(hash1, isNotEmpty);
      expect(hash1, equals(hash2));
    });

    test('should calculate fingerprint for large file consistently without OOM', () async {
      final modified = DateTime(2023, 1, 1, 12, 0, 0);
      final hash1 = await HashService.calculateFingerprint(largeFile, modified);
      final hash2 = await HashService.calculateFingerprint(largeFile, modified);

      expect(hash1, isNotEmpty);
      expect(hash1, equals(hash2));
    });

    test('fingerprint should change if modified time changes', () async {
      final modified1 = DateTime(2023, 1, 1, 12, 0, 0);
      final modified2 = DateTime(2023, 1, 1, 12, 0, 1);
      
      final hash1 = await HashService.calculateFingerprint(smallFile, modified1);
      final hash2 = await HashService.calculateFingerprint(smallFile, modified2);

      expect(hash1, isNot(equals(hash2)));
    });
  });
}
